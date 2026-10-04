# Design — vibecoding-bootstrap

## Design principles

### 1. Idempotence by default
Every file operation checks whether the file exists before writing. The `copy_if_not_exists()` function is the base primitive of all scripts.

### 2. Exhaustive dry-run
Every destructive action is wrapped in `run_cmd()`. In `--dry-run` mode, this function shows the command without executing it.

### 3. Separation of concerns
Each script has a single responsibility:
- `apply-template.sh`: file structure
- `sync-governance.sh`: governance injection
- `install-awesome-copilot.sh`: external items
- `init-*.sh`: GitHub-specific initialization

### 4. External configuration (partial — see governance audit B4/B8)
Intended: the choices of which items to include live in YAML files
(`config/templates.yml`, `config/awesome-copilot-bundles.yml`). Actual state: neither file is
read by `apply-template.sh` or `sync-governance.sh`, whose lists are hard-coded; only
`config/labels.yml` is read (by `init-labels.sh`). Treat the scripts as the source of truth until
this is resolved.

### 5. macOS/Linux compatibility
- Bash 4+ required (not macOS's bash 3)
- No GNU-specific extensions without a fallback
- No `readarray`, `declare -A` without a version check

## Script architecture

```
new-project.sh
    │
    ├── check-prerequisites.sh     (tool checks)
    ├── apply-template.sh          (file structure)
    │       ├── lib/log.sh
    │       ├── lib/fs.sh
    │       └── generate_*_files()
    ├── sync-governance.sh         (governance injection)
    │       └── lib/gh.sh
    ├── install-awesome-copilot.sh (item downloads)
    │       └── lib/gh.sh
    ├── init-github-repo.sh        (GitHub creation)
    ├── init-labels.sh             (labels)
    ├── init-milestones.sh         (milestones)
    └── init-adr.sh                (ADR-0001)
```

## Data flow

```
config/templates.yml
    └── apply-template.sh ──────→ <dest>/ (standard files)

config/awesome-copilot-bundles.yml
    ├── sync-governance.sh ─────→ <dest>/.github/instructions/
    │                             <dest>/.github/hooks/
    │                             <dest>/.github/agents/
    └── install-awesome-copilot.sh → <dest>/.github/skills/
                                     <dest>/.github/plugins/
```

## Error handling

- `set -euo pipefail` in every script
- `if/fi` patterns rather than `[[ ]] && { }` (bash 3 + set -e compatibility)
- Functions ending with `return 0` to avoid false positives
- Explicit error messages with context

## Security

- No secrets in generated files
- `--force` requires typing "CONFIRM_OVERWRITE"
- `session-auto-commit` disabled by default
- `grep` over generated files to detect sensitive patterns
