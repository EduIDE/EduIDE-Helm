# Releasing

One platform version spans four repositories: EduIDE-Cloud, EduIDE,
EduIDE-Landing-Page and the charts here. The `Release train` workflow cuts all
of it.

```
Actions -> Release train -> Run workflow
  version:  2.3.0        (no leading v)
  dry_run:  true         leave this on the first time
```

## What it does, and why in that order

1. **Validate** the version is semver and the tag is free.
2. **Build** every component at that tag, by dispatching each repository's own
   build workflow with `image_tag`. **Nothing is tagged yet.**
3. **Verify** all 14 images exist in GHCR and are multi-arch.
4. **Tag** the three component repositories.
5. **Publish** both charts at that version.

Tagging first is the obvious design and the wrong one. Building 15 multi-GB IDE
images is the flakiest step in the pipeline; if one fails after the tags exist,
immutable `vX.Y.Z` tags are stranded on repositories whose images were never
published. Building first makes a flake cost a re-run.

Step 3 exists because a chart pinning a tag that was never pushed is a failure
that only shows up at deploy time, in whichever environment picks it up first.

## Versions

- Git tags are `vX.Y.Z`.
- Image tags and chart versions are `X.Y.Z`, so a chart's `appVersion` and the
  image tag it refers to are the same string.
- Release candidates are `2.3.0-rc.1` throughout, published to the same place
  and installed with an explicit `--version`.

The four repositories move together. A one-line landing page fix therefore
rebuilds everything, which is the price of a version number that means
something. If a component's cadence ever diverges enough for that to hurt, the
alternative is a bill of materials pinning each component in the chart values,
with `appVersion` demoted to a label.

## Rolling a release out

The train does **not** deploy. It opens nothing and changes no environment.

```yaml
# environments/prod-tum/env.yaml
spec:
  platform:
    chartVersion: 2.3.0    # the only line that changes
```

Merge that, then run `Deploy environment`. Production is never deployed
automatically.

## swift

`swift` is deliberately absent from the image list. It exists under `images/`
and in `docker-compose.images.yml`, and the README advertises it, but it is in
no build matrix and has never been published. Listing it would fail every
release; leaving it implicit would let the gap rot unnoticed, so it is named
in the workflow as an explicit exclusion instead.
