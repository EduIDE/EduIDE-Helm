# EduIDE Helm Charts

The installable EduIDE platform. Two charts, published as OCI artifacts to
`ghcr.io/eduide/charts`.

| Chart | Installed | Owns |
|---|---|---|
| `eduide-cluster` | once per **cluster** | CRDs, conversion webhook, ClusterRoles, cert-manager issuers |
| `eduide` | once per **environment** | operator, REST service, landing page, routes |

```bash
# once per cluster
helm install eduide-cluster oci://ghcr.io/eduide/charts/eduide-cluster \
  --version 2.0.0 -n eduide-system --create-namespace

# once per environment
helm install eduide oci://ghcr.io/eduide/charts/eduide \
  --version 2.0.0 -n eduide-test1 -f my-values.yaml
```

Both charts always carry the same version. `docs/charts.md` explains why the
split exists and what it is safe to change.

## What one install pins

A bare `--version 2.0.0` with no overrides pins every image. Nothing floats.

| Value | Source repository | Default |
|---|---|---|
| `versions.ide` | EduIDE (the IDE images) | empty → the chart's `appVersion` |
| `versions.cloud` | EduIDE-Cloud (operator, REST service) | `1.2.0` |
| `versions.landingPage` | EduIDE-Landing-Page | `1.2.0` |

The three release on their own cadence, so each has its own knob and an
override names exactly one. A blanket tag would be wrong: a pull request only
builds the images of the repo it came from, so pointing everything at `pr-451`
puts the rest of the namespace into `ImagePullBackOff`.

## Choosing and adding IDE apps

`appDefinitions.catalog` holds the IDE images EduIDE officially releases.
An installation adds its own apps or changes a catalog entry under
`appDefinitions.apps`, and picks what it offers with `appDefinitions.enabled`.
An empty `enabled` (the default) offers every definition, catalog and `apps`
alike:

```yaml
appDefinitions:
  enabled:                  # names from the catalog or from apps
    - java-25-templates
    - python
    - haskell
  apps:
    python:                 # merged over the catalog entry
      limitsMemory: 4000M
    haskell:                # your own image
      image: registry.example.edu/ide/haskell:2.1.0   # a tag or digest is used as given
      limitsMemory: 4000M
      landingPage:
        label: Haskell             # omit landingPage to deploy it but hide it
        image: theia-logo.png      # a logo the landing page ships, or a path starting with /
```

Each app is `appDefinitions.defaults`, then its catalog entry, then its `apps`
entry. A bare repository such as `eduide/java-17` gets the tag from
`versions.ide`. `apps.<name>: null` removes an app. A name in `enabled` with
no definition is skipped, and `helm install` or `helm upgrade` prints a warning
naming it.

That one merged list drives the AppDefinition custom resource, the landing
page's app list, and the set of images preloaded onto every node. It used to be
three hand-maintained lists across two repositories, the preload one addressed
by array index - which is how production came to offer `c-templates` while
preloading everything except `c-templates`.
`scripts/test-app-consistency.sh` asserts the three agree, and CI runs it.

Environment configuration for the TUM installations lives in
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

Both charts, one version; `appVersion` and the `versions.*` pins at the
component releases you want to ship:

```yaml
# charts/eduide/Chart.yaml  AND  charts/eduide-cluster/Chart.yaml
version: 2.3.0
```

```bash
docker run --rm -v "$PWD/charts:/helm-docs" -u "$(id -u)" jnorwood/helm-docs:v1.14.2
```

Move the `## [Unreleased]` entries under `## [eduide 2.3.0] - YYYY-MM-DD`,
open the PR, let CI run, get it reviewed, merge.

### 2. Run the release

```bash
gh workflow run release.yml -R EduIDE/EduIDE-Helm -f version=2.3.0
```

It then, in this order:

1. **checks** that the IDE, Cloud (operator, service, conversion webhook) and
   landing page images the charts pin exist and are multi-arch, and that the
   chart versions are not published yet
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
# environments/prod-tum/env.yaml
spec:
  platform:
    chartVersion: 2.3.0    # the only line that changes
```

Merge that, then run `Deploy environment`. Production is never deployed
automatically.

## Release candidates

Run `release.yml` with `-f version=2.3.0-rc.1`, from any branch: same pipeline,
same registry, marked as a prerelease on GitHub. The version files are not
checked for a release candidate; the charts are stamped with it. Consume with
an explicit `--version`; never `--devel`.

## Versioning rules

| Thing | Form | Example |
|---|---|---|
| git tag | `vX.Y.Z` | `v2.3.0` |
| chart `version` | `X.Y.Z` | `2.0.0` |
| chart `appVersion` | the EduIDE IDE image version | `1.2.0` |
| image tag | `X.Y.Z` | `1.2.0` |

`appVersion` is the tag of the IDE images, so a chart says exactly which IDEs it
runs. The operator, REST service and landing page carry their own versions in
`versions.cloud` and `versions.landingPage`, because they release on a different
cadence and a one-line landing page fix should not rebuild fifteen
multi-gigabyte IDE images.

The chart version is the platform version and is what an environment pins.

## Checklist

```
[ ] both Chart.yaml files at the same `version`
[ ] `appVersion` set to the EduIDE release the IDE images were published under
[ ] `versions.cloud` and `versions.landingPage` set to their releases
[ ] scripts/test-app-consistency.sh passes (no floating tags, three consumers agree)
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
  `gateway.className` (default `envoy`).

## Working on the charts

```bash
helm lint charts/eduide charts/eduide-cluster
./scripts/render-envs.sh /tmp/out          # renders every real environment
```

CI also renders the PR base and head and posts the diff. **For a refactor the
expected result is an empty diff** — that is the acceptance criterion, not "it
still lints".

See `AGENTS.md` for the things that catch people out, and
`.claude/skills/chart-change.md` for the loop to follow when editing a template.
