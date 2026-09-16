#!/usr/bin/env bash
# sync-governance.sh — Synchronizes governance items from vibecoding-copilot-governance
# Usage: ./scripts/sync-governance.sh --type <base|infra|ai|app|m365> --dest <dest-dir>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
GOVERNANCE_DIR="${GOVERNANCE_DIR:-${BOOTSTRAP_DIR}/../vibecoding-copilot-governance}"
source "${SCRIPT_DIR}/lib/log.sh"
source "${SCRIPT_DIR}/lib/fs.sh"

: "${DRY_RUN:=false}"
: "${VERBOSE:=false}"
: "${EXTEND_ONLY:=false}"

TEMPLATE_TYPE=""
DEST_DIR=""
LANG_CODE="en"   # default: English. Override: --lang fr to continue an existing French line.

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--type)      TEMPLATE_TYPE="$2"; shift 2 ;;
      -d|--dest)      DEST_DIR="$2"; shift 2 ;;
      -l|--lang)      LANG_CODE="$2"; shift 2 ;;
      --dry-run)      DRY_RUN=true; shift ;;
      --verbose)      VERBOSE=true; shift ;;
      --extend-only)  EXTEND_ONLY=true; shift ;;
      *) log_error "Unknown argument: $1"; exit 1 ;;
    esac
  done
  if [[ -z "$TEMPLATE_TYPE" ]]; then
    log_error "--type is required"
    exit 1
  fi
  if [[ -z "$DEST_DIR" ]]; then
    log_error "--dest is required"
    exit 1
  fi
  if [[ "$LANG_CODE" != "en" && "$LANG_CODE" != "fr" ]]; then
    log_error "--lang must be 'en' or 'fr' (received: ${LANG_CODE})"
    exit 1
  fi
  return 0
}

# Loads the list of items to synchronize from awesome-copilot-bundles.yml
# for the given type (common + type-specific)
get_bundle_elements() {
  local type="$1" category="$2"
  local config="${BOOTSTRAP_DIR}/config/awesome-copilot-bundles.yml"

  if ! command -v python3 &>/dev/null; then
    log_warn "python3 not available — cannot parse the config YAML"
    return 0
  fi

  python3 - "$config" "$type" "$category" << 'PYEOF'
import sys, json

try:
    import yaml
except ImportError:
    # PyYAML not installed: empty output
    sys.exit(0)

config_file, proj_type, category = sys.argv[1], sys.argv[2], sys.argv[3]
with open(config_file) as f:
    data = yaml.safe_load(f)

# Combine common and type-specific
results = []
for scope in ['common', proj_type]:
    items = data.get(scope if scope == 'common' else f'bundles.{proj_type}', {})
    if scope == 'common':
        items = data.get('common', {})
    else:
        items = data.get('bundles', {}).get(proj_type, {})

    for item in items.get(category, []):
        if isinstance(item, dict):
            if not item.get('optional', False):
                results.append(item.get('name', ''))
        elif isinstance(item, str):
            results.append(item)

for r in results:
    if r:
        print(r)
PYEOF
}

# Synchronizes instructions from governance into the project
sync_instructions() {
  log_section "Synchronizing instructions"
  local src="${GOVERNANCE_DIR}/instructions"
  local dest="${DEST_DIR}/.github/instructions"

  if [[ ! -d "$src" ]]; then
    log_warn "Missing instructions directory: $src"
    return
  fi

  run_cmd mkdir -p "$dest"

  # Common items
  for f in \
    "devops-core-principles.instructions.md" \
    "github-actions-ci-cd-best-practices.instructions.md"; do
    [[ -f "${src}/${f}" ]] && copy_if_not_exists "${src}/${f}" "${dest}/${f}" || true
  done

  # Type-specific items
  case "$TEMPLATE_TYPE" in
    infra)
      for f in "ansible.instructions.md" "containerization-docker-best-practices.instructions.md"; do
        [[ -f "${src}/${f}" ]] && copy_if_not_exists "${src}/${f}" "${dest}/${f}" || true
      done
      ;;
    ai|m365)
      for f in "agent-safety.instructions.md" "agent-skills.instructions.md" \
               "ai-prompt-engineering-safety-best-practices.instructions.md"; do
        [[ -f "${src}/${f}" ]] && copy_if_not_exists "${src}/${f}" "${dest}/${f}" || true
      done
      ;;
    app)
      for f in "a11y.instructions.md" "containerization-docker-best-practices.instructions.md"; do
        [[ -f "${src}/${f}" ]] && copy_if_not_exists "${src}/${f}" "${dest}/${f}" || true
      done
      ;;
  esac
}

# Synchronizes hooks from governance
sync_hooks() {
  log_section "Synchronizing hooks"
  local src="${GOVERNANCE_DIR}/hooks"
  local dest="${DEST_DIR}/.github/hooks"

  if [[ ! -d "$src" ]]; then
    log_warn "Missing hooks directory: $src"
    return
  fi

  run_cmd mkdir -p "$dest"

  # Common hooks (all types)
  for hook in "tool-guardian" "secrets-scanner" "governance-audit"; do
    [[ -d "${src}/${hook}" ]] && copy_dir_if_not_exists "${src}/${hook}" "${dest}/${hook}" || true
  done

  # Type-specific hooks
  case "$TEMPLATE_TYPE" in
    infra|ai|app|m365)
      for hook in "dependency-license-checker" "fix-broken-links"; do
        [[ -d "${src}/${hook}" ]] && copy_dir_if_not_exists "${src}/${hook}" "${dest}/${hook}" || true
      done
      ;;
  esac

  if [[ "$TEMPLATE_TYPE" == "infra" ]] || [[ "$TEMPLATE_TYPE" == "ai" ]] || [[ "$TEMPLATE_TYPE" == "m365" ]]; then
    [[ -d "${src}/attester-import-check" ]] && \
      copy_dir_if_not_exists "${src}/attester-import-check" "${dest}/attester-import-check" || true
  fi

  if [[ "$TEMPLATE_TYPE" == "ai" ]] || [[ "$TEMPLATE_TYPE" == "m365" ]]; then
    [[ -d "${src}/session-logger" ]] && \
      copy_dir_if_not_exists "${src}/session-logger" "${dest}/session-logger" || true
  fi
}

# Synchronizes agents from governance
sync_agents() {
  log_section "Synchronizing agents"
  local src="${GOVERNANCE_DIR}/agents"
  local dest="${DEST_DIR}/.github/agents"

  if [[ ! -d "$src" ]]; then
    log_warn "Missing agents directory: $src"
    return
  fi

  run_cmd mkdir -p "$dest"

  # Universal agent: ADR generator
  [[ -f "${src}/adr-generator.agent.md" ]] && \
    copy_if_not_exists "${src}/adr-generator.agent.md" "${dest}/adr-generator.agent.md" || true

  # Universal agent: Runbook generator (ADR-0004 — executes downstream of an accepted ADR,
  # designed for hermes-solo execution on the local model by default)
  [[ -f "${src}/runbook-generator.agent.md" ]] && \
    copy_if_not_exists "${src}/runbook-generator.agent.md" "${dest}/runbook-generator.agent.md" || true

  case "$TEMPLATE_TYPE" in
    ai|m365)
      for agent in "ai-readiness-reporter.agent.md" "agent-governance-reviewer.agent.md" "ai-team-dev.agent.md"; do
        [[ -f "${src}/${agent}" ]] && copy_if_not_exists "${src}/${agent}" "${dest}/${agent}" || true
      done
      ;;
    app)
      for agent in "accessibility.agent.md" "accessibility-runtime-tester.agent.md"; do
        [[ -f "${src}/${agent}" ]] && copy_if_not_exists "${src}/${agent}" "${dest}/${agent}" || true
      done
      ;;
  esac
}

# Synchronizes the Hermes continuity contract (ADR-0021) from governance.
# Common to all project types — context continuity is not
# specific to base|infra|ai|app.
sync_hermes() {
  log_section "Synchronizing the Hermes continuity contract"
  local src="${GOVERNANCE_DIR}/hermes"

  if [[ ! -d "$src" ]]; then
    log_warn "Missing hermes/ directory: $src"
    return
  fi

  # .hermes.md — project name substitution (PROJECT_NAME derived from DEST_DIR unless
  # overridden via --project-name). The model → context-threshold mapping table
  # (Qwen3.8-27B-NVFP4/Sonnet 5/GPT-5.6 Sol) is embedded as-is from the source — keep it
  # in sync with governance/hermes/.hermes.md if the models used change.
  local project_name="${PROJECT_NAME:-$(basename "$DEST_DIR")}"
  if [[ -f "${DEST_DIR}/.hermes.md" ]]; then
    log_skip "${DEST_DIR}/.hermes.md"
  else
    write_template "${src}/.hermes.md" "${DEST_DIR}/.hermes.md" "PROJECT_NAME=${project_name}"
  fi

  # docs/operations/ skeleton — copied only once, never overwritten (copy_if_not_exists):
  # a CURRENT.md already in use must never be replaced by the empty skeleton.
  local ops_dest="${DEST_DIR}/docs/operations"
  run_cmd mkdir -p "$ops_dest"
  for f in CURRENT.md HANDOFF.md ACTIVITY.md; do
    [[ -f "${src}/docs-operations-templates/${f}" ]] && \
      copy_if_not_exists "${src}/docs-operations-templates/${f}" "${ops_dest}/${f}" || true
  done
}

# Synchronizes the PRD/ADR/Plan/Runbook methodology from governance.
# Common to all project types — the methodology does not depend on base|infra|ai|app.
sync_methodology() {
  log_section "Synchronizing the PRD/ADR/Plan/Runbook methodology"
  local src="${GOVERNANCE_DIR}"

  run_cmd mkdir -p "${DEST_DIR}/docs/prd" "${DEST_DIR}/docs/adr" "${DEST_DIR}/docs/runbooks" \
    "${DEST_DIR}/docs/methodology"

  [[ -f "${src}/hermes/docs-prd-templates/README.md" ]] && \
    copy_if_not_exists "${src}/hermes/docs-prd-templates/README.md" "${DEST_DIR}/docs/prd/README.md" || true
  [[ -f "${src}/hermes/docs-adr-templates/README.md" ]] && \
    copy_if_not_exists "${src}/hermes/docs-adr-templates/README.md" "${DEST_DIR}/docs/adr/README.md" || true
  [[ -f "${src}/hermes/docs-runbook-templates/README.md" ]] && \
    copy_if_not_exists "${src}/hermes/docs-runbook-templates/README.md" "${DEST_DIR}/docs/runbooks/README.md" || true
  [[ -f "${src}/docs/methodology/PRD-ADR-PLAN-RUNBOOK-WORKFLOW.md" ]] && \
    copy_if_not_exists "${src}/docs/methodology/PRD-ADR-PLAN-RUNBOOK-WORKFLOW.md" \
      "${DEST_DIR}/docs/methodology/PRD-ADR-PLAN-RUNBOOK-WORKFLOW.md" || true

  run_cmd mkdir -p "${DEST_DIR}/.github/agents"
  [[ -f "${src}/agents/prd-generator.agent.md" ]] && \
    copy_if_not_exists "${src}/agents/prd-generator.agent.md" "${DEST_DIR}/.github/agents/prd-generator.agent.md" || true
}

# Synchronizes standard templates from governance
sync_templates() {
  log_section "Synchronizing standard templates"
  local src="${GOVERNANCE_DIR}/templates"

  if [[ ! -d "$src" ]]; then
    log_warn "Missing templates directory: $src"
    return
  fi

  # PULL_REQUEST_TEMPLATE (if not already created by apply-template.sh)
  [[ -f "${src}/PULL_REQUEST_TEMPLATE.md" ]] && \
    copy_if_not_exists "${src}/PULL_REQUEST_TEMPLATE.md" "${DEST_DIR}/.github/PULL_REQUEST_TEMPLATE.md" || true

  # ISSUE_TEMPLATE
  run_cmd mkdir -p "${DEST_DIR}/.github/ISSUE_TEMPLATE"
  if [[ -d "${src}/ISSUE_TEMPLATE" ]]; then
    for tmpl in "${src}/ISSUE_TEMPLATE/"*.yml; do
      [[ -f "$tmpl" ]] && copy_if_not_exists "$tmpl" "${DEST_DIR}/.github/ISSUE_TEMPLATE/$(basename "$tmpl")" || true
    done
  fi
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"

  log_section "Governance synchronization → $DEST_DIR (type: $TEMPLATE_TYPE)"

  if [[ ! -d "$GOVERNANCE_DIR" ]]; then
    log_warn "vibecoding-copilot-governance not found: $GOVERNANCE_DIR"
    log_info "Synchronization skipped — create vibecoding-copilot-governance first"
    return 0
  fi

  sync_instructions
  sync_hooks
  sync_agents
  sync_templates
  sync_hermes
  sync_methodology

  log_success "Governance synchronization complete"
}

main "$@"
