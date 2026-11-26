# EduIDE Helm Charts

The installable EduIDE 3.0 platform on the Go control plane
([EduIDE-control-plane](https://github.com/EduIDE/EduIDE-control-plane)). Two
charts, published as OCI artifacts to `ghcr.io/eduide/charts`. The Java (Theia
Cloud) charts of EduIDE 2.x live on the branch `release/2.x`.

| Chart | Installed | Owns |
|---|---|---|
| `eduide-cluster` | once per **cluster** | control plane CRDs, cluster identity ConfigMap, optional GatewayClass and EnvoyProxy, optional cert-manager alerting |
| `eduide` | once per **deployment** (one namespace) | control plane, landing page, Gateway, optional ACME Issuer, IDETemplates and IDEPools |

```bash
# once per cluster
helm install eduide-cluster oci://ghcr.io/eduide/charts/eduide-cluster \
  --version <chart version> -n eduide-system --create-namespace --set clusterName=<name>

# once per deployment
helm install eduide oci://ghcr.io/eduide/charts/eduide \
  --version <chart version> -n my-deployment --create-namespace -f my-values.yaml
```

Both charts always carry the same version. Take `<chart version>` from the
[releases page](https://github.com/EduIDE/EduIDE-Helm/releases); pass a
prerelease such as `3.0.0-rc.12` explicitly, because `helm` skips prereleases
otherwise. `docs/charts.md` explains why the split exists.

**Never upgrade `eduide-cluster` on a cluster that still runs a 2.x Theia Cloud
installation.** The chart refuses (see "Upgrading from 2.x" in the CHANGELOG).

## What one install pins

A bare `--version <chart version>` with no overrides pins every image. Nothing floats.

| Image | Pinned by |
|---|---|
| IDE images (EduIDE) | chart `appVersion`; `images.tag` overrides it |
| control plane and landing page | the `eduide-control-plane` and `eduide-landing-page` dependencies in `charts/eduide/Chart.yaml` |
| CRDs | the `eduide-control-plane-crds` dependency in `charts/eduide-cluster/Chart.yaml` |

A pull request only builds the images of the repository it came from, so
override one thing at a time: `images.tag` for the IDE images, or a template's
own `tag` under `templates.<name>`.

## Choosing IDE templates

`catalog` in `charts/eduide/values.yaml` holds the IDE images EduIDE releases.
A deployment picks what it offers with `templates`: catalog name to overrides,
merged over the catalog entry. An entry without a catalog match needs
`displayName` and `image`.

```yaml
templates:
  java-25-standalone: {pool: {minIdle: 1, maxInstances: 5}}
  python-standalone: {}
  haskell:                         # your own image
    displayName: Haskell
    image: registry.example.edu/ide/haskell:2.1.0
```

Every language comes in two editions:

| Template | Image | Offered on the landing page | Started from |
|---|---|---|---|
| `<lang>` (no suffix) | `eduide/<lang>-artemis` | no (`listed: false`) | Artemis, by name |
| `<lang>-standalone` | `eduide/<lang>-standalone` | yes | the landing page |

`<lang>` is one of `java-17`, `java-25`, `python`, `javascript`, `c`, `rust`,
`go`. `listed` only hides the start tile; starts by name still work. Hosts,
gateway and OIDC settings are stated once under the subcharts and checked
against each other at render time. `deployments/test3/` is a worked example.

The configuration of the TUM installations lives in
[EduIDE-deployment](https://github.com/EduIDE/EduIDE-deployment), not here.

---

# Cutting a release

Nothing releases on push to `main`. A release is a reviewed pull request
followed by a manual run of `release.yml`. The `release` skill
(`.claude/skills/release/SKILL.md`) walks through it: it proposes the version,
checks the EduIDE components this repository pins against their latest
releases, writes the CHANGELOG section and opens the pull request.

Chart changes need no version bump. They go under `## [Unreleased]` in
`CHANGELOG.md`; the version moves in the release pull request only.

## The two steps

### 1. Release pull request

Both charts, one version; `appVersion` at the EduIDE release whose IDE images
you want to ship and the dependency versions at the control plane release:

```yaml
# charts/eduide/Chart.yaml  AND  charts/eduide-cluster/Chart.yaml
version: 3.0.0
appVersion: "3.0.0"
```

```bash
docker run --rm -v "$PWD/charts:/helm-docs" -u "$(id -u)" jnorwood/helm-docs:v1.14.2
```

Move the `## [Unreleased]` entries under `## [eduide 3.0.0] - YYYY-MM-DD`,
open the PR, let CI run, get it reviewed, merge.

### 2. Run the release

```bash
gh workflow run release.yml -R EduIDE/EduIDE-Helm -f version=3.0.0
```

It then, in this order:

1. **checks** that the IDE images (at `appVersion`) and the control plane images
   (operator, service, authz, agent, usage-export, pool-scaler, landing-page, at the subchart
   `appVersion`) exist and are multi-arch, and that the chart versions are not
   published yet
2. **validates** the version (semver, newer than the last release, matches both
   `Chart.yaml` files, CHANGELOG section exists) and creates a draft GitHub
   Release from the CHANGELOG section
3. **publishes** both charts to `oci://ghcr.io/eduide/charts` and adds what the
   version pins to the release notes
4. **verifies** both charts can be pulled
5. **publishes the release**, which creates the `vX.Y.Z` tag

The tag appears last on purpose: a missing image or a failed push leaves a
draft, not a tag for charts that were never published.

## Rolling it out

A release deploys nothing. In EduIDE-deployment:

```yaml
# environments/eduide.artemis.cit.tum.de/env.yaml
spec:
  platform:
    chartVersion: 3.0.0    # the only line that changes
```

Merge that, then run `Deploy environment`. Production is never deployed
automatically.

## Release candidates

Run `release.yml` with `-f version=3.0.0-rc.1`, from any branch: same pipeline,
same registry, marked as a prerelease on GitHub. The version files are not
checked for a release candidate; the charts are stamped with it. Consume with
an explicit `--version`; never `--devel`.

## Versioning rules

| Thing | Form | Example |
|---|---|---|
| git tag | `vX.Y.Z` | `v3.0.0` |
| chart `version` | `X.Y.Z` | `3.0.0` |
| chart `appVersion` | the EduIDE IDE image version | `3.0.0` |
| image tag | `X.Y.Z` | `3.0.0` |

`appVersion` is the tag of the IDE images, so a chart says exactly which IDEs it
runs. The control plane and the landing page are dependencies with their own
versions, because they release on a different cadence and a one-line landing
page fix should not rebuild the multi-gigabyte IDE images.

The chart version is the platform version and is what an environment pins.

## Checklist

```
[ ] both Chart.yaml files at the same `version`
[ ] `appVersion` set to the EduIDE release the IDE images were published under
[ ] dependency versions set to the control plane release
[ ] scripts/test-eduide.sh passes
[ ] helm-docs run, READMEs committed
[ ] CHANGELOG section `## [eduide X.Y.Z]` written
[ ] release PR reviewed and merged
[ ] release.yml run
[ ] chartVersion bumped in EduIDE-deployment for the environments to move
```

## If something goes wrong

| Symptom | Cause | Fix |
|---|---|---|
| `version is 'X', expected 'Y'` | release PR missed a Chart.yaml | bump both charts |
| `missing ghcr.io/...` | a component build failed or is not released | check that repository's Actions, release it first |
| `is not multi-arch` | one architecture failed | re-run that repository's build |
| `Tag vX.Y.Z already exists` / `already published` | version already used | pick the next one, tags are immutable |
| `No '## [eduide X.Y.Z]' section` | CHANGELOG not moved in the release PR | fix it in a new PR |

---

## Cluster prerequisites

- **cert-manager** - certificate management, including Let's Encrypt.
  [Install](https://cert-manager.io/docs/installation/helm/).
- **Envoy Gateway** with the Gateway API CRDs. The GatewayClass name must match
  `gateway.className` of the `eduide` release; `eduide-cluster` can create the
  GatewayClass and EnvoyProxy (`gatewayClass.create`, `envoyProxy.create`).

## Working on the charts

```bash
./scripts/resolve-deps.sh                  # fetch the subcharts first
helm lint charts/eduide charts/eduide-cluster
./scripts/test-eduide.sh                   # CP_CHARTS=<EduIDE-control-plane>/charts for unreleased subcharts
```

CI also renders the PR base and head of every environment that runs 3.x and
posts the diff; until EduIDE-deployment moves an environment to 3.x that diff is
empty.

See `AGENTS.md` for the things that catch people out, and
`.claude/skills/chart-change.md` for the loop to follow when editing a template.
