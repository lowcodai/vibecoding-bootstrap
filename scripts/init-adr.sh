#!/usr/bin/env bash
# init-adr.sh — Generates the first ADR (ADR-0001) for a project
# Usage: ./scripts/init-adr.sh --dest <dest-dir> --name <repo-name> --type <template-type>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/log.sh"
source "${SCRIPT_DIR}/lib/fs.sh"

: "${DRY_RUN:=false}"
: "${VERBOSE:=false}"

DEST_DIR=""
REPO_NAME=""
TEMPLATE_TYPE="base"
DATE_TODAY="$(date +%Y-%m-%d)"

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--dest)      DEST_DIR="$2"; shift 2 ;;
      -n|--name)      REPO_NAME="$2"; shift 2 ;;
      -t|--type)      TEMPLATE_TYPE="$2"; shift 2 ;;
      --dry-run)      DRY_RUN=true; shift ;;
      --verbose)      VERBOSE=true; shift ;;
      *) log_error "Unknown argument: $1"; exit 1 ;;
    esac
  done
  if [[ -z "$DEST_DIR" ]]; then
    log_error "--dest is required"
    exit 1
  fi
  if [[ -z "$REPO_NAME" ]]; then
    log_error "--name is required"
    exit 1
  fi
  return 0
}

generate_adr_0001() {
  local adr_dir="${DEST_DIR}/docs/adr"
  local adr_file="${adr_dir}/ADR-0001-initial-decisions.md"

  if [[ -f "$adr_file" ]]; then
    log_skip "ADR-0001 already exists: $adr_file"
    return 0
  fi

  run_cmd mkdir -p "$adr_dir"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_dry "Generate: $adr_file"
    return 0
  fi

  # Type-specific context
  local type_context
  case "$TEMPLATE_TYPE" in
    base)   type_context="Generic project standardized from vibecoding-template-base." ;;
    infra)  type_context="Infrastructure project using Ansible, Docker and GitHub Actions for IaC and SRE automation." ;;
    ai)     type_context="AI/agents project integrating AI governance, safety, and agentic usage practices for GitHub Copilot." ;;
    app)    type_context="Web/API application with CI/CD, accessibility (a11y) and good development practices." ;;
    m365)   type_context="Microsoft 365 Copilot declarative agent (MCP-backed plugin), standardized from vibecoding-template-m365-agent." ;;
  esac

  cat > "$adr_file" << EOF
# ADR-0001 — Initial decisions for project ${REPO_NAME}

**Date:** ${DATE_TODAY}
**Status:** Accepted
**Decision makers:** <!-- TODO: List the decision makers -->
**Template:** vibecoding-template-${TEMPLATE_TYPE}

## Context

${type_context}

This project is initialized from the vibecoding template factory, based on DevOps, SRE, AI governance and agentic GitHub Copilot usage best practices (source: [github/awesome-copilot](https://github.com/github/awesome-copilot)).

## Decisions

### 1. Base template
- **Choice:** vibecoding-template-${TEMPLATE_TYPE}
- **Reason:** Standardization of ${TEMPLATE_TYPE} projects within the organization

### 2. Copilot governance
- **Choice:** Reference vibecoding-copilot-governance for shared standards
- **Reason:** Avoid duplication, maintain a single source of truth

### 3. Branching strategy
- **Choice:** Simplified Git Flow (main + feature/* branches)
- **Reason:** Simplicity and compatibility with GitHub Flow

### 4. CI/CD
- **Choice:** GitHub Actions
- **Reason:** Native GitHub integration, no external dependency

### 5. Commit conventions
- **Choice:** Conventional Commits (feat, fix, docs, chore...)
- **Reason:** Compatibility with automatic CHANGELOG generation

## Consequences

- Projects automatically inherit governance updates via sync-governance.sh
- Copilot agents (including adr-generator) are available from initialization
- Security hooks (secrets-scanner, tool-guardian) are active from the start

## References

- [vibecoding-copilot-governance](https://github.com/lowcodai/vibecoding-copilot-governance)
- [github/awesome-copilot](https://github.com/github/awesome-copilot)
- [Conventional Commits](https://www.conventionalcommits.org)
EOF

  log_success "ADR-0001 generated: $adr_file"
}

main() {
  parse_args "$@"
  log_section "Generating ADR-0001 for: $REPO_NAME"
  generate_adr_0001
}

main "$@"
