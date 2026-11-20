---
name: chart-change
description: Change an EduIDE Helm chart safely. Use when editing templates or values in EduIDE-Helm, or when asked why a chart change is or is not behaviour-preserving.
---

# Changing a chart

The question that matters is not "does it lint" but "what does this do to a
deployment". `scripts/test-eduide.sh` answers the rules; the render diff answers
the rest.

## Loop

```bash
./scripts/resolve-deps.sh
# make one change, one concern at a time
helm lint charts/eduide charts/eduide-cluster
./scripts/test-eduide.sh          # CP_CHARTS=<EduIDE-control-plane>/charts for unreleased subcharts
# no version bump: add the change under "## [Unreleased]" in CHANGELOG.md
docker run --rm -v "$PWD/charts:/helm-docs" -u "$(id -u)" jnorwood/helm-docs:v1.14.2
```

A new rule that must always hold gets a check in `scripts/test-eduide.sh`.

## Traps

- **Never remove the Theia Cloud guard** in `charts/eduide-cluster`. It protects the sessions of a 2.x cluster.
- **Adding a `lookup`?** It is empty under `helm template`: keep the logic in a `define` and test it through a wrapper chart, as the guard test does.
- **A Go-template comment is `{{/* */}}`.** A YAML `#` comment inside a template ends up in the rendered manifest.
- **`helm lint` accepts invalid YAML.** Duplicate keys pass lint and render and are only caught by `kubeconform`.
