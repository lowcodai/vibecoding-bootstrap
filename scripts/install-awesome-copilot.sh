#!/usr/bin/env bash
# install-awesome-copilot.sh — Installs awesome-copilot items for a project type
# Usage: ./scripts/install-awesome-copilot.sh --type <base|infra|ai|app|m365> --dest <dest-dir>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/log.sh"
source "${SCRIPT_DIR}/lib/fs.sh"
source "${SCRIPT_DIR}/lib/gh.sh"

: "${DRY_RUN:=false}"
: "${VERBOSE:=false}"
: "${EXTEND_ONLY:=false}"

# Reference SHA for reproducibility (updated manually)
AWESOME_COPILOT_REF="dae77f24132c1d686c30fd5b29aee0d63668d1d2"
TEMPLATE_TYPE=""
DEST_DIR=""
SKIP_PLUGINS=false

INSTALLED_SKILLS=()
INSTALLED_AGENTS=()
INSTALLED_HOOKS=()
INSTALLED_PLUGINS=()
SKIPPED=()

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--type)          TEMPLATE_TYPE="$2"; shift 2 ;;
      -d|--dest)          DEST_DIR="$2"; shift 2 ;;
      --ref)              AWESOME_COPILOT_REF="$2"; shift 2 ;;
      --skip-plugins)     SKIP_PLUGINS=true; shift ;;
      --dry-run)          DRY_RUN=true; shift ;;
      --verbose)          VERBOSE=true; shift ;;
      --extend-only)      EXTEND_ONLY=true; shift ;;
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
  return 0
}

# Returns the skills to install for the given type
get_skills_for_type() {
  local type="$1"
  # Skills common to all types
  local skills=(
    "acquire-codebase-knowledge"
    "breakdown-plan"
    "breakdown-epic-arch"
    "breakdown-epic-pm"
    "breakdown-feature-prd"
    "breakdown-feature-implementation"
    "breakdown-test"
    "audit-integrity"
  )

  case "$type" in
    infra)
      skills+=("agent-supply-chain")
      ;;
    ai)
      skills+=(
        "acreadiness-assess"
        "acreadiness-generate-instructions"
        "agent-governance"
        "agentic-eval"
        "ai-prompt-engineering-safety-review"
        "agent-owasp-compliance"
        "agent-supply-chain"
      )
      ;;
    app)
      skills+=("agent-owasp-compliance")
      ;;
    m365)
      skills+=(
        "agent-owasp-compliance"
        "mcp-create-declarative-agent"
        "declarative-agents"
        "entra-agent-user"
        "mcp-security-audit"
        "mcp-implementation-security-review"
        "threat-model-analyst"
        "secret-scanning"
        "mcp-deploy-manage-agents"
      )
      ;;
  esac

  printf '%s\n' "${skills[@]}"
}

# Returns the agents to install for the given type
get_agents_for_type() {
  local type="$1"
  local agents=("adr-generator.agent.md")

  case "$type" in
    ai)
      agents+=(
        "ai-readiness-reporter.agent.md"
        "agent-governance-reviewer.agent.md"
        "ai-team-dev.agent.md"
      )
      ;;
    app)
      agents+=(
        "accessibility.agent.md"
        "accessibility-runtime-tester.agent.md"
      )
      ;;
    m365)
      agents+=(
        "declarative-agents-architect.agent.md"
        "mcp-m365-agent-expert.agent.md"
      )
      ;;
  esac

  printf '%s\n' "${agents[@]}"
}

# Returns the plugins to install for the given type
get_plugins_for_type() {
  local type="$1"
  local plugins=("arch")

  case "$type" in
    ai)
      plugins+=("acreadiness-cockpit" "ai-team-orchestration")
      ;;
    app)
      plugins+=("ai-team-orchestration")
      ;;
    m365)
      plugins+=("mcp-m365-copilot")
      ;;
  esac

  printf '%s\n' "${plugins[@]}"
}

# Installs the skills
install_skills() {
  log_section "Installing awesome-copilot skills"
  local skills_dest="${DEST_DIR}/.github/skills"
  run_cmd mkdir -p "$skills_dest"

  while IFS= read -r skill; do
    [[ -z "$skill" ]] && continue
    log_info "Skill: $skill"
    gh_install_skill "$skill" "$skills_dest"
    INSTALLED_SKILLS+=("$skill")
  done < <(get_skills_for_type "$TEMPLATE_TYPE")
}

# Installs the agents
install_agents() {
  log_section "Installing awesome-copilot agents"
  local agents_dest="${DEST_DIR}/.github/agents"
  run_cmd mkdir -p "$agents_dest"

  while IFS= read -r agent_file; do
    [[ -z "$agent_file" ]] && continue
    local agent_name="${agent_file%.agent.md}"
    log_info "Agent: $agent_name"
    gh_fetch_awesome_copilot_file "agents/${agent_file}" "${agents_dest}/${agent_file}" "$AWESOME_COPILOT_REF"
    INSTALLED_AGENTS+=("$agent_name")
  done < <(get_agents_for_type "$TEMPLATE_TYPE")
}

# Installs the instructions
install_instructions() {
  log_section "Installing awesome-copilot instructions"
  local instr_dest="${DEST_DIR}/.github/instructions"
  run_cmd mkdir -p "$instr_dest"

  # Common instructions
  local common_instructions=(
    "devops-core-principles.instructions.md"
    "github-actions-ci-cd-best-practices.instructions.md"
  )

  # Type-specific instructions
  local type_instructions=()
  case "$TEMPLATE_TYPE" in
    infra)
      type_instructions=("ansible.instructions.md" "containerization-docker-best-practices.instructions.md")
      ;;
    ai)
      type_instructions=(
        "agent-safety.instructions.md"
        "agent-skills.instructions.md"
        "ai-prompt-engineering-safety-best-practices.instructions.md"
      )
      ;;
    app)
      type_instructions=("a11y.instructions.md" "containerization-docker-best-practices.instructions.md")
      ;;
    m365)
      type_instructions=(
        "declarative-agents-microsoft365.instructions.md"
        "mcp-m365-copilot.instructions.md"
        "security-and-owasp.instructions.md"
      )
      ;;
  esac

  local all_instructions=("${common_instructions[@]}" "${type_instructions[@]}")
  for instr in "${all_instructions[@]}"; do
    log_info "Instruction: $instr"
    gh_fetch_awesome_copilot_file "instructions/${instr}" "${instr_dest}/${instr}" "$AWESOME_COPILOT_REF"
  done
}

# Installs the plugins
install_plugins() {
  if [[ "$SKIP_PLUGINS" == "true" ]]; then
    log_skip "Plugins (--skip-plugins enabled)"
    return
  fi

  log_section "Installing awesome-copilot plugins"
  log_info "Note: plugins are installed in the global Copilot environment (not in the repo)"

  while IFS= read -r plugin; do
    [[ -z "$plugin" ]] && continue
    log_info "Plugin: $plugin"
    gh_install_plugin "$plugin"
    INSTALLED_PLUGINS+=("$plugin")
  done < <(get_plugins_for_type "$TEMPLATE_TYPE")
}

# Generates an installation summary in the project
generate_install_summary() {
  local summary_file="${DEST_DIR}/.github/awesome-copilot-manifest.md"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_dry "Write: $summary_file"
    return
  fi

  cat > "$summary_file" << EOF
# Awesome Copilot Manifest — ${TEMPLATE_TYPE}

> Generated on: $(date +%Y-%m-%d)
> Awesome-copilot reference: \`${AWESOME_COPILOT_REF}\`
> Source: https://github.com/github/awesome-copilot

## Installed skills

$(for s in "${INSTALLED_SKILLS[@]}"; do echo "- \`$s\` — \`.github/skills/$s/\`"; done)

## Installed agents

$(for a in "${INSTALLED_AGENTS[@]}"; do echo "- \`$a\` — \`.github/agents/$a.agent.md\`"; done)

## Installed plugins (global environment)

$(for p in "${INSTALLED_PLUGINS[@]}"; do echo "- \`$p\`"; done)

## Installed instructions

\`\`.github/instructions/\`\`

## Updating

To update the awesome-copilot items:
\`\`\`bash
# From vibecoding-bootstrap:
./scripts/install-awesome-copilot.sh --type ${TEMPLATE_TYPE} --dest . --ref <new-sha>
\`\`\`

## Manual plugin installation

If \`copilot plugin install\` is not available:
1. Open VS Code
2. In the Extensions panel: type \`@agentPlugins\`
3. Install: $(IFS=', '; echo "${INSTALLED_PLUGINS[*]:-none}")
EOF
  log_success "Manifest created: $summary_file"
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"

  log_section "Installing awesome-copilot (type: $TEMPLATE_TYPE)"
  log_info "Reference: $AWESOME_COPILOT_REF"

  if ! command -v gh &>/dev/null && [[ "${DRY_RUN:-false}" != "true" ]]; then
    log_warn "gh CLI not available — downloads via curl (fallback)"
  fi

  install_skills
  install_agents
  install_instructions
  install_plugins
  generate_install_summary

  log_section "Installation summary"
  log_success "Skills: ${#INSTALLED_SKILLS[@]} installed"
  log_success "Agents: ${#INSTALLED_AGENTS[@]} installed"
  log_success "Plugins: ${#INSTALLED_PLUGINS[@]} processed"
  log_info "See: ${DEST_DIR}/.github/awesome-copilot-manifest.md"
}

main "$@"
