# Runbook — Aligning an existing repo on vibecoding governance + the Hermes contract

**Scope:** any `lowcodai/*` repo you want to bring in line with the
`vibecoding-copilot-governance` structure (Copilot instructions/hooks/agents) and the Hermes
continuity contract (`.hermes.md` + `docs/operations/{CURRENT,HANDOFF,ACTIVITY}.md`).
**Audience:** Arcane (execution) + Capitaine (review/validation).
**Origin:** actually applied on 2026-09-14 to 6 repos (governance, bootstrap, 4
templates, dgx-spark-V2, llmwiki) + HermesVPS2 itself. See `HermesVPS2/BACKLOG.md`
ticket `#6` and `CHANGELOG.md` (2026-09-14) for the history of reference commits.

---

## Step 0 — Folder layout prerequisites

`sync-governance.sh` resolves `vibecoding-copilot-governance` via a **fixed relative path**
(`${BOOTSTRAP_DIR}/../vibecoding-copilot-governance`) — **known pitfall:** `docs/usage.md`
documents a `--governance-dir` flag, but it does not exist in the actual script (verified
2026-09-14 via grep on `scripts/sync-governance.sh`). Do not rely on it until the doc
is fixed or the flag is added. So clone both repos **side by side**:

```bash
mkdir -p /opt/data/workspace/vibecoding-align && cd /opt/data/workspace/vibecoding-align
gh repo clone lowcodai/vibecoding-copilot-governance
gh repo clone lowcodai/vibecoding-bootstrap
gh repo clone lowcodai/<repo-to-align>
```

---

## Step 1 — Identify the closest template type

`base | infra | ai | app | m365` — choose the one that matches the target repo (it doesn't matter
whether it was originally created with `new-project.sh`: `--extend-only` only adds what is
missing, and never overwrites).

---

## Step 2 — Mandatory dry-run before any write

```bash
cd vibecoding-bootstrap
DRY_RUN=true ./scripts/sync-governance.sh \
  --type <base|infra|ai|app|m365> \
  --dest ../<repo-to-align> \
  --extend-only --verbose
```

Read the output: it must list what **would** be created (`instructions/`, `hooks/`,
`agents/`, `.hermes.md`, `docs/operations/{CURRENT,HANDOFF,ACTIVITY}.md`, `templates/`)
without writing anything. If the target repo's `docs/operations/*.md` files already exist
and are dated/in use, verify that they show up as `[SKIP]` and not `[CREATE]`.

---

## Step 2bis — Verify the PRD/ADR methodology in the dry-run

In the Step 2 output, confirm the presence of these lines (new since `sync_methodology()`
was added):

```text
[CREATE] docs/prd/README.md        (or [SKIP] if the target repo already has one)
[CREATE] docs/adr/README.md        (or [SKIP] — e.g. itshaker-dgx-spark-V2 already has a real one)
[CREATE] docs/methodology/PRD-ADR-PLAN-RUNBOOK-WORKFLOW.md
[CREATE] .github/agents/prd-generator.agent.md
```

If a target repo already has a real, dated `docs/adr/README.md` (e.g. `itshaker-dgx-spark-V2`),
it **must** show up as `[SKIP]`, never as `[CREATE]` — otherwise `--extend-only` has regressed.

---

## Step 3 — Actual execution

```bash
./scripts/sync-governance.sh \
  --type <base|infra|ai|app|m365> \
  --dest ../<repo-to-align> \
  --extend-only
```

`--extend-only` is the tested guarantee of idempotence (verified on 2026-09-14: manually
modifying `CURRENT.md` + re-running → file preserved, `[SKIP]` logged). Never run without
`--extend-only` on a repo that already has real content in `docs/operations/`.

---

## Step 4 — Verify the result before committing

```bash
cd ../<repo-to-align>
git status --short          # must show ONLY new files (A/??), no M
                             # on an already-dated/in-use docs/operations/*.md file
ls docs/operations/          # CURRENT.md HANDOFF.md ACTIVITY.md must be present
grep -n "^| \`" .hermes.md   # the model → context-threshold table must appear
                             # (Qwen3.8-27B-NVFP4 / Sonnet 5 / GPT-5.6 Sol)
```

If an existing dated `docs/operations/*.md` file shows up as `M` (modified) rather than
`clean`/`??`: **stop, do not commit**, investigate — this is a sign that `--extend-only`
was not respected or that a regression bug has reappeared.

---

## Step 5 — Commit + push, then a real remote verification

```bash
git add .hermes.md docs/operations/ instructions/ hooks/ agents/ 2>/dev/null
git commit -m "feat(hermes): Hermes continuity contract + Copilot governance (aligned with vibecoding-copilot-governance)"
git push origin main
```

**Never declare "committed and pushed" without checking the remote SHA** (lesson from
2026-09-14, following a question from Capitaine on this exact point):

```bash
local_head=$(git rev-parse --short HEAD)
git fetch origin main -q
remote_head=$(git rev-parse --short origin/main)
[ "$local_head" = "$remote_head" ] && echo "OK: $local_head" || echo "MISMATCH local=$local_head remote=$remote_head"
git status --short   # must be empty (working tree clean)
```

---

## Step 6 — Document in HermesVPS2

Add a `CHANGELOG.md` entry (format `[YYYY-MM-DD] feat — ...`) referencing the SHA of the
commit produced in Step 5, and update the corresponding `BACKLOG.md` ticket (or open a new
one if this repo falls outside the initial batch of ticket `#6`).

---

## Closing checklist

- [ ] Dry-run executed and read before the actual run
- [ ] `--extend-only` used (never a bare run on a repo with existing content)
- [ ] `git status --short` clean after sync — no dated file overwritten
- [ ] Model → context-threshold table present in `.hermes.md`
- [ ] Commit + push done
- [ ] Local SHA == `origin/main` SHA verified via `git fetch` (not assumed)
- [ ] `HermesVPS2/CHANGELOG.md` and `BACKLOG.md` updated with the actual SHA

## Known pitfalls

- `docs/usage.md` documents `--governance-dir`: it **does not exist** in
  `sync-governance.sh` as of 2026-09-14. Fixed relative path only. Flagged, not fixed
  (out of scope for this alignment) — to be fixed someday, either by implementing the flag
  or by removing the mention from the docs.
- Never run `sync-governance.sh` without `--extend-only` on a repo that already contains
  active notes in `docs/operations/` — without this flag, the default behavior has not
  been validated for preserving existing content.
- The model → context-threshold table (`.hermes.md`) should be revised if providers
  silently change their context windows, or if Capitaine changes their 3 reference
  models (Qwen3.8-27B-NVFP4 default / Sonnet 5 / GPT-5.6 Sol for heavy reasoning).
