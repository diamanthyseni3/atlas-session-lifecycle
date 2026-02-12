---
name: start
description: "Session initialization and lifecycle management: bootstraps session context, organizes files, generates CLAUDE.md, manages soul purpose lifecycle with completion protocol and active context harvesting. Use when user says /start, /init, bootstrap session, initialize session, or organize project."
user-invocable: true
---

# Session Init & Lifecycle Skill

> User runs `/start`. Questions upfront. Everything else silent. Then seamlessly continue working.

**Script**: `~/.claude/skills/start/session-init.py` handles all deterministic file operations.
All commands output JSON. AI only handles judgment calls (questions, assessment, continuation).

## Directive Capture

Capture any text after `/start` as `DIRECTIVE`. If empty, the soul purpose is the directive.
The skill NEVER finishes with "ready to go" and stops. After setup, immediately begin working.

## UX Contract (MANDATORY)

1. **NEVER announce step names** — no "Init Step 1", no "Wave 2"
2. **NEVER narrate internal process** — no "Detecting environment..."
3. **NEVER explain what you're about to do** — just ask questions, then do it silently
4. **User sees ONLY**: questions and seamless continuation into work
5. **Batch questions** — as few rounds as possible
6. **No "done" message that stops** — after setup, immediately begin working

## Hard Invariants

1. **User authority is absolute** — AI NEVER closes a soul purpose. Only suggests; user decides.
2. **Zero unsolicited behavior** — Skill ONLY runs when user types `/start`.
3. **Human-visible memory only** — All state lives in files.
4. **Idempotent** — Safe to run multiple times.
5. **Templates are immutable** — NEVER edit files in `~/claude-session-init-templates/`.
6. **NEVER** auto-invoke doubt agent. Only offer it.

---

# INIT MODE

> Triggered when preflight returns `"mode": "init"`.

## Step 1: Silent Pre-flight

```bash
python3 ~/.claude/skills/start/session-init.py preflight
```

Returns JSON with: `mode`, `is_git`, `has_claude_md`, `root_file_count`, `templates_valid`, `template_count`.
If `templates_valid` is false, STOP with error. Set internal flags from JSON. No output to user.

## Step 2: User Questions

### Round 1 — Ask upfront

Use AskUserQuestion with 2 questions:

**Question 1**: "What is the soul purpose of this project?"
- Options: "Build a product", "Fix & improve", "Research & learn" (user can type custom)

**Question 2**: "How should Ralph Loop work?"
- Options: "Automatic", "Manual", "Skip"

Store as `SOUL_PURPOSE` and `RALPH_MODE`.

### Round 2 — File organization (only if `root_file_count > 10`)

Use an Explore agent to scan root files and propose a move map. Present to user for approval.
If approved, use a Bash agent to execute `mkdir -p` + `git mv`/`mv` operations.
If skipped or root_file_count <= 10: no file moves.

## Step 3: Silent Execution

Run these commands sequentially. **ZERO output to user.**

```bash
# 1. Bootstrap session-context + seed active context
python3 ~/.claude/skills/start/session-init.py init \
  --soul-purpose "SOUL_PURPOSE_TEXT" \
  --ralph-mode "RALPH_MODE"

# 2. Ensure CLAUDE.md has all governance sections
python3 ~/.claude/skills/start/session-init.py ensure-governance \
  --ralph-mode "RALPH_MODE"

# 3. Cache governance before /init
python3 ~/.claude/skills/start/session-init.py cache-governance
```

Then run `/init` in main thread (Claude command to refresh CLAUDE.md).

```bash
# 4. Restore governance if /init removed sections
python3 ~/.claude/skills/start/session-init.py restore-governance
```

## Step 4: Continuation

Transition directly into work. No "session initialized" message.

- **If DIRECTIVE provided**: Begin working on directive immediately.
- **If RALPH_MODE = "automatic"**: Invoke `/ralph-wiggum:ralph-loop`.
- **Otherwise**: Begin working on soul purpose. If too vague, ask ONE clarifying question, write clarified purpose back via `archive --new-purpose`, then begin.

---

# RECONCILE MODE

> Triggered when preflight returns `"mode": "reconcile"`.

## Step 1: Silent Assessment

Run these commands sequentially. **NO output to user.**

```bash
# 1. Validate session files (repair from templates if needed)
python3 ~/.claude/skills/start/session-init.py validate

# 2. Cache governance before /init
python3 ~/.claude/skills/start/session-init.py cache-governance
```

Run `/init` in main thread.

```bash
# 3. Restore governance
python3 ~/.claude/skills/start/session-init.py restore-governance

# 4. Read soul purpose + active context
python3 ~/.claude/skills/start/session-init.py read-context
```

Returns JSON with: `soul_purpose`, `has_archived_purposes`, `active_context_summary`, `open_tasks`, `recent_progress`, `status_hint`.

## Step 2: Self-Assessment (pure reasoning, no tools)

Using the `read-context` JSON output, classify:

| Classification | Criteria |
|---------------|----------|
| `clearly_incomplete` | open_tasks non-empty, active blockers, criteria not met |
| `probably_complete` | No open tasks, artifacts exist, criteria met |
| `uncertain` | Mixed signals |

## Step 3: User Interaction (conditional)

### If `clearly_incomplete`:
No questions. Skip to continuation.

### If `probably_complete` or `uncertain`:
Ask ONE question combining assessment and decision:

"Soul purpose: '[purpose text]'. [1-2 sentence assessment]. What would you like to do?"
- Options: "Continue", "Verify first", "Close", "Redefine"

**If "Verify first"**: Dispatch doubt-agent, fold findings into re-presented question (without "Verify first" option).

**If "Close" or "Redefine"**: Run harvest + archive:

```bash
# Check for promotable content
python3 ~/.claude/skills/start/session-init.py harvest
```

If harvest returns content, AI assesses what to promote (judgment call — decisions need rationale, patterns must be reused, troubleshooting must have verified solutions). Present to user for approval. After approval, append promoted content to target files via Edit tool.

```bash
# Archive old purpose, optionally set new one
python3 ~/.claude/skills/start/session-init.py archive \
  --old-purpose "OLD_PURPOSE_TEXT" \
  --new-purpose "NEW_PURPOSE_TEXT"  # omit for close-without-redefine
```

**If "Close" without new purpose**: Ask if user wants to set a new soul purpose. If declined, the archive command writes "(No active soul purpose)".

## Step 4: Continuation

Transition directly into work. No "session reconciled" message.

- **If DIRECTIVE provided**: Begin working on directive.
- **If RALPH_MODE = "automatic"** (check CLAUDE.md): Invoke `/ralph-wiggum:ralph-loop`.
- **If soul purpose just redefined**: Begin working on new purpose.
- **If `clearly_incomplete`**: Pick up where last session left off using active context.
- **If no active soul purpose**: Ask user what to work on, write as new soul purpose via archive command.
- **Otherwise**: Resume work using active context as guide.

---

# Script Reference

All commands output JSON. Run from project root.

| Command | Purpose |
|---------|---------|
| `preflight` | Detect mode, git, CLAUDE.md, templates, session files |
| `init --soul-purpose "..." --ralph-mode "..."` | Bootstrap session-context, seed active context |
| `validate` | Check/repair session files from templates |
| `cache-governance` | Cache governance sections from CLAUDE.md to /tmp |
| `restore-governance` | Restore cached governance sections after /init |
| `ensure-governance --ralph-mode "..."` | Add missing governance sections to CLAUDE.md |
| `read-context` | Read soul purpose + active context summary |
| `harvest` | Scan active context for promotable content |
| `archive --old-purpose "..." [--new-purpose "..."]` | Archive soul purpose, reset active context |
