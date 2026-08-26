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
  --version 1.0.0-rc0 -n eduide-system --create-namespace

# once per environment
helm install eduide oci://ghcr.io/eduide/charts/eduide \
  --version 1.0.0-rc0 -n test1 -f my-values.yaml
```

Both charts always carry the same version. `docs/charts.md` explains why the
split exists and what it is safe to change.

Environment configuration for the TUM installations lives in
[EduIDE-deployment](https://github.com/EduIDE/EduIDE-deployment), not here.

---

# Cutting a release

A release is one version across four repositories: EduIDE-Cloud, EduIDE,
EduIDE-Landing-Page and this one.

**The release train does not bump the chart version.** You do, in a reviewed
pull request. The workflow checks the charts are already at the version you
asked for and refuses to continue otherwise. Automation that pushes to `main`
triggers the workflows watching `main`, and release automation that can trigger
itself is a bad thing to own.

## The three steps

### 1. Dry run

```
Actions -> Release train -> Run workflow
  version:  2.3.0        (no leading v)
  dry_run:  true
```

Nothing is built, tagged or published. It reports which images the version
would need. Read the summary before continuing.

### 2. Bump the charts in a pull request

Both charts, both fields, all four values identical:

```yaml
# charts/eduide/Chart.yaml  AND  charts/eduide-cluster/Chart.yaml
version: 2.3.0
appVersion: "2.3.0"
```

```bash
docker run --rm -v "$PWD/charts:/helm-docs" -u "$(id -u)" jnorwood/helm-docs:v1.14.2
```

Open the PR, let CI run, get it reviewed, merge. CI checks the version moved,
the READMEs match, and shows what the change does to every live environment.

### 3. Run the release train for real

```
Actions -> Release train -> Run workflow
  version:  2.3.0
  dry_run:  false
```

It then, in this order:

1. **validates** the version is semver and `v2.3.0` is free
2. **builds** all 14 images at that tag, by dispatching each repository's own
   build workflow — **nothing is tagged yet**
3. **verifies** every image exists in GHCR and is multi-arch
4. **tags** the three component repositories and creates their releases
5. **checks** the charts are at `2.3.0`, tags this repository, publishes both

Building before tagging is deliberate. Building 15 multi-GB IDE images is the
flakiest step in the pipeline; a failure after tagging strands immutable
`v2.3.0` tags on repositories whose images were never published. This way a
flake costs a re-run.

## Rolling it out

The train deploys nothing. In EduIDE-deployment:

```yaml
# environments/prod-tum/env.yaml
spec:
  platform:
    chartVersion: 2.3.0    # the only line that changes
```

Merge that, then run `Deploy environment`. Production is never deployed
automatically.

## Release candidates

`2.3.0-rc.1` everywhere — same pipeline, same registry, marked as a prerelease
on GitHub. Consume with an explicit `--version`; never `--devel`.

## Versioning rules

| Thing | Form | Example |
|---|---|---|
| git tag | `vX.Y.Z` | `v2.3.0` |
| chart `version` and `appVersion` | `X.Y.Z` | `2.3.0` |
| image tag | `X.Y.Z` | `2.3.0` |

`appVersion` and the image tag are the same string, so a chart says exactly
which images it runs.

The four repositories move together. A one-line landing page fix rebuilds
everything — that is the price of a version number that means something. If a
component's cadence ever diverges enough to hurt, the alternative is a bill of
materials pinning each component in the chart values, with `appVersion` demoted
to a label.

## Checklist

```
[ ] dry run is clean
[ ] both Chart.yaml files at X.Y.Z, version AND appVersion
[ ] helm-docs run, READMEs committed
[ ] bump PR reviewed and merged
[ ] release train run with dry_run: false
[ ] chartVersion bumped in EduIDE-deployment for the environments to move
```

## If something goes wrong

| Symptom | Cause | Fix |
|---|---|---|
| `version is 'X', expected 'Y'` | step 2 skipped or half-done | bump both charts, both fields |
| `missing ghcr.io/...` | a component build failed | check that repository's Actions, re-run |
| `is not multi-arch` | one architecture failed | re-run the whole build, not just the merge job |
| `tag v2.3.0 already exists` | version already used | pick the next one, tags are immutable |

---

## Cluster prerequisites

- **cert-manager** — certificate management, including Let's Encrypt.
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
