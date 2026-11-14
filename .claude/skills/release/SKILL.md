---
name: release
description: Release EduIDE-Helm. Use when asked to release, cut a release, make or publish a new version, ship a version, tag a version, or prepare a release candidate of EduIDE-Helm. Finds the unreleased changes, proposes the version, checks the EduIDE dependencies it pins, writes CHANGELOG.md, opens the release pull request and runs release.yml.
---

# Releasing EduIDE-Helm

A release is two steps with a human in between:

1. a **release pull request** that bumps the version files and moves the
   unreleased CHANGELOG entries under the new version, and
2. after it is merged, a run of **`release.yml`** (`workflow_dispatch`, input
   `version`), which validates, builds, tags, creates the GitHub Release from
   the CHANGELOG section and publishes.

Nothing releases on push to `main`. Tags look like `vX.Y.Z`;
images, charts and vsix files carry `X.Y.Z` without the prefix.

## Reference for this repository

Version files (release.yml refuses a stable version they do not state):

| File | Field |
|---|---|
| `charts/eduide/Chart.yaml` | `version` |
| `charts/eduide-cluster/Chart.yaml` | `version` (always equal to the other chart) |

`appVersion` is not the chart version: it pins the EduIDE IDE images (see dependencies). helm-docs renders the README badges from `version`, so run it after the bump.

What a release publishes:

| Artifact | Where | Check |
|---|---|---|
| Chart `eduide` | `oci://ghcr.io/eduide/charts/eduide:X.Y.Z` | `helm show chart oci://ghcr.io/eduide/charts/eduide --version X.Y.Z` |
| Chart `eduide-cluster` | `oci://ghcr.io/eduide/charts/eduide-cluster:X.Y.Z` | `helm show chart oci://ghcr.io/eduide/charts/eduide-cluster --version X.Y.Z` |
| GitHub Release `vX.Y.Z` | notes from CHANGELOG plus a table of what the version pins | `gh release view vX.Y.Z -R EduIDE/EduIDE-Helm` |

EduIDE dependencies this repository pins:

| Repository | Pinned in | Current pin | How to bump |
|---|---|---|---|
| EduIDE | `charts/eduide/Chart.yaml` and `charts/eduide-cluster/Chart.yaml`, key `appVersion` (both equal; renders every IDE image tag) | `yq -r .appVersion charts/eduide/Chart.yaml` | latest: `gh release list -R EduIDE/EduIDE --exclude-pre-releases --limit 1` (tag `vX.Y.Z`, pin is `X.Y.Z`) |
| EduIDE-Cloud | `charts/eduide/values.yaml`, key `versions.cloud` (operator, service) | `yq -r .versions.cloud charts/eduide/values.yaml` | latest: `gh release list -R EduIDE/EduIDE-Cloud --exclude-pre-releases --limit 1` |
| EduIDE-Landing-Page | `charts/eduide/values.yaml`, key `versions.landingPage` | `yq -r .versions.landingPage charts/eduide/values.yaml` | latest: `gh release list -R EduIDE/EduIDE-Landing-Page --exclude-pre-releases --limit 1` |
| EduIDE-shared-cache | `charts/eduide/Chart.yaml`, `dependencies[name=eduide-shared-cache].version` (OCI) | `yq '.dependencies[] \| select(.name=="eduide-shared-cache").version' charts/eduide/Chart.yaml` | latest: `gh release list -R EduIDE/EduIDE-shared-cache --exclude-pre-releases --limit 1` (tag `eduide-shared-cache-X.Y.Z`, pin is `X.Y.Z`); then refresh `Chart.lock` with `helm dependency update charts/eduide` |
| workspace-garbage-collector | `charts/eduide/Chart.yaml`, `dependencies[name=theia-workspace-garbage-collector].version` (OCI), and `charts/eduide/values.yaml` `theia-workspace-garbage-collector.image.tag` | same pattern, with `yq -r '.["theia-workspace-garbage-collector"].image.tag' charts/eduide/values.yaml` for the image | latest: `gh release list -R EduIDE/workspace-garbage-collector --exclude-pre-releases --limit 1` (tag `theia-workspace-garbage-collector-X.Y.Z`); `Chart.lock` refresh as above. Once the GC chart pins its own image by version, empty `image.tag` here |
| EduIDE-pool-scaler | `charts/eduide/values.yaml`, key `versions.poolScaler`, only when present on main | `yq -r .versions.poolScaler charts/eduide/values.yaml` | latest: `gh release list -R EduIDE/EduIDE-pool-scaler`; never pin an unreleased version |

`charts/eduide-cluster/values.yaml` `conversion.image` points at the upstream `theiacloud/theia-cloud-conversion-webhook`, not at an EduIDE-Cloud release, so it is not a pin to bump here. Upstream images (`wondershaperImage`, demo image) are Renovate's job.

Who pins this repository (tell the user after the release):

| Repository | Pinned in |
|---|---|
| EduIDE-deployment | `environments/*/env.yaml`, key `spec.platform.chartVersion` |

## 1. Find the last release and what is unreleased

```bash
gh release list -R EduIDE/EduIDE-Helm --limit 10
LAST=$(gh release list -R EduIDE/EduIDE-Helm --exclude-pre-releases --limit 1 --json tagName --jq '.[0].tagName')
git fetch origin --tags
git log --first-parent --format='%h %s' "$LAST"..origin/main
```

Read the merged pull requests behind those commits, not only the titles:

```bash
gh pr list -R EduIDE/EduIDE-Helm --state merged --base main --limit 100 \
  --search "merged:>$(git log -1 --format=%cI "$LAST")" \
  --json number,title,labels,body,url
```

Also read the `## [Unreleased]` section of `CHANGELOG.md`. If there are no
commits since `$LAST`, say so and stop, unless a dependency bump (step 3) is
the reason for the release.

## 2. Propose a version and let the user decide

Derive it from the changes since `$LAST` (conventional commits and the PR
content, not only the prefix):

| Change | Bump |
|---|---|
| `!` after the type, `BREAKING CHANGE:`, a removed or renamed option, a changed default that alters behaviour, a dependency pin that requires a breaking upgrade | major (minor while the version is `0.x`) |
| `feat`, a new option, a dependency pin that brings features | minor |
| `fix`, `perf`, security fixes, dependency pins with fixes only | patch |
| only `chore`, `ci`, `docs`, `test`, `build` | usually nothing to release; ask |

A prerelease is `X.Y.Z-rc.N`, only when the user asks for one or wants to test
before a stable release. `N` starts at 1 and continues after the highest
existing `-rc.N` of that `X.Y.Z`.

**Ask the user** with a question (the AskUserQuestion tool when available):
the proposed version as the first option, with a one-line reason
("minor: 2 features, 3 fixes, no breaking change"), the next lower and higher
bump, and the release candidate variant. Never continue on a guessed version.

## 3. Check every EduIDE dependency

For each row of "EduIDE dependencies":

1. Read the current pin from the file.
2. Find the latest release of that repository:
   `gh release list -R EduIDE/<repo> --exclude-pre-releases --limit 1`
   (for a prerelease of this repository, also look at its prereleases).
3. Check whether it has unreleased changes on main:
   `gh api repos/EduIDE/<repo>/compare/<its last tag>...main --jq '.ahead_by, (.commits[].commit.message | split("\n")[0])'`

Then, per dependency:

- **Pin is older than the latest release:** show the user both versions and
  the dependency's release notes in between, and ask whether to bump the pin
  in this release. A bump goes into the release pull request and into the
  `### Dependencies` notes.
- **Dependency has unreleased changes on main:** list them and ask whether to
  release that repository first. If yes, follow that repository's release
  skill completely before you continue here:
  - local clone (the EduIDE workspace keeps repositories side by side):
    `../<repo>/.claude/skills/release/SKILL.md`
  - otherwise read it with
    `gh api repos/EduIDE/<repo>/contents/.claude/skills/release/SKILL.md --jq .content | base64 -d`
    and work in a fresh clone or worktree of that repository, never in a
    checkout that has someone else's uncommitted work.

  When it is released, come back here and bump the pin to the new version.
- **Pin is current and the dependency has nothing unreleased:** report it as
  up to date, no question needed.

Never pin an unreleased build (`pr-N`, a commit SHA, `latest`) in a stable
release. If the repository pins one today, say so and ask how to resolve it.

## 4. Write the release notes into CHANGELOG.md

Move the content of `## [Unreleased]` under a new heading and leave an empty
`## [Unreleased]` above it. release.yml copies exactly this section into the
GitHub Release, so write it for the people who install or use the release,
not for the people who wrote the code:

```markdown
## [Unreleased]

## [eduide X.Y.Z] - YYYY-MM-DD

- [eduide] What changed for an operator, in one or two sentences, with the option name and its default ([#123](https://github.com/EduIDE/EduIDE-Helm/pull/123))
- [eduide-cluster] Version bump only, to keep both charts on the same version

Upgrade notes:

- What an operator has to do beyond installing the new version
```

The heading is `## [eduide X.Y.Z]` and entries carry the `[eduide]` or
`[eduide-cluster]` prefix; release.yml looks for exactly that heading. The
release also gets a table of what the version pins, added by release.yml.

Rules:

- Every entry links its pull request. Find it with `gh pr list --search <sha>`
  when the Unreleased entry has none.
- Leave out empty groups. Merge entries that describe one change. Leave out
  pure CI, test and refactoring changes unless a user can notice them.
- Dependency bumps (appVersion, `versions.*`, chart dependencies) are a
  `[eduide]` entry naming old and new version.
- Add `### Upgrade notes` when an operator has to do something beyond
  installing the new version.
- Use hyphens, never em or en dashes.

## 5. Open the release pull request

On a branch `release/X.Y.Z` from the latest `origin/main`:

1. Bump every row of "Version files" to `X.Y.Z`.
2. Apply the dependency bumps agreed in step 3.
3. Write the CHANGELOG section from step 4.
4. Run the repository's checks (see AGENTS.md / CI) and anything a version
   bump regenerates (helm-docs, so the README badges match: `docker run --rm -v "$PWD/charts:/helm-docs" -u "$(id -u)" jnorwood/helm-docs:v1.14.2`; `scripts/test-app-consistency.sh`).

Show the user the diff and ask before committing and pushing. Then:

```bash
git commit -m "chore(release): X.Y.Z"
git push -u origin release/X.Y.Z
gh pr create -R EduIDE/EduIDE-Helm --title "chore(release): X.Y.Z" --body-file <notes plus the dependency table>
```

Give the user the PR link, watch CI and fix failures. Do not merge it yourself
unless the user asks.

**Release candidate shortcut:** a `-rc.N` needs no release pull request.
release.yml does not check version files for a prerelease and falls back to the
Unreleased section for the notes. Dispatch it from the branch to test
(step 6 with `--ref <branch>`).

## 6. Run release.yml after the merge

```bash
gh workflow run release.yml -R EduIDE/EduIDE-Helm --ref main -f version=X.Y.Z
sleep 5
RUN=$(gh run list -R EduIDE/EduIDE-Helm --workflow release.yml --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" -R EduIDE/EduIDE-Helm --exit-status
```

If a job waits for an environment approval (`prod`), tell the user to approve
it in the run page. If `validate` fails, the message says what to fix; fix it
in a new pull request, never by editing tags. If a later job fails, fix the
cause and use "Re-run failed jobs": the tag stays, nothing is published twice.
Never delete a tag or a release once something was published under it; ship
the next patch version instead.

## 7. Verify what was published

Check every row of "What a release publishes", for example:

```bash
gh release view vX.Y.Z -R EduIDE/EduIDE-Helm --json url,isPrerelease,assets --jq '{url, isPrerelease, assets: [.assets[].name]}'
crane manifest ghcr.io/eduide/<image>:X.Y.Z | jq -r '[.manifests[].platform.architecture] | join(",")'   # amd64 and arm64
helm show chart oci://ghcr.io/eduide/charts/<chart> --version X.Y.Z
curl -fsS https://open-vsx.org/api/<namespace>/<name>/X.Y.Z | jq -r .version
```

Report to the user: the release link, the artifacts with their check result,
and every row of "Who pins this repository" with its current pin, so they can
decide whether to bump it next (that repository's release skill does it).
