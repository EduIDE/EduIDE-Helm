#!/usr/bin/env bash
# Check AGENTS.md's factual claims about paths, in both directions.
#
# Every AGENTS.md in this org had rotted into fiction. One named a CI job that
# had been deleted and a package.json path that does not exist; another
# described a landing page removed months earlier. Nothing checked them, so
# nothing noticed.
#
# A path in backticks must exist - unless the sentence containing it says it
# does not, in which case it must NOT exist. That second direction matters:
# these docs deliberately name dead paths so nobody mistakes them for live code,
# and if someone later creates one the doc has quietly become wrong again.
#
# Checking is per REFERENCE, not per path: a doc that says a file is gone in one
# sentence and tells you to edit it in another is wrong, and evaluating the path
# once would let the negated sentence excuse the live one.
#
# Only repo-relative, extension-bearing paths in backticks are checked. Prose is
# not validated; this is a lint, not a proof.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT/AGENTS.md"
[[ -f "$DOC" ]] || { echo "no AGENTS.md here"; exit 0; }

# A sentence asserting absence. Deliberately narrow: "is dead" and "retired"
# describe something that exists and does not work, which is a different claim.
NEGATED='does not exist|do not exist|no longer exists|no longer exist|was removed|were removed|has no root'

interesting() {
  local p="$1"
  [[ "$p" == */* ]] || return 1          # must look like a path
  [[ "$p" == *.* ]] || return 1          # and carry an extension
  case "$p" in
    http*|*ghcr.io*|*github.com*|oci://*|*.tum.de*|*.io/*|*@*) return 1 ;;
  esac
  return 0
}

failed=0; checked=0
# One line at a time, so each reference is judged in its own sentence.
while IFS=: read -r lineno line; do
  while IFS= read -r p; do
    interesting "$p" || continue

    # A parent-directory reference resolves against whatever happens to sit
    # beside the checkout, so it passes locally and fails in CI - or worse, the
    # reverse. Cross-repo paths belong in prose, not in backticks.
    case "$p" in
      ../*|*/../*)
        echo "  line $lineno: leaves the repository: $p"
        echo "             cross-repo paths cannot be checked; name the file without a path"
        failed=1
        continue ;;
    esac

    checked=$((checked + 1))
    if grep -qiE "$NEGATED" <<<"$line"; then
      if [[ -e "$ROOT/$p" ]]; then
        echo "  line $lineno: says this does not exist, but it does: $p"
        failed=1
      fi
    elif [[ ! -e "$ROOT/$p" ]]; then
      echo "  line $lineno: missing: $p"
      failed=1
    fi
  done < <(grep -oE '`[A-Za-z0-9_./-]+`' <<<"$line" | tr -d '`')
done < <(grep -n '`' "$DOC")

if [[ $failed -ne 0 ]]; then
  echo "AGENTS.md disagrees with the repository. Fix the doc or the path."
  exit 1
fi
echo "AGENTS.md: $checked path references all check out"
