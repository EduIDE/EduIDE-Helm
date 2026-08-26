---
name: chart-change
description: Change an EduIDE Helm chart safely. Use when editing templates or values in EduIDE-Helm, or when asked why a chart change is or is not behaviour-preserving.
---

# Changing a chart

The question that matters is not "does it lint" but **"what does this do to the
five live environments"**. There is a command for that.

## Loop

```bash
# 1. baseline BEFORE touching anything
./scripts/render-envs.sh /tmp/before

# 2. make one change, one concern at a time

# 3. what did it actually do?
./scripts/render-envs.sh /tmp/after
diff -r /tmp/before /tmp/after
```

For a refactor the diff must be **empty**. If it is not, either the refactor is
not behaviour-preserving or the change was larger than intended — both worth
knowing before review.

For an intentional change, the diff should contain exactly that change and
nothing else. Ten lines across five environments is one line per environment.

## Then

```bash
helm lint charts/eduide charts/eduide-cluster
# bump the chart version - CI enforces it, and release.yml silently
# publishes nothing if you forget
docker run --rm -v "$PWD/charts:/helm-docs" -u "$(id -u)" jnorwood/helm-docs:v1.14.2
```

## Traps

- **Never release-prefix resource names.** The operator mounts
  `oauth2-proxy-config`, `oauth2-templates` and `oauth2-emails` by literal name
  into every session pod.
- **Adding a `lookup`?** Add it to the mask list in `scripts/render-envs.sh` too,
  or every future PR shows a false diff.
- **A Go-template comment is `{{/* */}}`.** A YAML `#` comment inside a template
  ends up in the rendered manifest and shows as a diff.
- **`helm lint` accepts invalid YAML.** Duplicate keys pass lint and render, and
  are only caught by `kubeconform`. Run it.
