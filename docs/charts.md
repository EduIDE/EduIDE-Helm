# The charts

Two charts, released together with the same version.

| Chart | Installed | Owns |
|---|---|---|
| `eduide-cluster` | once per **cluster** | CRDs, the conversion webhook, ClusterRoles, cert-manager issuers |
| `eduide` | once per **environment** | operator, REST service, landing page, routes, config |

```bash
# once per cluster
helm install eduide-cluster oci://ghcr.io/eduide/charts/eduide-cluster \
  --version 2.0.0 -n eduide-system --create-namespace

# once per environment
helm install eduide oci://ghcr.io/eduide/charts/eduide \
  --version 2.0.0 -n eduide-test1 -f my-values.yaml
```

## Why two charts and not one

Everything in `eduide-cluster` is cluster-scoped or singular: a CRD exists once,
and a CRD names exactly one conversion webhook service. Everything in `eduide`
exists once per environment.

Before the split, every tenant deploy also reinstalled the cluster-scoped
charts into the `default` namespace. Three concurrent test deploys therefore
raced over the same objects, which was worked around with a six-attempt retry
loop. One owner removes the race instead of retrying through it.

It also means a tenant upgrade cannot touch a CRD, so it cannot break the other
environments on the same cluster.

The one cluster-scoped exception the tenant chart owns is the operator's
unavoidable cluster-scoped access: it lists `customresourcedefinitions`
(read-only) at startup and reads `persistentvolumes`, writing them for workspace
storage only when `operator.cloudProvider` is `MINIKUBE`. A namespaced RoleBinding
can grant neither. The tenant chart therefore
renders a minimal `operator-api-access-cluster-<namespace>` ClusterRole and
ClusterRoleBinding, named per namespace so tenants never collide on them. The
broad, namespaced operator verbs stay bound through the shared
`operator-api-access` ClusterRole (a RoleBinding by default, see
`operator.clusterWideRbac`). That role includes write verbs on
`persistentvolumes` and `customresourcedefinitions`, so setting
`operator.clusterWideRbac=true` grants those writes cluster-wide.

### The conversion webhook belongs to the cluster

A CRD's `conversion.webhook.clientConfig.service` names one namespace and one
service. If the webhook were a tenant resource, "which of the four environments
on this cluster serves CRD conversion?" would have no answer, and tenants on
different chart versions would fight over one conversion schema.

## Install order

`eduide-cluster` first. The tenant chart checks for it and fails with a usable
message if it is missing; without that check the first symptom is the operator
crash-looping on an absent CRD. Set `skipPreflight=true` to bypass it.

## CRDs are annotated `helm.sh/resource-policy: keep`

`helm uninstall eduide-cluster` will not delete them. Deleting a CRD deletes
every object of that kind, which here means every live Session, Workspace and
AppDefinition on the cluster. Remove them by hand if you really mean to.

They are ordinary templates rather than files under `crds/`, because Helm never
upgrades anything in `crds/` and these change with almost every release
(`v1beta8` through `v1beta11` so far).

## Renaming an existing installation

Helm will not manage an object it did not create, so pointing a new release
name at existing objects normally deletes and recreates everything. Adopt them
instead:

```bash
DRY_RUN=1 ./scripts/adopt-release.sh test1 eduide \
  deploy/operator-deployment deploy/service-deployment deploy/landing-page-deployment
```

Drop `DRY_RUN` once the output looks right, then upgrade under the new name.

## Resource names are deliberately not release-prefixed

The operator mounts `oauth2-proxy-config`, `oauth2-templates` and
`oauth2-emails` **by literal name** into every session pod
(`AddedHandlerUtil.java:88` and `templateDeployment.yaml`). Prefixing them would
break every running session.

One install means one namespace, so prefixing buys no collision protection
anyway. Standard `app.kubernetes.io/*` labels give the same grouping without
the rename, and labels are additive on upgrade.

## Maintenance page and rolling updates

While the landing page has no ready pod, Envoy would answer with a bare
`no healthy upstream`. The `eduide` chart ships a `BackendTrafficPolicy` on
`landing-route` that replaces every 502/503/504 there with
`charts/eduide/files/maintenance.html` ("EduIDE is currently unavailable").
Envoy serves the page from the `maintenance-page` ConfigMap itself, so it works
with the landing page down and loads nothing from anywhere else. The status
code stays 5xx. It needs Envoy Gateway; turn it off with
`maintenancePage.enabled: false` elsewhere.

Keep `%` out of the page. Envoy reads the body as a format string, rejects
the override because of it and still reports the policy as Accepted, so
visitors get an empty 503. `scripts/test-maintenance-page.sh` checks for it.

It covers the landing page only. The REST service and sessions keep their own
errors, and nothing helps while Envoy itself is down.

To show the page on purpose, scale `landing-page-deployment` to 0 - the
`maintenance.yml` workflow in EduIDE-deployment does exactly that. The next
deploy scales it back.

So that deploys rarely show it:

- the landing page and REST service start the new pod before stopping the old
  one (`maxUnavailable: 0`), and the REST service is only ready once its port
  is open
- both sleep 10s in `preStop`, so Envoy stops sending traffic before the
  process exits
- `landingPage.replicas` / `service.replicas` above 1 add a
  PodDisruptionBudget each (`podDisruptionBudget.enabled`, off on single-node
  clusters, where it would block every drain) and prefer different nodes

## Pinning EduIDE to a node pool

`global.nodeSelector` pins every EduIDE pod to the nodes carrying those labels,
so sessions start where their images are preloaded. Set it on both charts:

```yaml
global:
  nodeSelector:
    aet.cit.tum.de/pool: pve
```

The `eduide` chart renders it on the operator, the REST service, the landing
page and image preloading, and passes it to the operator as
`--sessionNodeSelector aet.cit.tum.de/pool=pve` for the session pods it creates.
`eduide-cluster` renders it on the conversion webhook. Helm hands `global` to
the garbage collector, which reads it from its next chart version. The shared
cache does not read it. It is a plain node selector: the nodes need no taint and stay open to
other workloads. With too few labelled nodes, sessions stay `Pending`.

`preloading.nodeSelector` still works on its own and wins when set.
`scripts/test-node-selector.sh` checks every workload gets the selector.

## Deployer ServiceAccounts

A deploy workflow should not hold cluster-admin. `eduide-cluster` can create,
per tenant namespace, a ServiceAccount that installs, upgrades, rolls back and
uninstalls the `eduide` chart there and does nothing else:

```yaml
deployers:
  enabled: true
  namespaces: [eduide-test1, eduide-test2]
```

Each namespace gets the ServiceAccount `eduide-deployer`, its token Secret
`eduide-deployer-token`, a Role and RoleBinding for what the chart renders, a
Role in `eduide-system` to read the `eduide-cluster-identity` ConfigMap, and a
ClusterRole `eduide-deployer-<namespace>` for the operator's one cluster-scoped
grant. Read the token with:

```bash
kubectl -n eduide-test1 get secret eduide-deployer-token -o jsonpath='{.data.token}' | base64 -d
```

They live in the cluster chart because it is installed with cluster-admin.
From the tenant chart they would be chicken-and-egg, and `helm uninstall`
would delete the access along with the release. The namespaces must exist
first: the chart does not create or own them, so its uninstall cannot delete a
tenant.

Kubernetes refuses to let the deployer create a Role with rights it does not
hold itself, so the deployer holds every right the chart's own Roles grant -
which is why it can delete pods. `scripts/test-deployers.sh` renders `eduide`
with every optional kind on and fails when it renders a kind, or a Role rule,
the deployer does not cover. Adding either to `eduide` means updating
`charts/eduide-cluster/templates/rbac/deployers.yaml` in the same change.

`operator.clusterWideRbac: true` and `operator.cloudProvider: MINIKUBE` grant
the operator cluster-wide rights the deployer lacks, so those installations
need a broader kubeconfig.

## Checking a change

```bash
helm lint charts/eduide charts/eduide-cluster
./scripts/render-envs.sh /tmp/out                # render every real environment
```

CI additionally renders the PR base and head and posts the diff, which is the
only reliable answer to "what will this do to production". For a pure refactor
the expected result is an empty diff.
