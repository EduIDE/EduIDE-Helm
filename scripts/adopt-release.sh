#!/usr/bin/env bash
# Hand existing objects over to a new Helm release without recreating them.
#
#   ./scripts/adopt-release.sh <namespace> <new-release-name> <kind/name>...
#   DRY_RUN=1 ./scripts/adopt-release.sh ...     # print, change nothing
#
# Helm refuses to manage an object it did not create, and renaming a release
# would otherwise mean deleting and recreating every object in it. Annotating
# them first makes the rename an in-place upgrade instead.
#
# Generalises the inline `kubectl annotate role/operator-sidecar-pod-restart`
# hack that had grown into the old deploy workflow.
#
# Idempotent. Run it immediately before the first upgrade under the new name.

set -euo pipefail

NS="${1:?usage: adopt-release.sh <namespace> <release> <kind/name>...}"
REL="${2:?usage: adopt-release.sh <namespace> <release> <kind/name>...}"
shift 2
[[ $# -gt 0 ]] || { echo "no objects given" >&2; exit 2; }

run() {
  if [[ -n "${DRY_RUN:-}" ]]; then echo "  would: $*"; else "$@"; fi
}

for obj in "$@"; do
  if ! kubectl -n "$NS" get "$obj" >/dev/null 2>&1; then
    echo "  skip   $obj (does not exist)"
    continue
  fi
  owner=$(kubectl -n "$NS" get "$obj" -o jsonpath={.metadata.annotations.meta.helm.sh/release-name} 2>/dev/null || true)
  if [[ "$owner" == "$REL" ]]; then
    echo "  ok     $obj (already owned by $REL)"
    continue
  fi
  echo "  adopt  $obj ${owner:+(was $owner)}"
  run kubectl -n "$NS" annotate --overwrite "$obj" \
      "meta.helm.sh/release-name=$REL" "meta.helm.sh/release-namespace=$NS"
  run kubectl -n "$NS" label --overwrite "$obj" "app.kubernetes.io/managed-by=Helm"
done
