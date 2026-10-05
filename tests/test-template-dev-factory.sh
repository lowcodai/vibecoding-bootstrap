#!/usr/bin/env bash
# tests/test-template-dev-factory.sh — Verifies that each vibecoding-template-* repo ships the
# dev factory kit identical to vibecoding-copilot-governance/dev-factory/project-template/
# (only CLAUDE.md line 1, the project name, may differ). Missing clones are skipped.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATES_ROOT="${TEMPLATES_ROOT:-${BOOTSTRAP_DIR}/..}"
GOVERNANCE_DIR="${GOVERNANCE_DIR:-${BOOTSTRAP_DIR}/../vibecoding-copilot-governance}"
KIT="${GOVERNANCE_DIR}/dev-factory/project-template"

PASS=0
FAIL=0
SKIP=0

echo "=== Test: templates ship the dev factory kit ==="

if [[ ! -d "$KIT" ]]; then
  echo "[SKIP] kit not found: $KIT"
  exit 0
fi

mapfile -t FILES < <(cd "$KIT" && find . -type f -not -path '*/__pycache__/*' -not -name '*.pyc' | sed 's|^\./||' | sort)

for name in base infra ai app m365-agent; do
  repo="${TEMPLATES_ROOT}/vibecoding-template-${name}"
  if [[ ! -d "$repo" ]]; then
    echo "[SKIP] vibecoding-template-${name}: no clone at ${repo}"
    SKIP=$((SKIP + 1))
    continue
  fi
  bad=()
  for f in "${FILES[@]}"; do
    if [[ ! -f "${repo}/${f}" ]]; then
      bad+=("missing ${f}")
    elif [[ "$f" == "CLAUDE.md" ]]; then
      diff -q <(tail -n +2 "${KIT}/${f}") <(tail -n +2 "${repo}/${f}") >/dev/null || bad+=("drift ${f}")
    else
      cmp -s "${KIT}/${f}" "${repo}/${f}" || bad+=("drift ${f}")
    fi
    if [[ "$f" == *.py && -f "${repo}/${f}" && ! -x "${repo}/${f}" ]]; then
      bad+=("not executable ${f}")
    fi
  done
  if [[ ${#bad[@]} -eq 0 ]]; then
    echo "[PASS] vibecoding-template-${name}: ${#FILES[@]} kit files in sync"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] vibecoding-template-${name}: ${bad[*]}"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "Result: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
[[ $FAIL -eq 0 ]]
