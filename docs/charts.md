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

## Checking a change

```bash
helm lint charts/eduide charts/eduide-cluster
./scripts/render-envs.sh /tmp/out                # render every real environment
```

CI additionally renders the PR base and head and posts the diff, which is the
only reliable answer to "what will this do to production". For a pure refactor
the expected result is an empty diff.
