#!/usr/bin/env bash
# tests/test-template-governance-copies.sh — ADR-0007 DEC-007: every governance file copied into a
# vibecoding-template-* repo must be identical to its source in vibecoding-copilot-governance, and
# no template ships an agent-specific .hermes.md. Missing clones are skipped.
#
# Mapping (template path → governance path):
#   .github/agents/*            → agents/*
#   .github/instructions/*      → instructions/*
#   .github/hooks/*             → hooks/*
#   .github/PULL_REQUEST_TEMPLATE.md → templates/PULL_REQUEST_TEMPLATE.md
#   .github/ISSUE_TEMPLATE/*    → templates/ISSUE_TEMPLATE/*
#   docs/methodology/*          → docs/methodology/*

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATES_ROOT="${TEMPLATES_ROOT:-${BOOTSTRAP_DIR}/..}"
GOVERNANCE_DIR="${GOVERNANCE_DIR:-${BOOTSTRAP_DIR}/../vibecoding-copilot-governance}"

PASS=0
FAIL=0
SKIP=0

echo "=== Test: governance copies in templates are in sync (ADR-0007) ==="

if [[ ! -d "$GOVERNANCE_DIR/agents" ]]; then
  echo "[SKIP] governance not found: $GOVERNANCE_DIR"
  exit 0
fi

source_for() {
  case "$1" in
    .github/agents/*)                 echo "${GOVERNANCE_DIR}/agents/${1#.github/agents/}" ;;
    .github/instructions/*)           echo "${GOVERNANCE_DIR}/instructions/${1#.github/instructions/}" ;;
    .github/hooks/*)                  echo "${GOVERNANCE_DIR}/hooks/${1#.github/hooks/}" ;;
    .github/PULL_REQUEST_TEMPLATE.md) echo "${GOVERNANCE_DIR}/templates/PULL_REQUEST_TEMPLATE.md" ;;
    .github/ISSUE_TEMPLATE/*)         echo "${GOVERNANCE_DIR}/templates/ISSUE_TEMPLATE/${1#.github/ISSUE_TEMPLATE/}" ;;
    docs/methodology/*)               echo "${GOVERNANCE_DIR}/$1" ;;
    *)                                echo "" ;;
  esac
}

for name in base infra ai app m365-agent; do
  repo="${TEMPLATES_ROOT}/vibecoding-template-${name}"
  if [[ ! -d "$repo/.git" ]]; then
    echo "[SKIP] vibecoding-template-${name}: no clone at ${repo}"
    SKIP=$((SKIP + 1))
    continue
  fi
  bad=()
  checked=0
  [[ -f "${repo}/.hermes.md" ]] && bad+=("ships .hermes.md")
  while IFS= read -r f; do
    [[ "$(basename "$f")" == ".gitkeep" ]] && continue
    src="$(source_for "$f")"
    [[ -z "$src" ]] && continue
    checked=$((checked + 1))
    if [[ ! -f "$src" ]]; then
      bad+=("no governance source for ${f}")
    elif ! cmp -s "$src" "${repo}/${f}"; then
      bad+=("drift ${f}")
    fi
  done < <(git -C "$repo" ls-files)
  if [[ ${#bad[@]} -eq 0 ]]; then
    echo "[PASS] vibecoding-template-${name}: ${checked} copies in sync"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] vibecoding-template-${name}: ${bad[*]}"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "Result: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
[[ $FAIL -eq 0 ]]
