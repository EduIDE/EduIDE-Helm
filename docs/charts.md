# The charts

Two charts, released together with the same version.

| Chart | Installed | Owns |
|---|---|---|
| `eduide-cluster` | once per **cluster** | control plane CRDs, cluster identity ConfigMap, optional GatewayClass and EnvoyProxy, optional cert-manager alerting |
| `eduide` | once per **deployment** (one namespace) | control plane, landing page, Gateway, optional ACME Issuer, OIDC bridge, IDETemplates and IDEPools |

```bash
# once per cluster
helm install eduide-cluster oci://ghcr.io/eduide/charts/eduide-cluster \
  --version <chart version> -n eduide-system --create-namespace --set clusterName=<name>

# once per deployment
helm install eduide oci://ghcr.io/eduide/charts/eduide \
  --version <chart version> -n my-deployment --create-namespace -f my-values.yaml
```

## Why two charts and not one

A CRD exists once per cluster, a Gateway data plane and the cluster identity too.
Everything in `eduide` exists once per deployment. One owner for the cluster
objects means a deployment upgrade cannot touch a CRD, so it cannot break the
other deployments on the same cluster.

`eduide-cluster` pulls the CRDs in through its dependency
`eduide-control-plane-crds`. Clusters that must not get the rest of the chart
install that CRD chart alone.

## The Theia Cloud guard

Version 3 ships no Theia CRDs. Upgrading `eduide-cluster` from 2.x on a cluster
that still runs Theia Cloud would delete them and with them every session and
workspace. `templates/theia-guard.yaml` looks up `appdefinitions.theia.cloud` and
fails the install or upgrade while it exists, unless `allowRemovingTheiaCloud` is
true. `lookup` is empty under `helm template`, so the guard only fires against a
cluster; `scripts/test-eduide.sh` tests the logic through a wrapper chart.

## Merged gateways

The EnvoyProxy rendered by `eduide-cluster` sets `mergeGateways: true`, so the
Gateway of every deployment on the cluster shares one Envoy data plane (one
load balancer, one hostPort). Set `envoyProxy.spec.mergeGateways: false` to
change that.

## Install order

`eduide-cluster` (or the CRD chart) first, then the `eduide` releases. The
control plane crash-loops on absent CRDs otherwise.

## CRDs

The CRDs are templates of `eduide-control-plane-crds`, not files under `crds/`,
so Helm upgrades them. See that chart's README for its uninstall behavior.

## Renaming an existing release

Helm will not manage an object it did not create. Adopt the objects instead:

```bash
DRY_RUN=1 ./scripts/adopt-release.sh my-deployment eduide deploy/<name>
```

Drop `DRY_RUN` once the output looks right, then upgrade under the new name.

## Checking a change

```bash
./scripts/resolve-deps.sh
helm lint charts/eduide charts/eduide-cluster
./scripts/test-eduide.sh
```
