# AGENTS.md - EduIDE-Helm

The Helm charts of EduIDE 3.0 on the Go control plane. This is the installable
product: an administrator anywhere gets EduIDE from here. The Java (Theia Cloud)
charts of 2.x live on the branch release/2.x.

`CLAUDE.md` is a symlink to this file.

## Two charts

| Chart | Installed | Owns |
|---|---|---|
| `eduide-cluster` | once per **cluster** | control plane CRDs (dependency `eduide-control-plane-crds`), cluster identity ConfigMap, optional GatewayClass and EnvoyProxy, optional cert-manager alerting |
| `eduide` | once per **deployment** | control plane and landing page (dependencies), Gateway, optional ACME Issuer, OIDC bridge, IDETemplates and IDEPools |

Released together, same version. Deployment values live in
**EduIDE-deployment**, not here; `deployments/test3` is an example.

## Before you change a template

```bash
./scripts/resolve-deps.sh
helm lint charts/eduide charts/eduide-cluster
./scripts/test-eduide.sh        # CP_CHARTS=<EduIDE-control-plane>/charts for unreleased subcharts
```

`scripts/test-eduide.sh` renders both charts with the CI and test3 values and
asserts the rules below. CI also renders the PR base and head of every
EduIDE-deployment environment whose `chartVersion` is 3.0.0-rc.9 or newer
(`scripts/render-envs.sh`); until one moves to 3.x that diff is empty.

## Things that will catch you out

**The Theia Cloud guard.** `charts/eduide-cluster/templates/theia-guard.yaml`
fails an install or upgrade while the CRD `appdefinitions.theia.cloud` exists
(a 2.x cluster), unless `allowRemovingTheiaCloud: true`. It protects every
session and workspace of that cluster. `lookup` is empty under `helm template`;
the logic is tested through a wrapper chart in `scripts/test-eduide.sh`. Never
remove the guard.

**Three hostnames, no wildcard.** The `eduide` Gateway has HTTPS listeners for
the service host, the instance host and `webview.<instance host>` and HTTP :80
listeners for ACME. `charts/eduide/templates/validate.yaml` refuses a render where the two
subcharts disagree on hosts, gateway or Keycloak client.

**The IDE image tag follows `appVersion`.** `images.tag` is empty by default;
a template's own `tag` wins over it. Never default it to `latest`.

**`listed`.** The artemis editions (`<lang>`) are `listed: false`, the
`<lang>-standalone` editions are listed. `listed` renders to
`IDETemplate.spec.listed` and only hides the start tile; launches by name still
work.

**`mergeGateways` defaults to true** in the EnvoyProxy of `eduide-cluster`, so
all deployments of a cluster share one data plane.

## `lookup` makes rendering nondeterministic

`lookup` returns empty under `helm template`. Keep templates correct for both
cases, and test the cluster-side behavior through a wrapper chart or a local
kind cluster with an isolated `KUBECONFIG`. Never test against the default kube
context.

## Releasing

Releases are manual. A release pull request moves the CHANGELOG entries under
the new version and bumps both charts; after it merges, `release.yml`
(`workflow_dispatch`, input `version`) verifies every pinned image, drafts
the GitHub Release from the CHANGELOG section, publishes both charts to OCI
and finally publishes the release, which creates the tag. Nothing releases on push to `main`, and automation never pushes to
`main`. Procedure in the README, and as a skill in
`.claude/skills/release/SKILL.md`.

## Conventions

- Do not bump the chart version in a feature or fix PR. Add the entry under
  `## [Unreleased]` in `CHANGELOG.md`; the release pull request bumps the
  version. CI still checks that both charts carry the same version.
- Chart READMEs are generated. Run helm-docs and commit the result; CI fails on
  drift.
- The subchart versions (`eduide-control-plane`, `eduide-landing-page` and
  `eduide-control-plane-crds`) must be the same release of EduIDE-control-plane.

## Renovate

`renovate.json` extends `local>EduIDE/.github:renovate-config`, the org-wide
preset, and adds one rule that groups the control plane subcharts into one pull
request. The `helmv3` manager reads the `dependencies:` blocks of
`charts/eduide/Chart.yaml` and `charts/eduide-cluster/Chart.yaml`. Nothing is
automerged.

Expect a Renovate pull request touching a chart to arrive **red** until an entry
under `## [Unreleased]` in `CHANGELOG.md` and regenerated chart READMEs are
added by hand.

## Always resolve dependencies before touching a chart

`charts/*/charts/` is gitignored - dependencies are resolved, not vendored,
which is what stops Chart.lock, Chart.yaml and HEAD drifting apart the way they
used to. The cost is that a fresh checkout has none, and `helm template`,
`helm package` and `helm dependency list` all refuse outright rather than
degrading.

Call `scripts/resolve-deps.sh <chart>` first; every caller does. The
dependencies are OCI charts from `oci://ghcr.io/eduide/eduide-control-plane/charts`.
