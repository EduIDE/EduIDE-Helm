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
never published.

**It does not bump the chart version.** That is a reviewed pull request; the
workflow checks the charts are already at the requested version and fails
otherwise. Do not make automation push to `main`: it triggers the workflows
watching `main`. Full procedure in the README, and as a skill in
`.claude/skills/cut-a-release.md`.

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

## appDefinitions.apps is the single source of truth

Three things derive from it: the AppDefinition custom resources, the app list
the landing page offers, and the images the preloading DaemonSet pulls onto
every node. **Never write a preload list, and never add an app in two places.**

They used to be three hand-maintained lists across two repositories, the
preload one addressed by array index, with production's list one shorter than
test's. Production offered `c-templates` while preloading everything except
`c-templates`. `scripts/test-app-consistency.sh` asserts they agree and CI runs
it; it also fails on any floating tag in a default render.

## One version knob per source repository

`versions.ide` (EduIDE), `versions.cloud` (EduIDE-Cloud), `versions.landingPage`
(EduIDE-Landing-Page). `versions.ide` empty means the chart's `appVersion`, so
`helm install --version X` with no overrides pins every image to that release.

A deploy override names exactly one. Never set a blanket tag - a pull request
only builds the images of the repo it came from, so the rest of the namespace
goes into `ImagePullBackOff`.

The three image values are plain strings rendered through `tpl`, so they can
interpolate `.Values.versions.*` without any template change. Keep it that way:
turning them into `{registry, repository, tag}` maps would break every values
file for no gain.

## The garbage collector is pinned to a commit, not a version

Its repository has never cut a release - GHCR holds only `latest`, `main` and
per-commit SHAs - and its own chart defaults to `latest`. A released chart must
not install whatever was built most recently, and `helm upgrade` would see no
diff when it changed. `garbageCollector.image.tag` therefore pins a commit SHA.
Replace it with a semver tag when that repo starts releasing.

## Dependency aliases must be lowercase

An `alias:` becomes `.Chart.Name` inside the subchart, and charts build resource
names and label values from it. `alias: sharedCache` rendered
`sharedCache-redis`, which the API server rejects - RFC 1123 names are lowercase
only, and `helm template` renders it happily. The dependencies are declared
under their real names for that reason, so the values keys are
`eduide-shared-cache:` and `theia-workspace-garbage-collector:`.
`test-app-consistency.sh` checks every rendered name.

## One expected warning from `helm template`

```
warning: cannot overwrite table with non table for eduide-shared-cache.gateway.parentRefs
```

Both this chart and the cache subchart have a top-level `gateway:` table, and
this chart's `parentRefs` is a list where the subchart's is a map. Helm
coalesces the parent's table down and says so. The subchart's map wins, its
HTTPRoutes stay off, and only this chart's three routes render -
`test-app-consistency.sh` asserts exactly that, so the day the behaviour
changes it fails rather than quietly publishing routes for hostnames nobody
configured.

Do not parse `helm template` output with `2>&1`. That warning lands in the YAML
and anything downstream reads it as a broken document.

## Preflight checks must stay silent offline

`helm template`, the render diff and CI all run without a cluster. A preflight
that fires there breaks all three. `lookup` returns empty both offline and when
the thing is genuinely missing, so it cannot tell them apart alone - look up the
`kube-system` namespace first, and only check anything if that comes back.

The earlier version keyed off `.Release.IsInstall`, which is true under
`helm template` too. It went unnoticed because the define was never invoked from
any template. Both are fixed; the includes are at the top of `operator.yaml`,
which every install renders.

## The oauth2 ConfigMaps are not gated on keycloak.enable

They cannot be: the operator mounts `oauth2-proxy-config`, `oauth2-templates`
and `oauth2-emails` into every session pod by literal name. So a chart left at
the default `keycloak.authUrl` ships a live proxy pointed at
`https://keycloak.url/auth/realms/TheiaCloud`, and sessions fail at the proxy
instead of running unauthenticated.

`eduide.preflightKeycloak` refuses to render on the placeholder values.
An installation that genuinely has no identity provider yet sets
`keycloak.allowUnauthenticated: true`.
