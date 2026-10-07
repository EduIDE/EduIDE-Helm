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

## Checking a change

```bash
helm lint charts/eduide charts/eduide-cluster
./scripts/render-envs.sh /tmp/out                # render every real environment
```

CI additionally renders the PR base and head and posts the diff, which is the
only reliable answer to "what will this do to production". For a pure refactor
the expected result is an empty diff.
