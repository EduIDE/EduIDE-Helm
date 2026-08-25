# AGENTS.md — EduIDE-Helm

The Helm charts. This is the installable product: an administrator anywhere
gets EduIDE from here.

`CLAUDE.md` is a symlink to this file.

## Two charts

| Chart | Installed | Owns |
|---|---|---|
| `eduide-cluster` | once per **cluster** | CRDs, conversion webhook, ClusterRoles, cert-manager issuers |
| `eduide` | once per **environment** | operator, REST service, landing page, routes |

Released together, same version. Environment values live in
**EduIDE-deployment**, not here.

## Before you change a template

```bash
helm lint charts/eduide charts/eduide-cluster
./scripts/render-envs.sh /tmp/out          # renders every real environment
```

CI additionally renders the PR base and head and posts the diff. **For a pure
refactor the expected result is an empty diff.** That is the acceptance
criterion, not "it still lints".

## Things that will catch you out

**Do not release-prefix resource names.** The operator mounts
`oauth2-proxy-config`, `oauth2-templates` and `oauth2-emails` **by literal name**
into every session pod — see `AddedHandlerUtil.java:88` and
`templateDeployment.yaml` in EduIDE-Cloud. Renaming them breaks every running
session. One install is one namespace, so prefixing buys no collision
protection anyway. Use `app.kubernetes.io/*` labels for grouping; they are
additive on upgrade.

**CRDs are templates, not `crds/`.** Helm never upgrades anything in `crds/`,
and these change most releases (`v1beta8` through `v1beta11`). They carry
`helm.sh/resource-policy: keep` because deleting a CRD deletes every live
Session, Workspace and AppDefinition on the cluster.

**The conversion webhook belongs to the cluster chart.** A CRD names exactly
one conversion service, so it cannot be a per-environment resource.

**Preloading must not be under `--wait`.** It pulls ~10 multi-GB images on every
node. Inside the main release it would time out and `--atomic` would roll back a
healthy deploy.

**`hosts.usePaths` is gone.** Do not reintroduce path-based routing without
wiring it through the Gateway API properly; it branched in seven files and no
environment ever set it.

**Host names come from the helpers.** `theia-cloud.host.{base,landing,service,instance}`
and `theia-cloud.url.service` in `_helpers.tpl`. Before those existed the same
two-line `printf` was re-derived inline in about a dozen places, each wrapped in
`tpl (X | toString) .`.

## `lookup` makes rendering nondeterministic

`theia-appdefinitions` preserves live scaling values and `theia-shared-cache`
generates a Redis password when its lookup finds nothing. Both are correct, but
`lookup` returns empty under `helm template`, so both are masked in
`scripts/render-envs.sh`. **Add any new `lookup` to the mask list**, or
render-diff fills with false changes and stops being read.

## Releasing

`Release train` cuts a version across all four repositories. It builds, then
verifies every image exists and is multi-arch, and only then tags — because a
failure after tagging strands immutable tags on repositories whose images were
never published. See `docs/releasing.md`.

## Conventions

- A changed chart must have a bumped version. CI enforces this: `release.yml`
  skips a version that already exists, so a forgotten bump publishes nothing
  and fails silently. It has happened three times.
- Chart READMEs are generated. Run helm-docs and commit the result; CI fails on
  drift.
- `kubeconform` skips `HTTPRoute`: the CRDs-catalog schema declares
  `minItems: 1` on `spec.rules`, but the upstream Gateway API CRD does not, and
  `httproute-instances.yaml` ships `rules: []` deliberately for the operator to
  patch.
