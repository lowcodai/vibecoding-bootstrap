# vibecoding-bootstrap

> Automatic project initialization scripts from the vibecoding templates.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Description

`vibecoding-bootstrap` provides a set of shell scripts to quickly and reproducibly create new projects following vibecoding standards.

## Prerequisites

- **bash** ≥ 4.0 (macOS: `brew install bash`)
- **git** ≥ 2.30
- **gh** (GitHub CLI) ≥ 2.0 — [installation](https://cli.github.com/)
- **curl** ≥ 7.64
- **jq** ≥ 1.6
- **python3** (for reading YAML config files)

Check with:
```bash
./scripts/check-prerequisites.sh
```

## Quick usage

```bash
# Interactive creation (recommended)
./scripts/new-project.sh

# Direct creation
./scripts/new-project.sh --type base --name my-project --visibility private

# Dry-run test
./scripts/new-project.sh --type ai --name test-ai --dry-run --verbose

# Add missing files to an existing project
./scripts/new-project.sh --type infra --name my-infra --extend-only --no-github
```

## Project types

| Type | Description | Template source |
|------|-------------|-----------------|
| `base` | Any new generic project | `vibecoding-template-base` |
| `infra` | Infrastructure, SRE, Ansible, Docker | `vibecoding-template-infra` |
| `ai` | AI, agents, MCP, prompts, RAG | `vibecoding-template-ai` |
| `app` | Web applications, API, MVP, SaaS | `vibecoding-template-app` |
| `m365` | Microsoft 365 Copilot declarative agents (MCP-backed plugins) | `vibecoding-template-m365-agent` |

## CLI Options

```
./scripts/new-project.sh [OPTIONS]

  -t, --type <base|infra|ai|app|m365>   Template type
  -n, --name <repo-name>            Repository name
  -v, --visibility <public|private> GitHub visibility (default: private)
  -o, --org <org>                   GitHub organization
  -d, --output-dir <path>           Destination directory
      --no-github                   Local only (no gh repo create)
      --dry-run                     Simulation without changes
      --verbose                     Detailed logging
      --extend-only                 Only add missing files
      --force                       Overwrite files (confirmation required)
      --no-adr                      Do not generate ADR-0001
      --no-labels                   Do not create GitHub labels
      --skip-awesome-copilot        Do not install awesome-copilot items
  -h, --help                        Help
```

## Architecture

```
scripts/
├── new-project.sh              # Main entry point
├── apply-template.sh           # Instantiation of the template structure
├── sync-governance.sh          # Synchronization from governance
├── install-awesome-copilot.sh  # Installation of skills/agents/hooks/plugins
├── init-github-repo.sh         # Creation of the GitHub repo
├── init-labels.sh              # GitHub labels
├── init-milestones.sh          # v0.1-alpha and v1.0 milestones
├── init-adr.sh                 # Generation of ADR-0001
├── check-prerequisites.sh      # Prerequisite checks
└── lib/
    ├── log.sh                  # Colored logging + run_cmd (dry-run)
    ├── fs.sh                   # Idempotent file operations
    ├── confirm.sh               # Interactive confirmations
    └── gh.sh                   # GitHub CLI wrappers
config/
├── templates.yml               # Mapping type → files to include
├── awesome-copilot-bundles.yml # Awesome-copilot items per type
└── labels.yml                  # Standard GitHub labels
```

## Tests

```bash
# Full test suite
bash tests/test-dry-run.sh
bash tests/test-idempotency.sh
bash tests/test-extend-only.sh
```

## Security

- Dry-run mode: no filesystem changes
- No secrets in generated files
- Explicit confirmation before any `--force`
- Idempotent scripts: safe to re-run
- `--extend-only`: only adds missing files

## References

- [vibecoding-copilot-governance](https://github.com/lowcodai/vibecoding-copilot-governance)
- [github/awesome-copilot](https://github.com/github/awesome-copilot)
- [GitHub CLI](https://cli.github.com/)
