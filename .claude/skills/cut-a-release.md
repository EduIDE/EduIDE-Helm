---
name: cut-a-release
description: Cut an EduIDE platform release across all four repositories. Use when asked to release, cut a version, publish charts, or ship a version of EduIDE.
---

# Cutting a release

A release is one version across EduIDE-Cloud, EduIDE, EduIDE-Landing-Page and
EduIDE-Helm.

**Do not bump the chart version from a workflow or by pushing to `main`.** The
release train deliberately does not do this, and neither should you. It checks
the charts are already at the requested version and fails otherwise. The bump is
a reviewed pull request; automation that pushes to `main` triggers the workflows
watching `main`.

## 1. Dry run first, always

```bash
gh workflow run release-train.yml --repo EduIDE/EduIDE-Helm \
  -f version=2.3.0 -f dry_run=true
```

Read the summary. It reports which images the version would need, and builds
nothing.

## 2. Bump both charts in a pull request

Both charts, both fields — four values, all identical:

```yaml
# charts/eduide/Chart.yaml  AND  charts/eduide-cluster/Chart.yaml
version: 2.3.0
appVersion: "2.3.0"
```

Then regenerate the READMEs, or the `docs-drift` job fails:

```bash
docker run --rm -v "$PWD/charts:/helm-docs" -u "$(id -u)" jnorwood/helm-docs:v1.14.2
```

Open the PR and let CI run. Do not merge it yourself unless asked to.

## 3. Run it for real

```bash
gh workflow run release-train.yml --repo EduIDE/EduIDE-Helm \
  -f version=2.3.0 -f dry_run=false
```

Order: validate, build all 14 images, verify they exist and are multi-arch,
**then** tag, then publish. Building before tagging means a flaky image build
costs a re-run rather than stranding immutable tags on repositories whose
images were never published.

## 4. Roll it out separately

The train deploys nothing. In EduIDE-deployment, bump
`spec.platform.chartVersion` in the relevant `environments/*/env.yaml`, in a
pull request. Production is never deployed automatically.

## Version forms

- git tags `vX.Y.Z`
- chart `version`, chart `appVersion` and image tags all `X.Y.Z`
- release candidates `2.3.0-rc.1` throughout

## Common failures

| Message | Meaning |
|---|---|
| `version is 'X', expected 'Y'` | step 2 skipped, or only one chart/field bumped |
| `missing ghcr.io/...` | a component build failed; check that repository's Actions |
| `is not multi-arch` | one architecture failed; re-run the whole build, not just the merge job |
| `tag v2.3.0 already exists` | pick the next version, tags are immutable |
