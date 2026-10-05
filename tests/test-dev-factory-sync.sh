#!/usr/bin/env bash
# tests/test-dev-factory-sync.sh — Verifies that sync-governance.sh installs the dev factory
# (ADR-0005) and never overwrites a project's tuned files on re-sync.
# NB: set -e is not used in the tests so that return codes can be captured

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPTS="${BOOTSTRAP_DIR}/scripts"
GOVERNANCE_DIR="${GOVERNANCE_DIR:-${BOOTSTRAP_DIR}/../vibecoding-copilot-governance}"

PASS=0
FAIL=0

check() {
  local desc="$1"
  if eval "$2"; then
    echo "[PASS] $desc"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Test: dev factory synchronization ==="

if [[ ! -d "${GOVERNANCE_DIR}/dev-factory/project-template" ]]; then
  echo "[SKIP] ${GOVERNANCE_DIR}/dev-factory/project-template not found"
  exit 0
fi

TMPDIR="/tmp/vibecoding-test-dev-factory-$$"
bash "${SCRIPTS}/sync-governance.sh" --type base --dest "$TMPDIR" >/dev/null 2>&1
rc=$?
check "sync exits 0" "[[ $rc -eq 0 ]]"

for f in CLAUDE.md .claude/settings.json .ai/orchestration.yaml .ai/.gitignore \
         .ai/tasks/TASK-template.md .ai/roles/dev.md .ai/roles/review.md .ai/roles/test.md \
         scripts/orchestrate.py .claude/hooks/tool_guardian.py .claude/hooks/secrets_scanner.py; do
  check "installed: $f" "[[ -f '${TMPDIR}/${f}' ]]"
done
check "docs/plans/README.md installed (ADR-0006)" "[[ -f '${TMPDIR}/docs/plans/README.md' ]]"
for f in docs/operations/README.md docs/operations/CURRENT.md docs/adr/README.md docs/runbooks/README.md; do
  check "docs skeleton from kit: $f" "[[ -f '${TMPDIR}/${f}' ]]"
done
check "no .hermes.md written (ADR-0007)" "[[ ! -f '${TMPDIR}/.hermes.md' ]]"
check "orchestrate.py is executable" "[[ -x '${TMPDIR}/scripts/orchestrate.py' ]]"
check "hooks are executable" "[[ -x '${TMPDIR}/.claude/hooks/tool_guardian.py' && -x '${TMPDIR}/.claude/hooks/secrets_scanner.py' ]]"
check "settings.json wires the hooks" "grep -q 'tool_guardian.py' '${TMPDIR}/.claude/settings.json' && grep -q 'secrets_scanner.py' '${TMPDIR}/.claude/settings.json'"
check "CLAUDE.md project name substituted" "grep -q 'CLAUDE.md — vibecoding-test-dev-factory' '${TMPDIR}/CLAUDE.md'"
check "no __pycache__ copied" "[[ -z \"\$(find '${TMPDIR}' -name '*.pyc')\" ]]"

echo "max_review_cycles: 9  # tuned" >> "${TMPDIR}/.ai/orchestration.yaml"
bash "${SCRIPTS}/sync-governance.sh" --type base --dest "$TMPDIR" >/dev/null 2>&1
check "re-sync keeps tuned orchestration.yaml" "grep -q '# tuned' '${TMPDIR}/.ai/orchestration.yaml'"

bash "${SCRIPTS}/sync-governance.sh" --type base --dest "$TMPDIR" --lang fr >/dev/null 2>&1
rc=$?
check "--lang fr is rejected" "[[ $rc -ne 0 ]]"

rm -rf "$TMPDIR"

echo ""
echo "Result: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
