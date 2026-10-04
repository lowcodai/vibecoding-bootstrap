#!/usr/bin/env bash
# tests/test-template-agents-md.sh — Verifies that the AGENTS.md committed in each
# vibecoding-template-* repo matches what apply-template.sh renders for that type.
# The generator is the single source; a mismatch means a template copy drifted.
# Template clones are looked up next to this repo; missing clones are skipped.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPTS="${BOOTSTRAP_DIR}/scripts"
TEMPLATES_ROOT="${TEMPLATES_ROOT:-${BOOTSTRAP_DIR}/..}"

PASS=0
FAIL=0
SKIP=0

echo "=== Test: template AGENTS.md in sync with the generator ==="

for pair in base:vibecoding-template-base infra:vibecoding-template-infra \
            ai:vibecoding-template-ai app:vibecoding-template-app m365:vibecoding-template-m365-agent; do
  type="${pair%%:*}"
  repo="${TEMPLATES_ROOT}/${pair#*:}"
  if [[ ! -f "${repo}/AGENTS.md" ]]; then
    echo "[SKIP] ${pair#*:}: no clone or no AGENTS.md at ${repo}"
    SKIP=$((SKIP + 1))
    continue
  fi
  tmp="/tmp/vibecoding-test-agents-${type}-$$"
  bash "${SCRIPTS}/apply-template.sh" --type "$type" --name tpl --dest "$tmp" >/dev/null 2>&1
  # Templates are used via "Use this template": nothing substitutes the name, so line 1 differs.
  if diff -q <(tail -n +2 "${tmp}/AGENTS.md") <(tail -n +2 "${repo}/AGENTS.md") >/dev/null; then
    echo "[PASS] ${pair#*:} matches the ${type} rendering"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] ${pair#*:} drifted from the ${type} rendering:"
    diff <(tail -n +2 "${tmp}/AGENTS.md") <(tail -n +2 "${repo}/AGENTS.md") | head -20
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$tmp"
done

echo ""
echo "Result: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
[[ $FAIL -eq 0 ]]
