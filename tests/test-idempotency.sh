#!/usr/bin/env bash
# tests/test-idempotency.sh — Verifies that rerunning the scripts does not modify an existing project

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPTS="${BOOTSTRAP_DIR}/scripts"

PASS=0
FAIL=0
TMPDIR_BASE="/tmp/vibecoding-test-idempotency-$$"

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

cleanup() { rm -rf "$TMPDIR_BASE"; }
trap cleanup EXIT

echo "=== Test: Idempotency ==="
echo ""

# Initial creation
echo "[INFO] Initial creation..."
if bash "${SCRIPTS}/apply-template.sh" \
  --type base --name test-idempotency --dest "$TMPDIR_BASE" 2>/dev/null; then
  pass "Project created successfully"
else
  fail "Project creation failed"
  exit 1
fi

[[ -f "${TMPDIR_BASE}/README.md" ]] && pass "README.md present" || fail "README.md missing"
[[ -f "${TMPDIR_BASE}/.github/copilot-instructions.md" ]] && \
  pass ".github/copilot-instructions.md present" || fail ".github/copilot-instructions.md missing"

# Modify a file to verify it is not overwritten
echo "MODIFIED" >> "${TMPDIR_BASE}/README.md"
checksum_before=$(md5 -q "${TMPDIR_BASE}/README.md" 2>/dev/null || md5sum "${TMPDIR_BASE}/README.md" | awk '{print $1}')

# Rerun in extend-only
echo "[INFO] Rerunning in extend-only..."
bash "${SCRIPTS}/apply-template.sh" \
  --type base --name test-idempotency --dest "$TMPDIR_BASE" --extend-only 2>/dev/null

checksum_after=$(md5 -q "${TMPDIR_BASE}/README.md" 2>/dev/null || md5sum "${TMPDIR_BASE}/README.md" | awk '{print $1}')
[[ "$checksum_before" == "$checksum_after" ]] && \
  pass "README.md unchanged after extend-only" || fail "README.md modified after extend-only"

# Check required directories
for dir in docs/adr docs/architecture docs/plans docs/runbooks .github/workflows .github/ISSUE_TEMPLATE; do
  [[ -d "${TMPDIR_BASE}/${dir}" ]] && pass "Directory present: $dir" || fail "Directory missing: $dir"
done

# AGENTS.md is the project rulebook (not a Copilot agent list)
for heading in "## Commands" "## Boundaries" "## Definition of done" "## Type-specific rules (base)"; do
  grep -qF "$heading" "${TMPDIR_BASE}/AGENTS.md" && \
    pass "AGENTS.md has: $heading" || fail "AGENTS.md missing: $heading"
done
grep -q "{{" "${TMPDIR_BASE}/AGENTS.md" && \
  fail "AGENTS.md has unresolved placeholders" || pass "AGENTS.md placeholders resolved"
for type in infra ai app m365; do
  tmp_type="${TMPDIR_BASE}-${type}"
  bash "${SCRIPTS}/apply-template.sh" --type "$type" --name "test-${type}" --dest "$tmp_type" >/dev/null 2>&1
  grep -qF "## Type-specific rules (${type})" "${tmp_type}/AGENTS.md" && \
    pass "AGENTS.md type rules: $type" || fail "AGENTS.md type rules missing: $type"
  rm -rf "$tmp_type"
done

# Test: missing file recreated in extend-only
rm -f "${TMPDIR_BASE}/BACKLOG.md"
bash "${SCRIPTS}/apply-template.sh" \
  --type base --name test-idempotency --dest "$TMPDIR_BASE" --extend-only 2>/dev/null
[[ -f "${TMPDIR_BASE}/BACKLOG.md" ]] && \
  pass "BACKLOG.md recreated in extend-only" || fail "BACKLOG.md not recreated in extend-only"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
