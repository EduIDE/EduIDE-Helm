# test3 (EXPERIMENTAL)

Go control plane on cluster `stud`, namespace `eduide-test3`. Values: `values-test3.yaml`.
Set the `pr-<N>` image tags in the values (or with `--set`) before installing.
Run everything from the repository root. Never use another kube context.

## 1. CRDs (once per cluster)

```bash
helm upgrade --install eduide-control-plane-crds \
  oci://ghcr.io/eduide/eduide-control-plane/charts/eduide-control-plane-crds \
  --version 0.1.0 --kube-context stud
```

The CRDs are cluster wide and additive; install this chart before any deployment chart.

## 2. Namespace

```bash
kubectl --context stud create namespace eduide-test3
```

## 3. OIDC client secret (never in a file)

Copy the secret of the shared Keycloak client from test1 without printing it:

```bash
kubectl --context stud -n eduide-test1 get secret service-config-secret \
  -o go-template='{{index .data "KEYCLOAK_CLIENTSECRET" | base64decode}}' \
  | kubectl --context stud -n eduide-test3 create secret generic eduide-oidc \
      --from-file=client-secret=/dev/stdin
```

## 4. The deployment chart

```bash
helm upgrade --install eduide \
  oci://ghcr.io/eduide/eduide-control-plane/charts/eduide-go \
  --version 0.1.0 --kube-context stud -n eduide-test3 \
  -f deployments/test3/values-test3.yaml
```

Until `eduide-go` is published, package it locally (`helm dependency update charts/eduide-go`) and pass the path.
`helm template` renders without a cluster. Add `--wait` only after the images exist.

## Checks

- keycloak-test and the production Keycloak (`keycloak.aet.cit.tum.de`) accept only the TLS curves P-384 and P-521; Envoy offers X25519 and P-256. The chart's `oidcBridge` (an nginx TLS bridge in the namespace) is therefore enabled, and `providerBackendRefs` points at `eduide-oidc-bridge`. Production needs the same until Keycloak or the EnvoyProxy allow a common curve.

- cert-manager needs the Gateway API feature enabled so the Gateway annotation and the Issuer solver work.
- The `eduide` node pool has no taints on stud, so the values carry no toleration.
- Add the `artemis-test*.artemis.cit.tum.de` hosts in use to `config.allowedHosts`.
- Without `sectionName`, session routes also attach to the three HTTP :80 listeners (they serve ACME). The control plane chart has one parentRef; restrict this later if port 80 must not carry routes.
