#!/usr/bin/env bash
# apply-template.sh — Copies and instantiates a template into the target directory
# Usage: ./scripts/apply-template.sh --type <base|infra|ai|app|m365> --name <repo-name> --dest <dest-dir>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/log.sh"
source "${SCRIPT_DIR}/lib/fs.sh"

# Trap to show errors with context

# Global variables (can be overridden by new-project.sh)
: "${DRY_RUN:=false}"
: "${VERBOSE:=false}"
: "${EXTEND_ONLY:=false}"
: "${FORCE:=false}"

TEMPLATE_TYPE=""
REPO_NAME=""
DEST_DIR=""
DATE_TODAY="$(date +%Y-%m-%d)"
LANG_CODE="en"   # Only 'en' is supported. The flag is kept for CLI compatibility; French generation has been retired.

# ─── Argument parsing ─────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--type)      TEMPLATE_TYPE="$2"; shift 2 ;;
      -n|--name)      REPO_NAME="$2"; shift 2 ;;
      -d|--dest)      DEST_DIR="$2"; shift 2 ;;
      -l|--lang)      LANG_CODE="$2"; shift 2 ;;
      --dry-run)      DRY_RUN=true; shift ;;
      --verbose)      VERBOSE=true; shift ;;
      --extend-only)  EXTEND_ONLY=true; shift ;;
      --force)        FORCE=true; shift ;;
      *) log_error "Unknown argument: $1"; exit 1 ;;
    esac
  done

  if [[ -z "$TEMPLATE_TYPE" ]]; then
    log_error "--type is required (base|infra|ai|app|m365)"
    exit 1
  fi
  if [[ -z "$REPO_NAME" ]]; then
    log_error "--name is required"
    exit 1
  fi
  if [[ -z "$DEST_DIR" ]]; then
    log_error "--dest is required"
    exit 1
  fi
  if [[ "$LANG_CODE" != "en" ]]; then
    log_error "French generation has been retired; only English (--lang en) is supported (received: ${LANG_CODE})"
    exit 1
  fi
  return 0
}

# ─── Validation ────────────────────────────────────────────────────────────────
validate() {
  local valid_types=("base" "infra" "ai" "app" "m365")
  local valid=false
  for t in "${valid_types[@]}"; do
    [[ "$TEMPLATE_TYPE" == "$t" ]] && valid=true && break
  done
  if [[ "$valid" == "false" ]]; then
    log_error "Invalid type: $TEMPLATE_TYPE (values: base|infra|ai|app|m365)"
    exit 1
  fi

  if ! [[ "$REPO_NAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$ ]]; then
    log_error "Invalid repo name: $REPO_NAME (lowercase alphanumeric and hyphens)"
    exit 1
  fi
  return 0
}

# ─── Placeholder substitution ──────────────────────────────────────────────────
substitute_placeholders() {
  local file="$1"
  [[ ! -f "$file" ]] && return
  local tmp="${file}.tmp"
  sed \
    -e "s/{{REPO_NAME}}/${REPO_NAME}/g" \
    -e "s/{{TEMPLATE_TYPE}}/${TEMPLATE_TYPE}/g" \
    -e "s/{{DATE}}/${DATE_TODAY}/g" \
    -e "s/{{YEAR}}/$(date +%Y)/g" \
    "$file" > "$tmp" && mv "$tmp" "$file"
}

# ─── Copy common base files ────────────────────────────────────────────────────
apply_base_files() {
  log_section "Applying base template"
  local template_src="${BOOTSTRAP_DIR}/../vibecoding-template-base"

  if [[ ! -d "$template_src" ]]; then
    log_warn "Template source not found: $template_src — using inline files"
    generate_base_files_inline
    return
  fi

  # Recursive copy while preserving mode
  find "$template_src" -type f | while IFS= read -r src_file; do
    local rel_path="${src_file#${template_src}/}"
    local dest_file="${DEST_DIR}/${rel_path}"
    copy_if_not_exists "$src_file" "$dest_file"
    [[ "${DRY_RUN:-false}" != "true" ]] && substitute_placeholders "$dest_file"
  done
}

# ─── Inline generation when the template source is absent ─────────────────────
generate_base_files_inline() {
  # In dry-run, list the files that would be created without creating them
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    local base_files=(
      "README.md" "CHANGELOG.md" "BACKLOG.md" "ROADMAP.md" "AGENTS.md"
      "CONTRIBUTING.md" "SECURITY.md" "SUPPORT.md" "LICENSE"
      "docs/adr/.gitkeep" "docs/architecture/.gitkeep" "docs/runbooks/.gitkeep"
    )
    for f in "${base_files[@]}"; do
      log_dry "Create: ${DEST_DIR}/${f}"
    done
    return 0
  fi

  # Create the target directory if absent
  mkdir -p "$DEST_DIR" "${DEST_DIR}/.github"

  log_info "Generating standard files..."

  # README.md
  if [[ ! -f "${DEST_DIR}/README.md" ]]; then
    cat > "${DEST_DIR}/README.md" << EOF
# {{REPO_NAME}}

> Type: ${TEMPLATE_TYPE} | Created on: ${DATE_TODAY}

## Description

<!-- TODO: Describe the project -->

## Quick start

\`\`\`bash
# TODO: Startup commands
\`\`\`

## Documentation

- [Architecture](docs/architecture/)
- [ADR](docs/adr/)
- [Runbooks](docs/runbooks/)
- [BACKLOG](BACKLOG.md)
- [ROADMAP](ROADMAP.md)
- [CONTRIBUTING](CONTRIBUTING.md)

## Available Copilot agents

See [AGENTS.md](AGENTS.md)

## License

See [LICENSE](LICENSE)
EOF
    [[ "${DRY_RUN:-false}" != "true" ]] && sed -i.bak "s/{{REPO_NAME}}/${REPO_NAME}/g" "${DEST_DIR}/README.md" && rm -f "${DEST_DIR}/README.md.bak"
    log_success "Created: README.md"
  else
    log_skip "README.md"
  fi

  # CHANGELOG.md
  if [[ ! -f "${DEST_DIR}/CHANGELOG.md" ]]; then
    cat > "${DEST_DIR}/CHANGELOG.md" << 'EOF'
# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased]

### Added
- Project initialization
EOF
    log_success "Created: CHANGELOG.md"
  else
    log_skip "CHANGELOG.md"
  fi

  # BACKLOG.md
  if [[ ! -f "${DEST_DIR}/BACKLOG.md" ]]; then
    cat > "${DEST_DIR}/BACKLOG.md" << 'EOF'
# Backlog

## Epics

| ID | Title | Priority | Status |
|----|-------|----------|--------|
| E1 | Initialization | High | In progress |

## Stories

| ID | Epic | Title | Priority | Status |
|----|------|-------|----------|--------|
| S1 | E1 | Initial project setup | High | Done |

## Icebox

> Issues not yet planned
EOF
    log_success "Created: BACKLOG.md"
  else
    log_skip "BACKLOG.md"
  fi

  # ROADMAP.md
  if [[ ! -f "${DEST_DIR}/ROADMAP.md" ]]; then
    cat > "${DEST_DIR}/ROADMAP.md" << EOF
# Roadmap — ${REPO_NAME}

## v0.1-alpha — Initialization
- [ ] Initial project setup
- [ ] Initial documentation
- [ ] Basic CI/CD

## v1.0 — Production Ready
- [ ] Core features
- [ ] Full test coverage
- [ ] Complete documentation
EOF
    [[ "${DRY_RUN:-false}" != "true" ]] && sed -i.bak "s/{{REPO_NAME}}/${REPO_NAME}/g" "${DEST_DIR}/ROADMAP.md" && rm -f "${DEST_DIR}/ROADMAP.md.bak"
    log_success "Created: ROADMAP.md"
  else
    log_skip "ROADMAP.md"
  fi

  # AGENTS.md
  if [[ ! -f "${DEST_DIR}/AGENTS.md" ]]; then
    LANG_SECTION=$'## Language\n\nAll repository documentation is written in English (ADRs, PRDs, runbooks, README, code comments). No retroactive translation required for pre-existing content.'
    cat > "${DEST_DIR}/AGENTS.md" << EOF
# Copilot Agents

${LANG_SECTION}

This file lists the GitHub Copilot agents available in this project.
Source: [github/awesome-copilot](https://github.com/github/awesome-copilot)

## Installed agents

| Agent | Description | File |
|-------|-------------|------|
| ADR Generator | Generates Architecture Decision Records | \`.github/agents/adr-generator.agent.md\` |
| PRD Generator | Generates Product Requirement Documents | \`.github/agents/prd-generator.agent.md\` |

## Usage

In GitHub Copilot Chat, reference an agent with \`@<agent-name>\`.
Custom agents are automatically available via their \`.agent.md\` files.
EOF
    log_success "Created: AGENTS.md"
  else
    log_skip "AGENTS.md"
  fi

  # CONTRIBUTING.md
  if [[ ! -f "${DEST_DIR}/CONTRIBUTING.md" ]]; then
    cat > "${DEST_DIR}/CONTRIBUTING.md" << 'EOF'
# Contributing guide

## Prerequisites

- Git
- GitHub CLI (`gh`)
- Repo access

## Workflow

1. Create a branch from `main`: `git checkout -b feat/my-feature`
2. Make your changes
3. Commit using conventional commits: `feat: description`
4. Open a PR against `main`
5. Wait for review

## Conventions

See the standards in [vibecoding-copilot-governance](https://github.com/lowcodai/vibecoding-copilot-governance).

## Conventional commits

```
feat: new feature
fix: bug fix
docs: documentation
chore: maintenance
refactor: refactoring
test: tests
```
EOF
    log_success "Created: CONTRIBUTING.md"
  else
    log_skip "CONTRIBUTING.md"
  fi

  # SECURITY.md
  if [[ ! -f "${DEST_DIR}/SECURITY.md" ]]; then
    cat > "${DEST_DIR}/SECURITY.md" << 'EOF'
# Security Policy

## Reporting a Vulnerability

To report a security vulnerability, please use
[GitHub Security Advisories](../../security/advisories/new) (private).

**Do not open a public issue for security problems.**

## Response Time

- Acknowledgment: within 48h
- Initial assessment: within 7 days
- Fix: depending on severity

## Supported Versions

| Version | Support |
|---------|---------|
| latest  | ✓ |
EOF
    log_success "Created: SECURITY.md"
  fi

  # SUPPORT.md
  if [[ ! -f "${DEST_DIR}/SUPPORT.md" ]]; then
    cat > "${DEST_DIR}/SUPPORT.md" << 'EOF'
# Support

## Getting Help

- Open an [issue](../../issues/new/choose)
- Check the [documentation](docs/)

## Bugs

For bugs, use the [bug_report](.github/ISSUE_TEMPLATE/bug_report.yml) template.
EOF
    log_success "Created: SUPPORT.md"
  else
    log_skip "SUPPORT.md"
  fi

  # LICENSE (MIT)
  if [[ ! -f "${DEST_DIR}/LICENSE" ]]; then
    cat > "${DEST_DIR}/LICENSE" << EOF
MIT License

Copyright (c) $(date +%Y)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
    log_success "Created: LICENSE"
  else
    log_skip "LICENSE"
  fi

  # Directories with .gitkeep
  for dir in docs/adr docs/architecture docs/runbooks; do
    ensure_dir_with_gitkeep "${DEST_DIR}/${dir}"
  done
}

# ─── .github files ──────────────────────────────────────────────────────────────
generate_github_files() {
  # In dry-run, list the files that would be created
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    local github_files=(
      ".github/copilot-instructions.md" ".github/PULL_REQUEST_TEMPLATE.md"
      ".github/ISSUE_TEMPLATE/bug_report.yml" ".github/ISSUE_TEMPLATE/feature_request.yml"
      ".github/workflows/ci.yml" ".github/workflows/governance-check.yml"
      ".github/instructions/.gitkeep" ".github/hooks/.gitkeep" ".github/agents/.gitkeep"
    )
    for f in "${github_files[@]}"; do
      log_dry "Create: ${DEST_DIR}/${f}"
    done
    return 0
  fi

  log_section "Generating .github files"
  local github_dir="${DEST_DIR}/.github"
  mkdir -p "$github_dir"

  # copilot-instructions.md
  if [[ ! -f "${github_dir}/copilot-instructions.md" ]]; then
    cat > "${github_dir}/copilot-instructions.md" << EOF
# Copilot Instructions — ${REPO_NAME}

## Project type
${TEMPLATE_TYPE}

## Context
<!-- TODO: Describe the project context for Copilot agents -->

## Standards
- Follow the conventions defined in [vibecoding-copilot-governance](https://github.com/lowcodai/vibecoding-copilot-governance)
- Use conventional commits
- Document architecture decisions in docs/adr/

## Specific instructions
<!-- TODO: Add project-specific instructions -->
EOF
    [[ "${DRY_RUN:-false}" != "true" ]] && sed -i.bak "s/{{REPO_NAME}}/${REPO_NAME}/g" "${github_dir}/copilot-instructions.md" && rm -f "${github_dir}/copilot-instructions.md.bak"
    log_success "Created: .github/copilot-instructions.md"
  else
    log_skip ".github/copilot-instructions.md"
  fi

  # PULL_REQUEST_TEMPLATE.md
  if [[ ! -f "${github_dir}/PULL_REQUEST_TEMPLATE.md" ]]; then
    cat > "${github_dir}/PULL_REQUEST_TEMPLATE.md" << 'EOF'
## Description

<!-- Describe the changes introduced by this PR -->

## Type of change

- [ ] 🐛 Bug fix
- [ ] ✨ New feature
- [ ] 📝 Documentation
- [ ] 🔧 Maintenance / refactoring
- [ ] 🔒 Security
- [ ] 🏗️ Infrastructure

## Checklist

- [ ] Code follows the project conventions
- [ ] Tests pass locally
- [ ] Documentation is up to date
- [ ] No secrets are included in this commit
- [ ] Necessary ADRs have been created (if architecture decision)

## Related issues

Closes #<!-- issue number -->

## Tests performed

<!-- Describe the tests performed -->
EOF
    log_success "Created: .github/PULL_REQUEST_TEMPLATE.md"
  else
    log_skip ".github/PULL_REQUEST_TEMPLATE.md"
  fi

  # ISSUE_TEMPLATE/bug_report.yml
  run_cmd mkdir -p "${github_dir}/ISSUE_TEMPLATE"
  if [[ ! -f "${github_dir}/ISSUE_TEMPLATE/bug_report.yml" ]]; then
    cat > "${github_dir}/ISSUE_TEMPLATE/bug_report.yml" << 'EOF'
name: 🐛 Bug Report
description: Report a bug
labels: ["type: bug"]
body:
  - type: markdown
    attributes:
      value: "Thank you for filling out this form to report a bug."
  - type: textarea
    id: description
    attributes:
      label: Description
      description: Clear description of the bug
    validations:
      required: true
  - type: textarea
    id: reproduction
    attributes:
      label: Steps to reproduce
      placeholder: |
        1. Go to '...'
        2. Do '...'
        3. See the error
    validations:
      required: true
  - type: textarea
    id: expected
    attributes:
      label: Expected behavior
    validations:
      required: true
  - type: textarea
    id: environment
    attributes:
      label: Environment
      placeholder: "OS, version, etc."
EOF
    log_success "Created: .github/ISSUE_TEMPLATE/bug_report.yml"
  else
    log_skip ".github/ISSUE_TEMPLATE/bug_report.yml"
  fi

  # ISSUE_TEMPLATE/feature_request.yml
  if [[ ! -f "${github_dir}/ISSUE_TEMPLATE/feature_request.yml" ]]; then
    cat > "${github_dir}/ISSUE_TEMPLATE/feature_request.yml" << 'EOF'
name: ✨ Feature Request
description: Propose a new feature
labels: ["type: feature"]
body:
  - type: textarea
    id: problem
    attributes:
      label: Problem to solve
      description: What problem does this feature solve?
    validations:
      required: true
  - type: textarea
    id: solution
    attributes:
      label: Proposed solution
    validations:
      required: true
  - type: dropdown
    id: priority
    attributes:
      label: Priority
      options: ["Critical", "High", "Medium", "Low"]
EOF
    log_success "Created: .github/ISSUE_TEMPLATE/feature_request.yml"
  else
    log_skip ".github/ISSUE_TEMPLATE/feature_request.yml"
  fi

  # Base CI/CD workflows
  run_cmd mkdir -p "${github_dir}/workflows"

  if [[ ! -f "${github_dir}/workflows/ci.yml" ]]; then
    cat > "${github_dir}/workflows/ci.yml" << 'EOF'
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  lint:
    name: Lint & Validate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate YAML files
        run: |
          find . -name "*.yml" -o -name "*.yaml" | xargs -I{} sh -c 'python3 -c "import yaml; yaml.safe_load(open(\"{}\")); print(\"OK: {}\")"'

  security:
    name: Security Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      # On a push, `base`/`head` must be the before/after commits of the push (not
      # "main"/HEAD, which point to the same commit once checkout is done — TruffleHog
      # then errors out with "BASE and HEAD commits are the same"). `before` is the null SHA
      # on a branch's very first push: in that case we scan the whole history (no `base`)
      # instead of failing.
      - name: Scan for secrets (push)
        if: github.event_name == 'push' && github.event.before != '0000000000000000000000000000000000000000'
        uses: trufflesecurity/trufflehog@main
        with:
          path: ./
          base: ${{ github.event.before }}
          head: ${{ github.event.after }}
      - name: Scan for secrets (push — first commit of the branch)
        if: github.event_name == 'push' && github.event.before == '0000000000000000000000000000000000000000'
        uses: trufflesecurity/trufflehog@main
        with:
          path: ./
      - name: Scan for secrets (pull_request)
        if: github.event_name == 'pull_request'
        uses: trufflesecurity/trufflehog@main
        with:
          path: ./
          base: ${{ github.event.pull_request.base.sha }}
          head: ${{ github.event.pull_request.head.sha }}
EOF
    log_success "Created: .github/workflows/ci.yml"
  else
    log_skip ".github/workflows/ci.yml"
  fi

  if [[ ! -f "${github_dir}/workflows/governance-check.yml" ]]; then
    cat > "${github_dir}/workflows/governance-check.yml" << 'EOF'
name: Governance Check

on:
  pull_request:
    branches: [main]

jobs:
  check-files:
    name: Check required files
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check required files
        run: |
          required_files=(
            "README.md"
            "CHANGELOG.md"
            "SECURITY.md"
            "CONTRIBUTING.md"
            ".github/copilot-instructions.md"
          )
          for f in "${required_files[@]}"; do
            if [[ ! -f "$f" ]]; then
              echo "MISSING: $f"
              exit 1
            fi
            echo "OK: $f"
          done

  check-secrets:
    name: Check for absence of secrets
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check for hardcoded secrets patterns
        run: |
          if grep -rE "(password|secret|api_key|token)\s*=\s*['\"][^'\"]{8,}" \
            --include="*.yml" --include="*.yaml" --include="*.json" \
            --exclude-dir=".git" . 2>/dev/null; then
            echo "Potential secrets found!"
            exit 1
          fi
          echo "No obvious secrets found"
EOF
    log_success "Created: .github/workflows/governance-check.yml"
  else
    log_skip ".github/workflows/governance-check.yml"
  fi

  # Directories for instructions, hooks, agents
  for dir in instructions hooks agents; do
    ensure_dir_with_gitkeep "${github_dir}/${dir}"
  done
}

# ─── Type-specific files ────────────────────────────────────────────────────────
apply_type_specific() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_dry "Apply type-specific files: $TEMPLATE_TYPE"
    return 0
  fi
  log_section "Applying type-specific files: $TEMPLATE_TYPE"

  case "$TEMPLATE_TYPE" in
    infra) apply_infra_files ;;
    ai)    apply_ai_files ;;
    app)   apply_app_files ;;
    m365)  apply_m365_files ;;
    base)  log_verbose "Type base: no additional type-specific files" ;;
  esac
}

apply_infra_files() {
  for dir in ansible/inventory ansible/playbooks ansible/roles docker \
             monitoring/dashboards monitoring/alerts cmdb; do
    ensure_dir_with_gitkeep "${DEST_DIR}/${dir}"
  done

  # Ansible lint workflow
  if [[ ! -f "${DEST_DIR}/.github/workflows/ansible-lint.yml" ]]; then
    cat > "${DEST_DIR}/.github/workflows/ansible-lint.yml" << 'EOF'
name: Ansible Lint
on:
  push:
    paths: ["ansible/**"]
  pull_request:
    paths: ["ansible/**"]
jobs:
  ansible-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ansible/ansible-lint@v26
        with:
          path: ansible/
EOF
    log_success "Created: .github/workflows/ansible-lint.yml"
  fi

  # Docker build workflow
  if [[ ! -f "${DEST_DIR}/.github/workflows/docker-build.yml" ]]; then
    cat > "${DEST_DIR}/.github/workflows/docker-build.yml" << 'EOF'
name: Docker Build
on:
  push:
    paths: ["docker/**", "Dockerfile*"]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build Docker image
        run: |
          if [ -f Dockerfile ] || find . -maxdepth 3 -iname 'Dockerfile*' -not -path './.git/*' | grep -q .; then
            docker build -t ${{ github.repository }}:${{ github.sha }} .
          else
            echo "No Dockerfile found — nothing to build yet. Add one under docker/ or at the repo root to enable this check."
          fi
EOF
    log_success "Created: .github/workflows/docker-build.yml"
  fi
}

apply_ai_files() {
  for dir in agents prompts mcp rag llm-wiki; do
    ensure_dir_with_gitkeep "${DEST_DIR}/${dir}"
  done

  if [[ ! -f "${DEST_DIR}/.github/workflows/ai-safety-check.yml" ]]; then
    cat > "${DEST_DIR}/.github/workflows/ai-safety-check.yml" << 'EOF'
name: AI Safety Check
on:
  pull_request:
    paths: ["agents/**", "prompts/**", ".github/instructions/**"]
jobs:
  safety-review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check agent files structure
        run: |
          find .github/agents -name "*.agent.md" -exec echo "Agent file: {}" \;
          find .github/instructions -name "*.instructions.md" -exec echo "Instruction file: {}" \;
      - name: Check for unsafe patterns in prompts
        run: |
          if grep -rE "(ignore previous instructions|jailbreak|bypass safety)" prompts/ 2>/dev/null; then
            echo "Unsafe patterns found in prompts!"
            exit 1
          fi
          echo "AI safety check passed"
EOF
    log_success "Created: .github/workflows/ai-safety-check.yml"
  fi
}

apply_app_files() {
  for dir in src tests public; do
    ensure_dir_with_gitkeep "${DEST_DIR}/${dir}"
  done

  if [[ ! -f "${DEST_DIR}/.github/workflows/release.yml" ]]; then
    cat > "${DEST_DIR}/.github/workflows/release.yml" << 'EOF'
name: Release
on:
  push:
    tags: ["v*"]
jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
EOF
    log_success "Created: .github/workflows/release.yml"
  fi

  if [[ ! -f "${DEST_DIR}/.github/workflows/a11y-check.yml" ]]; then
    cat > "${DEST_DIR}/.github/workflows/a11y-check.yml" << 'EOF'
name: Accessibility Check
on:
  pull_request:
    paths: ["src/**", "public/**"]
jobs:
  a11y:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Accessibility audit placeholder
        run: echo "TODO: Configure axe-core or pa11y for accessibility tests"
EOF
    log_success "Created: .github/workflows/a11y-check.yml"
  fi
}

apply_m365_files() {
  # appPackage/: Teams app manifest + declarative agent manifest + MCP plugin manifest
  # (three-manifest family — see vibecoding-template-m365-agent's own ADR-0001 example).
  # env/: Microsoft 365 Agents Toolkit per-environment config (.env.local, .env.dev, ...).
  for dir in appPackage env; do
    ensure_dir_with_gitkeep "${DEST_DIR}/${dir}"
  done

  if [[ ! -f "${DEST_DIR}/.github/workflows/m365-agent-manifest-check.yml" ]]; then
    cat > "${DEST_DIR}/.github/workflows/m365-agent-manifest-check.yml" << 'EOF'
name: M365 Agent Manifest Check
on:
  pull_request:
    paths: ["appPackage/**"]
jobs:
  manifest-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate manifest JSON files are well-formed
        run: |
          shopt -s globstar nullglob
          found=0
          for f in appPackage/**/*.json; do
            found=1
            echo "Checking $f"
            python3 -m json.tool "$f" > /dev/null
          done
          if [[ "$found" -eq 0 ]]; then
            echo "No manifest JSON files found yet under appPackage/ — nothing to validate."
          fi
      - name: Reminder
        run: |
          echo "This is a syntax check only. Validate against the current Microsoft 365 Agents"
          echo "Toolkit schema (https://github.com/microsoft/m365-agent-templates) before publishing."
EOF
    log_success "Created: .github/workflows/m365-agent-manifest-check.yml"
  fi
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"
  validate

  log_section "Applying template '$TEMPLATE_TYPE' → $DEST_DIR"

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    run_cmd mkdir -p "$DEST_DIR"
    run_cmd mkdir -p "${DEST_DIR}/.github"
  fi

  generate_base_files_inline
  generate_github_files
  apply_type_specific

  log_section "Template applied successfully"
  log_info "Directory: $DEST_DIR"
}

main "$@"
