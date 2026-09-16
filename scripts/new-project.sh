#!/usr/bin/env bash
# new-project.sh — Main entry point of the vibecoding factory
#
# Usage: ./scripts/new-project.sh [OPTIONS]
#
# Options:
#   -t, --type <base|infra|ai|app|m365>   Template type
#   -n, --name <repo-name>            Repository name
#   -v, --visibility <public|private> GitHub visibility (default: private)
#   -o, --org <org>                   GitHub organization (optional)
#   -d, --output-dir <path>           Destination directory (default: ../<name>)
#       --no-github                   Do not create the repo on GitHub
#       --dry-run                     Simulation mode without changes
#       --verbose                     Detailed logging
#       --extend-only                 Only add missing files
#       --force                       Overwrite existing files (confirmation required)
#       --no-adr                      Do not generate ADR-0001
#       --no-labels                   Do not create GitHub labels
#       --skip-awesome-copilot        Do not install awesome-copilot items
#   -h, --help                        Help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Import libraries
source "${SCRIPT_DIR}/lib/log.sh"
source "${SCRIPT_DIR}/lib/fs.sh"
source "${SCRIPT_DIR}/lib/confirm.sh"
source "${SCRIPT_DIR}/lib/gh.sh"

# ─── Global variables ──────────────────────────────────────────────────────────
export DRY_RUN=false
export VERBOSE=false
export EXTEND_ONLY=false
export FORCE=false
export AUTO_YES=false

TEMPLATE_TYPE=""
REPO_NAME=""
VISIBILITY="private"
ORG=""
OUTPUT_DIR=""
NO_GITHUB=false
NO_ADR=false
NO_LABELS=false
SKIP_AWESOME_COPILOT=false
LANG_CODE="en"   # Only 'en' is supported. The flag is kept for CLI compatibility; French generation has been retired.

# Counters for the final summary
ACTIONS_DONE=()
ACTIONS_SKIPPED=()
WARNINGS_LIST=()

# ─── Help ──────────────────────────────────────────────────────────────────────
show_help() {
  cat << 'EOF'
vibecoding-bootstrap — GitHub Template Factory

Usage:
  ./scripts/new-project.sh [OPTIONS]

Options:
  -t, --type <base|infra|ai|app|m365>   Template type (interactive if omitted)
  -n, --name <repo-name>            Repository name (interactive if omitted)
  -v, --visibility <public|private> GitHub visibility (default: private)
  -o, --org <org>                   GitHub organization (optional)
  -d, --output-dir <path>           Destination directory (default: ../<name>)
      --no-github                   No GitHub creation (local only)
      --dry-run                     Simulation: shows actions without performing them
      --verbose                     Detailed logging
      --extend-only                 Only add missing files
      --force                       Overwrite existing files (confirmation)
      --no-adr                      Do not generate ADR-0001
      --no-labels                   Do not create GitHub labels
      --skip-awesome-copilot        Do not install awesome-copilot items
  -h, --help                        Show this help

Examples:
  # Interactive creation
  ./scripts/new-project.sh

  # Direct creation, infra type, private repo
  ./scripts/new-project.sh -t infra -n my-infra -v private --org lowcodai

  # Dry-run test
  ./scripts/new-project.sh -t ai -n test-ai --dry-run --verbose

  # Add missing files to an existing project
  ./scripts/new-project.sh -t base -n my-project --extend-only --no-github

Sources:
  Templates:   https://github.com/lowcodai/vibecoding-template-{base,infra,ai,app}
               https://github.com/lowcodai/vibecoding-template-m365-agent (type: m365)
  Governance:  https://github.com/lowcodai/vibecoding-copilot-governance
  Bootstrap:   https://github.com/lowcodai/vibecoding-bootstrap
  Awesome Copilot: https://github.com/github/awesome-copilot
EOF
}

# ─── Argument parsing ──────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--type)            TEMPLATE_TYPE="$2"; shift 2 ;;
      -n|--name)            REPO_NAME="$2"; shift 2 ;;
      -v|--visibility)      VISIBILITY="$2"; shift 2 ;;
      -o|--org)             ORG="$2"; shift 2 ;;
      -d|--output-dir)      OUTPUT_DIR="$2"; shift 2 ;;
      -l|--lang)            LANG_CODE="$2"; shift 2 ;;
      --no-github)          NO_GITHUB=true; shift ;;
      --dry-run)            DRY_RUN=true; shift ;;
      --verbose)            VERBOSE=true; shift ;;
      --extend-only)        EXTEND_ONLY=true; shift ;;
      --force)              FORCE=true; shift ;;
      --yes|-y)             AUTO_YES=true; shift ;;
      --no-adr)             NO_ADR=true; shift ;;
      --no-labels)          NO_LABELS=true; shift ;;
      --skip-awesome-copilot) SKIP_AWESOME_COPILOT=true; shift ;;
      -h|--help)            show_help; exit 0 ;;
      *)                    log_error "Unknown argument: $1"; show_help; exit 1 ;;
    esac
  done
}

# ─── Input validation ──────────────────────────────────────────────────────────
validate_inputs() {
  local valid_types=("base" "infra" "ai" "app" "m365")
  if [[ -n "$TEMPLATE_TYPE" ]]; then
    local valid=false
    for t in "${valid_types[@]}"; do
      [[ "$TEMPLATE_TYPE" == "$t" ]] && valid=true && break
    done
    if [[ "$valid" == "false" ]]; then
      log_error "Invalid type: $TEMPLATE_TYPE (values: base|infra|ai|app|m365)"
      exit 1
    fi
  fi

  if [[ -n "$REPO_NAME" ]]; then
    if ! [[ "$REPO_NAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$ ]]; then
      log_error "Invalid repo name: '$REPO_NAME'"
      log_info "Rules: lowercase letters, digits and hyphens only, no leading/trailing hyphen"
      exit 1
    fi
  fi

  if [[ "$VISIBILITY" != "public" ]] && [[ "$VISIBILITY" != "private" ]]; then
    log_error "Invalid visibility: $VISIBILITY (public|private)"
    exit 1
  fi

  if [[ "$FORCE" == "true" ]] && [[ "$EXTEND_ONLY" == "true" ]]; then
    log_error "--force and --extend-only are incompatible"
    exit 1
  fi
}

# ─── Interactive parameter collection ──────────────────────────────────────────
collect_interactive_params() {
  echo ""
  log_section "vibecoding-bootstrap — New project"
  echo ""

  # Template type
  if [[ -z "$TEMPLATE_TYPE" ]]; then
    select_option "Template type:" \
      "base — Generic (any project)" \
      "infra — Infrastructure, SRE, Ansible, Docker" \
      "ai — AI, agents, MCP, prompts, RAG" \
      "app — Web application, API, SaaS" \
      "m365 — Microsoft 365 Copilot declarative agent"
    TEMPLATE_TYPE="${SELECTED%% *}"
  fi

  # Repo name
  if [[ -z "$REPO_NAME" ]]; then
    while true; do
      echo -n "Repository name (e.g. my-project): "
      read -r REPO_NAME
      if [[ "$REPO_NAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$ ]]; then
        break
      fi
      log_warn "Invalid name. Use: lowercase letters, digits, hyphens (not leading/trailing)"
    done
  fi

  # Visibility
  if [[ "$VISIBILITY" == "private" ]] && [[ "$NO_GITHUB" == "false" ]]; then
    select_option "GitHub visibility:" "private (Recommended)" "public"
    VISIBILITY="${SELECTED%% *}"
  fi

  # Create on GitHub?
  if [[ "$NO_GITHUB" == "false" ]]; then
    if ! confirm "Create the repository on GitHub?"; then
      NO_GITHUB=true
      log_info "Local-only mode selected"
    fi
  fi
}

# ─── Target directory check ────────────────────────────────────────────────────
check_dest_dir() {
  [[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR="$(cd "${BOOTSTRAP_DIR}/.." && pwd)/${REPO_NAME}"

  log_verbose "Target directory: $OUTPUT_DIR"

  if [[ -d "$OUTPUT_DIR" ]]; then
    if [[ "$EXTEND_ONLY" == "true" ]]; then
      log_info "Existing directory — extend-only mode enabled: $OUTPUT_DIR"
      return 0
    fi

    if [[ "$FORCE" == "true" ]]; then
      confirm_destructive \
        "The directory '$OUTPUT_DIR' already exists. All conflicting files will be overwritten." \
        "CONFIRM_OVERWRITE" || exit 1
      # Backup before overwriting
      local backup="${OUTPUT_DIR}.backup.$(date +%Y%m%d%H%M%S)"
      log_warn "Backup created: $backup"
      run_cmd cp -r "$OUTPUT_DIR" "$backup"
    else
      log_error "The directory '$OUTPUT_DIR' already exists."
      log_info "Options:"
      log_info "  --extend-only    to only add missing files"
      log_info "  --force          to overwrite existing files (destructive!)"
      exit 1
    fi
  fi
}

# ─── Prerequisites ──────────────────────────────────────────────────────────────
run_prerequisites_check() {
  log_section "Checking prerequisites"
  if ! bash "${SCRIPT_DIR}/check-prerequisites.sh" 2>&1; then
    if ! confirm "Warnings were detected. Continue anyway?"; then
      log_error "Aborting on prerequisite check"
      exit 1
    fi
  fi
}

# ─── Display plan summary before acting ────────────────────────────────────────
show_plan() {
  log_section "Summary"
  echo ""
  echo "  Template type     : ${TEMPLATE_TYPE}"
  echo "  Repo name         : ${REPO_NAME}"
  echo "  Directory         : ${OUTPUT_DIR}"
  echo "  GitHub visibility : ${VISIBILITY}"
  echo "  Create on GitHub  : $([[ "$NO_GITHUB" == "true" ]] && echo "No" || echo "Yes")"
  echo "  Dry-run mode      : ${DRY_RUN}"
  echo "  Extend-only mode  : ${EXTEND_ONLY}"
  echo "  Force mode        : ${FORCE}"
  echo "  Awesome Copilot   : $([[ "$SKIP_AWESOME_COPILOT" == "true" ]] && echo "Skipped" || echo "Yes")"
  echo "  Generate ADR-0001 : $([[ "$NO_ADR" == "true" ]] && echo "No" || echo "Yes")"
  echo ""

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    if ! confirm "Proceed with creation?"; then
      log_info "Operation cancelled."
      exit 0
    fi
  fi
}

# ─── Execution steps ────────────────────────────────────────────────────────────
step_apply_template() {
  log_section "Step 1/6 — Applying template"
  local args=(
    "--type" "$TEMPLATE_TYPE"
    "--name" "$REPO_NAME"
    "--dest" "$OUTPUT_DIR"
    "--lang" "$LANG_CODE"
  )
  [[ "$DRY_RUN" == "true" ]]     && args+=("--dry-run")
  [[ "$VERBOSE" == "true" ]]     && args+=("--verbose")
  [[ "$EXTEND_ONLY" == "true" ]] && args+=("--extend-only")
  [[ "$FORCE" == "true" ]]       && args+=("--force")

  bash "${SCRIPT_DIR}/apply-template.sh" "${args[@]}"
  ACTIONS_DONE+=("Template ${TEMPLATE_TYPE} applied")
}

step_sync_governance() {
  log_section "Step 2/6 — Governance synchronization"
  local args=(
    "--type" "$TEMPLATE_TYPE"
    "--dest" "$OUTPUT_DIR"
    "--lang" "$LANG_CODE"
  )
  [[ "$DRY_RUN" == "true" ]]     && args+=("--dry-run")
  [[ "$VERBOSE" == "true" ]]     && args+=("--verbose")
  [[ "$EXTEND_ONLY" == "true" ]] && args+=("--extend-only")

  bash "${SCRIPT_DIR}/sync-governance.sh" "${args[@]}"
  ACTIONS_DONE+=("Governance synchronized")
}

step_install_awesome_copilot() {
  if [[ "$SKIP_AWESOME_COPILOT" == "true" ]]; then
    log_skip "Awesome-copilot installation (--skip-awesome-copilot)"
    ACTIONS_SKIPPED+=("Awesome-copilot items")
    return 0
  fi

  log_section "Step 3/6 — Installing awesome-copilot"
  local args=(
    "--type" "$TEMPLATE_TYPE"
    "--dest" "$OUTPUT_DIR"
  )
  [[ "$DRY_RUN" == "true" ]]     && args+=("--dry-run")
  [[ "$VERBOSE" == "true" ]]     && args+=("--verbose")
  [[ "$EXTEND_ONLY" == "true" ]] && args+=("--extend-only")

  bash "${SCRIPT_DIR}/install-awesome-copilot.sh" "${args[@]}"
  ACTIONS_DONE+=("Awesome-copilot items installed")
}

step_generate_adr() {
  if [[ "$NO_ADR" == "true" ]]; then
    log_skip "ADR-0001 generation (--no-adr)"
    ACTIONS_SKIPPED+=("ADR-0001")
    return 0
  fi

  log_section "Step 4/6 — Generating ADR-0001"
  local args=(
    "--dest" "$OUTPUT_DIR"
    "--name" "$REPO_NAME"
    "--type" "$TEMPLATE_TYPE"
  )
  [[ "$DRY_RUN" == "true" ]] && args+=("--dry-run")
  [[ "$VERBOSE" == "true" ]] && args+=("--verbose")

  bash "${SCRIPT_DIR}/init-adr.sh" "${args[@]}"
  ACTIONS_DONE+=("ADR-0001 generated")
}

step_init_github() {
  if [[ "$NO_GITHUB" == "true" ]]; then
    log_skip "GitHub creation (--no-github)"
    ACTIONS_SKIPPED+=("GitHub repo")
    return 0
  fi

  log_section "Step 5/6 — GitHub initialization"

  local gh_args=(
    "--name" "$REPO_NAME"
    "--dest" "$OUTPUT_DIR"
    "--visibility" "$VISIBILITY"
  )
  [[ -n "$ORG" ]]             && gh_args+=("--org" "$ORG")
  [[ "$DRY_RUN" == "true" ]]  && gh_args+=("--dry-run")
  [[ "$VERBOSE" == "true" ]]  && gh_args+=("--verbose")

  bash "${SCRIPT_DIR}/init-github-repo.sh" "${gh_args[@]}" || {
    log_warn "GitHub creation failed — continuing in local mode"
    WARNINGS_LIST+=("GitHub repo not created (check gh auth)")
    return 0
  }
  ACTIONS_DONE+=("GitHub repo created")

  # Labels and milestones
  if [[ "$NO_LABELS" != "true" ]]; then
    local full_name="${ORG:+${ORG}/}${REPO_NAME}"
    [[ -z "$ORG" ]] && {
      local gh_user
      gh_user=$(gh api user --jq '.login' 2>/dev/null || echo "")
      full_name="${gh_user}/${REPO_NAME}"
    }
    local labels_args=(--repo "$full_name")
    [[ "$DRY_RUN" == "true" ]] && labels_args+=(--dry-run)
    bash "${SCRIPT_DIR}/init-labels.sh" "${labels_args[@]}" || \
      WARNINGS_LIST+=("Labels not created")
    local milestones_args=(--repo "$full_name")
    [[ "$DRY_RUN" == "true" ]] && milestones_args+=(--dry-run)
    bash "${SCRIPT_DIR}/init-milestones.sh" "${milestones_args[@]}" || \
      WARNINGS_LIST+=("Milestones not created")
    ACTIONS_DONE+=("Labels and milestones created")
  fi
}

step_finalize() {
  log_section "Step 6/6 — Finalization"

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    # Write the bootstrap log into the project
    local log_file="${OUTPUT_DIR}/.bootstrap-log.txt"
    {
      echo "# vibecoding-bootstrap — Creation log"
      echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "Type: ${TEMPLATE_TYPE}"
      echo "Repo: ${REPO_NAME}"
      echo ""
      echo "## Actions performed"
      for a in "${ACTIONS_DONE[@]}"; do echo "- $a"; done
      echo ""
      echo "## Actions skipped"
      for s in "${ACTIONS_SKIPPED[@]}"; do echo "- $s"; done
      echo ""
      echo "## Warnings"
      for w in "${WARNINGS_LIST[@]}"; do echo "- $w"; done
    } > "$log_file"
    log_success "Bootstrap log: $log_file"
  fi
}

# ─── Final summary ──────────────────────────────────────────────────────────────
show_summary() {
  echo ""
  log_section "Final summary"
  echo ""

  log_success "Project '${REPO_NAME}' created successfully!"
  echo ""

  if [[ ${#ACTIONS_DONE[@]} -gt 0 ]]; then
    echo -e "${_CLR_SUCCESS}Actions performed:${_CLR_RESET}"
    for a in "${ACTIONS_DONE[@]}"; do echo "  ✓ $a"; done
  fi

  if [[ ${#ACTIONS_SKIPPED[@]} -gt 0 ]]; then
    echo ""
    echo -e "${_CLR_SKIP}Skipped:${_CLR_RESET}"
    for s in "${ACTIONS_SKIPPED[@]}"; do echo "  - $s"; done
  fi

  if [[ ${#WARNINGS_LIST[@]} -gt 0 ]]; then
    echo ""
    echo -e "${_CLR_WARN}Warnings:${_CLR_RESET}"
    for w in "${WARNINGS_LIST[@]}"; do echo "  ⚠ $w"; done
  fi

  echo ""
  log_info "Next steps:"
  echo "  1. cd ${OUTPUT_DIR}"
  echo "  2. Edit README.md and .github/copilot-instructions.md"
  echo "  3. Review and complete docs/adr/ADR-0001-initial-decisions.md"
  if [[ "$NO_GITHUB" == "false" ]]; then
    local full_name="${ORG:+${ORG}/}${REPO_NAME}"
    echo "  4. Open: https://github.com/${full_name}"
  fi

  if [[ "$SKIP_AWESOME_COPILOT" == "false" ]]; then
    echo ""
    log_info "Awesome Copilot installed — see: ${OUTPUT_DIR}/.github/awesome-copilot-manifest.md"
  fi
  echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"
  validate_inputs

  # Non-interactive mode if all params are provided
  local interactive=false
  [[ -z "$TEMPLATE_TYPE" ]] || [[ -z "$REPO_NAME" ]] && interactive=true

  if [[ "$interactive" == "true" ]] && [[ "${DRY_RUN:-false}" != "true" ]]; then
    collect_interactive_params
  fi

  # Final checks
  if [[ -z "$TEMPLATE_TYPE" ]]; then
    log_error "--type is required in non-interactive mode"
    exit 1
  fi
  if [[ -z "$REPO_NAME" ]]; then
    log_error "--name is required in non-interactive mode"
    exit 1
  fi
  [[ -z "$OUTPUT_DIR" ]]    && OUTPUT_DIR="$(cd "${BOOTSTRAP_DIR}/.." && pwd)/${REPO_NAME}"

  run_prerequisites_check
  check_dest_dir
  show_plan

  # ── Step execution ──
  step_apply_template
  step_sync_governance
  step_install_awesome_copilot
  step_generate_adr
  step_init_github
  step_finalize

  show_summary
}

main "$@"
