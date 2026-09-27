---
name: cut-a-release
description: Release an EduIDE chart, which is what moves a component version into the environments. Use when asked to release, cut a version, publish charts, ship a version of EduIDE, or move an environment to a new IDE version.
---

# Cutting a release

**Each repository releases on its own cadence.** EduIDE cuts `v1.3.0`, EduIDE-Cloud
cuts its own, the landing page cuts its own. A chart release then says which of
those versions belong together, and a deployment PR says which environments get
them.

So "release EduIDE 1.3.0 to production" is three merges in three repositories,
in this order. None of them is optional and the order is not a preference.

```
EduIDE            release v1.3.0        images published as 1.3.0
EduIDE-Helm       chart 2.3.0           appVersion 1.3.0 -> every IDE image
EduIDE-deployment chartVersion 2.3.0    merging this IS the deploy
```

## What a chart version pins

One knob per source repository, and the chart version is the name for the set:

| Value | Repository | Renders as |
|---|---|---|
| `appVersion` in `Chart.yaml` | EduIDE | every IDE image tag |
| `versions.cloud` in `values.yaml` | EduIDE-Cloud | operator, service, conversion webhook |
| `versions.landingPage` in `values.yaml` | EduIDE-Landing-Page | the landing page |

`versions.ide` in an environment's values overrides `appVersion` for that
installation. It exists for pinning an unreleased image - a `pr-123` tag - and
every use of it is temporary. If one is in place, the comment beside it should
say what has to become true before it goes, and that condition should be checked
whenever a release moves past it.

## 1. The component release exists first

Whatever you are pinning must already be published. Check, do not assume:

```bash
gh release view v1.3.0 --repo EduIDE/EduIDE
gh run list --repo EduIDE/EduIDE --event release --limit 1   # did the build finish?
docker manifest inspect ghcr.io/eduide/eduide/java-17:1.3.0  # did it publish?
```

A GitHub release existing means somebody clicked release. It does **not** mean
the images exist: the build runs after the tag, takes the better part of an
hour, and can fail. `release.yml` now refuses to publish a chart whose pinned
images are missing, so getting this wrong costs a red build rather than an
`ImagePullBackOff` in production - but it is still the first thing to check.

## 2. Bump the chart in a pull request

Both charts carry the same version - CI enforces it - and only `appVersion`
moves with the component:

```yaml
# charts/eduide/Chart.yaml
version: 2.3.0          # and the same in charts/eduide-cluster/Chart.yaml
appVersion: "1.3.0"     # the EduIDE release being pinned
```

Chart version is semver about **the chart**: a values change that alters
rendered output is a minor, a fix is a patch. It does not track the component
version and never has.

Then regenerate the READMEs, or `docs-drift` fails - the version badges come
from `Chart.yaml`:

```bash
docker run --rm -v "$PWD/charts:/helm-docs" -u "$(id -u)" jnorwood/helm-docs:v1.14.2
```

Open the PR, let CI run, and do not merge it yourself unless asked.

## 3. Merging publishes and releases it

`release.yml` runs on push to `main` and does four things in order:

1. verifies every image the chart pins exists and is multi-arch
2. packages and pushes any chart whose version is not already published
3. tags the repository `vX.Y.Z`
4. creates a GitHub release naming what the version pins, with generated notes

Step 1 reads the IDE image list from EduIDE's build matrix at run time rather
than from a list here, because a hand-kept copy drifts the moment somebody adds
an image and then a release verifies a subset and passes.

If `main` carries no version bump, steps 2 to 4 do nothing. That is every
ordinary merge.

## 4. Roll it out

Nothing here deploys. In EduIDE-deployment, bump `spec.platform.chartVersion` in
the relevant `environments/*/env.yaml`, in a pull request - staging first, then
production, in separate PRs so production can be reverted without reverting the
environment that proved it. Merging the production one is the deploy.

## The release train is a different thing

`release-train.yml` moves **all four repositories to one number** and requires
both charts to carry that number in both `version` and `appVersion`. That is a
deliberate lockstep release, not this process, and running it against an
ordinary `main` fails its pre-check by design.

Reach for it only when you actually want every component rebuilt and retagged
together. Almost nothing needs that.

## Common failures

| Message | Meaning |
|---|---|
| `missing ghcr.io/...` in Release Charts | step 1 - the component release's build has not finished, or failed |
| `is not multi-arch` | one architecture failed in the component build; re-run that build, not this one |
| `eduide is X but eduide-cluster is Y` | the two charts drifted; they release together at one version |
| `changed but version is still X` | a chart changed with no bump; `release.yml` would publish nothing |
| `chart READMEs are out of date` | run helm-docs and commit the result |
| `tag vX.Y.Z already exists` | the charts were published under that version already; bump |
| Chart published but no release | the tag already existed - the charts are out, only the release page is missing |
