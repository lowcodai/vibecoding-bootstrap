#!/usr/bin/env bash
# tests/test-autonomy.sh — Verifies the agent autonomy levels end to end (ADR-0008):
# new-project.sh --autonomy, sync-governance.sh --autonomy, kit-owned refresh, preservation of
# tuned files, migration of a pre-ADR-0008 repo, fallback, and rejection of invalid levels.
# NB: set -e is not used in the tests so that return codes can be captured

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPTS="${BOOTSTRAP_DIR}/scripts"
GOVERNANCE_DIR="${GOVERNANCE_DIR:-${BOOTSTRAP_DIR}/../vibecoding-copilot-governance}"
KIT="${GOVERNANCE_DIR}/dev-factory/project-template"

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

echo "=== Test: agent autonomy levels (ADR-0008) ==="

if [[ ! -f "${KIT}/.claude/hooks/autonomy.py" ]]; then
  echo "[SKIP] ${KIT}/.claude/hooks/autonomy.py not found"
  exit 0
fi

ROOT="/tmp/vibecoding-test-autonomy-$$"
mkdir -p "$ROOT"
trap 'rm -rf "$ROOT"' EXIT

new_project() {   # <level> <dir> [extra args...]
  local level="$1" dir="$2"
  shift 2
  bash "${SCRIPTS}/new-project.sh" -t base -n "$(basename "$dir")" --autonomy "$level" --no-github \
    --skip-awesome-copilot --no-labels --no-adr --yes -d "$dir" "$@" >"${dir}.log" 2>&1
}
level_of()   { grep -E '^level:' "$1/.ai/autonomy.yaml" | awk '{print $2}'; }
check_ok()   { python3 "$1/.claude/hooks/autonomy.py" check --root "$1" >/dev/null 2>&1; }
denies()     { grep -qF "\"$2\"" "$1/.claude/settings.json"; }

# ─── CLI ─────────────────────────────────────────────────────────────────────
check "new-project --help documents --autonomy" \
  "bash '${SCRIPTS}/new-project.sh' --help | grep -q -- '--autonomy <level>'"
bash "${SCRIPTS}/new-project.sh" -t base -n bad --autonomy root --no-github --yes --dry-run -d "$ROOT/bad" >/dev/null 2>&1
rc=$?
check "new-project rejects an unknown level" "[[ $rc -ne 0 && ! -e '$ROOT/bad' ]]"
bash "${SCRIPTS}/sync-governance.sh" --type base --dest "$ROOT/bad2" --autonomy admin >/dev/null 2>&1
rc=$?
check "sync-governance rejects an unknown level" "[[ $rc -ne 0 && ! -e '$ROOT/bad2' ]]"

# ─── Dry run ─────────────────────────────────────────────────────────────────
new_project branch "$ROOT/dry" --dry-run
check "dry-run creates nothing" "[[ ! -e '$ROOT/dry' ]]"
check "dry-run shows the level in the summary" "grep -q 'Agent autonomy    : branch' '$ROOT/dry.log'"
check "dry-run announces the level file" "grep -q 'would write .ai/autonomy.yaml (level: branch)' '$ROOT/dry.log'"

# ─── Creation at each level ──────────────────────────────────────────────────
for level in supervised branch trusted; do
  d="$ROOT/p-${level}"
  new_project "$level" "$d"
  rc=$?
  check "[$level] new-project exits 0" "[[ $rc -eq 0 ]]"
  check "[$level] .ai/autonomy.yaml declares $level" "[[ \"\$(level_of '$d')\" == '$level' ]]"
  check "[$level] autonomy.py check passes" "check_ok '$d'"
  check "[$level] CLAUDE.md carries the $level line" "grep -q 'Autonomy \`$level\`' '$d/CLAUDE.md'"
  check "[$level] AGENTS.md carries the $level section" "grep -q '## Autonomy — level \`$level\`' '$d/AGENTS.md'"
  check "[$level] AGENTS.md no longer says 'git push' is always forbidden" "! grep -q '^- \`git push\`, \`merge\`' '$d/AGENTS.md'"
  check "[$level] invariants denied: rebase, pull, autonomy.yaml edits" \
    "denies '$d' 'Bash(git rebase:*)' && denies '$d' 'Bash(git pull:*)' && denies '$d' 'Edit(./.ai/autonomy.yaml)'"
done
check "[supervised] curl, gh and push are denied" \
  "denies '$ROOT/p-supervised' 'Bash(curl:*)' && denies '$ROOT/p-supervised' 'Bash(gh:*)' && denies '$ROOT/p-supervised' 'Bash(git push:*)'"
check "[branch] curl and plain push are not denied, force push and gh pr merge are" \
  "! denies '$ROOT/p-branch' 'Bash(curl:*)' && ! denies '$ROOT/p-branch' 'Bash(git push:*)' && denies '$ROOT/p-branch' 'Bash(git push --force:*)' && denies '$ROOT/p-branch' 'Bash(gh pr merge:*)'"
check "[trusted] gh pr merge is not denied, --admin is" \
  "! denies '$ROOT/p-trusted' 'Bash(gh pr merge:*)' && denies '$ROOT/p-trusted' 'Bash(gh pr merge --admin:*)'"

# ─── Changing the level of an existing repo ──────────────────────────────────
d="$ROOT/p-branch"
git -C "$d" init -q -b main
echo "max_review_cycles: 9  # tuned" >> "$d/.ai/orchestration.yaml"
echo "- Project-specific rule kept by sync." >> "$d/CLAUDE.md"
echo "custom role line" >> "$d/.ai/roles/dev.md"
echo "docs/** GENERIC_SECRET" >> "$d/.claude/hooks/secrets-allowlist.txt"
git -C "$d" add -A
git -C "$d" -c user.email=t@example.com -c user.name=t commit -qm init
bash "${SCRIPTS}/sync-governance.sh" --type base --dest "$d" --autonomy supervised >"$ROOT/resync.log" 2>&1
rc=$?
check "sync --autonomy supervised exits 0" "[[ $rc -eq 0 ]]"
check "level changed to supervised" "[[ \"\$(level_of '$d')\" == 'supervised' ]]"
check "rendered files follow (check passes, curl denied again)" "check_ok '$d' && denies '$d' 'Bash(curl:*)'"
check "tuned orchestration.yaml kept" "grep -q '# tuned' '$d/.ai/orchestration.yaml'"
check "project line of CLAUDE.md kept" "grep -q 'Project-specific rule kept by sync' '$d/CLAUDE.md'"
check "tuned role prompt kept" "grep -q 'custom role line' '$d/.ai/roles/dev.md'"
check "secrets allowlist kept" "grep -q 'docs/\*\* GENERIC_SECRET' '$d/.claude/hooks/secrets-allowlist.txt'"
changed="$(git -C "$d" status --porcelain | awk '{print $2}' | sort | tr '\n' ' ')"
check "only level-driven files changed (got: ${changed})" \
  "[[ '${changed}' == '.ai/autonomy.yaml .claude/settings.json AGENTS.md CLAUDE.md ' ]]"
git -C "$d" add -A
git -C "$d" -c user.email=t@example.com -c user.name=t commit -qm supervised
bash "${SCRIPTS}/sync-governance.sh" --type base --dest "$d" >/dev/null 2>&1
check "re-sync without --autonomy keeps the level and changes nothing" \
  "[[ \"\$(level_of '$d')\" == 'supervised' && -z \"\$(git -C '$d' status --porcelain)\" ]]"

# ─── Kit-owned files are refreshed ───────────────────────────────────────────
echo "# hand edit" >> "$d/.claude/hooks/tool_guardian.py"
sed -i 's/"Bash(curl:\*)",//' "$d/.claude/settings.json"
bash "${SCRIPTS}/sync-governance.sh" --type base --dest "$d" >/dev/null 2>&1
check "hand-edited tool_guardian.py restored from the kit" "cmp -s '${KIT}/.claude/hooks/tool_guardian.py' '$d/.claude/hooks/tool_guardian.py'"
check "hand-edited settings.json re-rendered" "denies '$d' 'Bash(curl:*)' && check_ok '$d'"
echo "# hand edit" >> "$d/.claude/hooks/tool_guardian.py"
bash "${SCRIPTS}/sync-governance.sh" --type base --dest "$d" --extend-only >/dev/null 2>&1
check "--extend-only never overwrites a kit-owned file" "grep -q '# hand edit' '$d/.claude/hooks/tool_guardian.py'"

# ─── Migration of a repo synced before ADR-0008 ──────────────────────────────
m="$ROOT/legacy"
bash "${SCRIPTS}/sync-governance.sh" --type base --dest "$m" >/dev/null 2>&1
rm -f "$m/.ai/autonomy.yaml" "$m/.claude/hooks/autonomy.py"
python3 - "$m/CLAUDE.md" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r"\n<!-- autonomy:begin -->.*?<!-- autonomy:end -->", "", s, flags=re.S)
s = s.replace("= one worktree.", "= one worktree. Never push, merge or rebase.")
open(p, "w").write(s)
PYEOF
cat > "$m/AGENTS.md" <<'EOF'
# AGENTS.md — legacy

## Boundaries

**Never**
- `git push`, `merge`, `rebase`, `reset --hard`, force operations, or commits on `main`.

## Definition of done

- done
EOF
bash "${SCRIPTS}/sync-governance.sh" --type base --dest "$m" --autonomy branch >"$ROOT/legacy.log" 2>&1
rc=$?
check "legacy repo: sync exits 0" "[[ $rc -eq 0 ]]"
check "legacy repo: level file and policy module added" "[[ \"\$(level_of '$m')\" == 'branch' && -f '$m/.claude/hooks/autonomy.py' ]]"
check "legacy repo: CLAUDE.md migrated (no 'Never push' sentence, one block)" \
  "! grep -q 'Never push, merge or rebase' '$m/CLAUDE.md' && [[ \$(grep -c 'autonomy:begin' '$m/CLAUDE.md') -eq 1 ]]"
check "legacy repo: AGENTS.md gets the section before Definition of done" \
  "awk '/## Autonomy/{a=NR} /## Definition of done/{b=NR} END{exit !(a && b && a<b)}' '$m/AGENTS.md'"
check "legacy repo: check passes" "check_ok '$m'"

# ─── Fallback: a corrupt level file is rendered as supervised ────────────────
echo "level: [oops" > "$m/.ai/autonomy.yaml"
bash "${SCRIPTS}/sync-governance.sh" --type base --dest "$m" >"$ROOT/corrupt.log" 2>&1
check "corrupt level file: rendered as supervised" "denies '$m' 'Bash(curl:*)' && grep -q 'Autonomy \`supervised\`' '$m/CLAUDE.md'"
check "corrupt level file: check reports it" "! check_ok '$m'"

echo ""
echo "Result: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
