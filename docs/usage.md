# Usage guide — vibecoding-bootstrap

## Installation

```bash
git clone https://github.com/lowcodai/vibecoding-bootstrap
cd vibecoding-bootstrap
./scripts/check-prerequisites.sh
```

## Creating a new project

### Interactive mode

```bash
./scripts/new-project.sh
```

The script asks the following questions:
1. Project type (base / infra / ai / app)
2. Repository name (alphanumeric + hyphens)
3. GitHub visibility (public / private)
4. Create the repo on GitHub? (yes / no)

### Full CLI mode

```bash
# Private infra project in the lowcodai org
./scripts/new-project.sh \
  --type infra \
  --name my-infra-aws \
  --visibility private \
  --org lowcodai \
  --verbose

# AI project in dry-run first
./scripts/new-project.sh --type ai --name my-agent --dry-run --verbose

# Create locally only (without GitHub)
./scripts/new-project.sh --type app --name my-app --no-github
```

## Adding files to an existing project

```bash
cd /path/to/my-project
cd ../vibecoding-bootstrap

./scripts/new-project.sh \
  --type base \
  --name my-project \
  --output-dir /path/to/my-project \
  --extend-only \
  --no-github
```

## Synchronizing governance

To update the instructions and hooks from `vibecoding-copilot-governance`:

```bash
./scripts/sync-governance.sh \
  --type base \
  --dest /path/to/my-project \
  [--autonomy supervised|branch|trusted|yolo]   # ADR-0008; omit to keep the repo's level
```

Kit-owned files (`.claude/settings.json`, `.claude/hooks/*.py`, `scripts/orchestrate.py`) are
refreshed; tuned files are kept. Commit the resulting diff through a PR.

> ⚠️ `--governance-dir` does not exist: the path to `vibecoding-copilot-governance` is
> resolved via a fixed relative path (`../vibecoding-copilot-governance` from `vibecoding-bootstrap`).
> Clone both repos side by side. Full procedure to align an existing repo:
> see [`docs/governance-alignment-runbook.md`](governance-alignment-runbook.md).

## Installing Awesome Copilot items

```bash
./scripts/install-awesome-copilot.sh \
  --type ai \
  --dest /path/to/my-project
```

## Environment variables

| Variable | Default | Description |
|----------|--------|-------------|
| `VIBECODING_GOVERNANCE_DIR` | `../vibecoding-copilot-governance` | Local path to governance |
| `VIBECODING_GITHUB_ORG` | (empty) | Default GitHub organization |
| `GITHUB_TOKEN` | (via gh auth) | Token for GitHub API operations |

## Troubleshooting

### "bash: bad option" or syntax errors

macOS uses bash 3.x by default. The scripts require bash ≥ 4:

```bash
brew install bash
# Then run the scripts with full bash:
/usr/local/bin/bash scripts/new-project.sh ...
```

### "gh: command not found"

Install GitHub CLI: https://cli.github.com/

Then authenticate: `gh auth login`

### Operation cancelled "target directory already exists"

Use `--extend-only` to only add missing files, or `--force` to overwrite (confirmation required).
