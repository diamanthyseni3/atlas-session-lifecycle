---
name: start
description: "Session initialization and lifecycle management: bootstraps session context, organizes files, generates CLAUDE.md, manages soul purpose lifecycle with completion protocol and active context harvesting. Use when user says /start, /init, bootstrap session, initialize session, or organize project."
user-invocable: true
---

# Session Init & Lifecycle Skill

> User runs `/start`. Questions upfront. Everything else silent. Then seamlessly continue working.

**Script path** (resolved at load time):

!`if [ -n "$CLAUDE_PLUGIN_ROOT" ] && [ -f "$CLAUDE_PLUGIN_ROOT/scripts/session-init.py" ]; then echo "$CLAUDE_PLUGIN_ROOT/scripts/session-init.py"; elif p=$(find ~/.claude/plugins -path '*/atlas-session-lifecycle/scripts/session-init.py' -type f 2>/dev/null | head -1) && [ -n "$p" ]; then echo "$p"; elif [ -f ~/.claude/skills/start/session-init.py ]; then echo "$HOME/.claude/skills/start/session-init.py"; else echo 'NOT_FOUND'; fi`

Use the resolved path above as `SESSION_SCRIPT` for all script invocations below.

**Plugin root** (resolved at load time):

!`if [ -n "$CLAUDE_PLUGIN_ROOT" ]; then echo "$CLAUDE_PLUGIN_ROOT"; elif p=$(find ~/.claude/plugins -path '*/atlas-session-lifecycle/scripts/session-init.py' -type f 2>/dev/null | head -1) && [ -n "$p" ]; then dirname "$(dirname "$p")"; elif [ -f ~/.claude/skills/start/session-init.py ]; then echo "$HOME/.claude/skills/start"; else echo 'NOT_FOUND'; fi`

Use the resolved path above as `PLUGIN_ROOT`.

**AtlasCoin URL** (resolved at load time):

!`if [ -n "$ATLASCOIN_URL" ]; then echo "$ATLASCOIN_URL"; else echo "http://localhost:3000"; fi`

Use the resolved URL above as `ATLASCOIN_URL`.

All commands output JSON. AI only handles judgment calls (questions, assessment, continuation).
All infrastructure work is delegated to Agent Team teammates.

## Directive Capture

Capture any text after `/start` as `DIRECTIVE`. If empty, the soul purpose is the directive.
The skill NEVER finishes with "ready to go" and stops. After setup, immediately begin working.

## UX Contract (MANDATORY)

1. **NEVER announce step names** — no "Init Step 1", no "Wave 2"
2. **NEVER narrate internal process** — no "Detecting environment...", no "Spawning session-ops..."
3. **NEVER explain what you're about to do** — just ask questions, then do it silently
4. **User sees ONLY**: questions and seamless continuation into work
5. **Batch questions** — as few rounds as possible
6. **No "done" message that stops** — after setup, immediately begin working
7. **Agent Teams are invisible** — user never sees team creation, task assignment, or teammate messages

## Hard Invariants

1. **User authority is absolute** — AI NEVER closes a soul purpose. Only suggests; user decides.
2. **Zero unsolicited behavior** — Skill ONLY runs when user types `/start`.
3. **Human-visible memory only** — All state lives in files.
4. **Idempotent** — Safe to run multiple times.
5. **Templates are immutable** — NEVER edit bundled template files.
6. **NEVER** auto-invoke doubt agent. Only offer it.
7. **Trust separation** — bounty-agent creates bounties, finality-agent verifies them. Never the same agent.
8. **AtlasCoin is optional** — if the service is down, tell the user and continue without bounty tracking.

## Agent Team Architecture

All infrastructure work is performed by specialized teammates, not by the main agent running python directly.

### Teammates

| Name | Prompt | Lifecycle | Purpose |
|------|--------|-----------|---------|
| `session-ops` | `PLUGIN_ROOT/prompts/session-ops.md` | Init through brainstorm completion | Execute all session-init.py subcommands |
| `bounty-agent` | `PLUGIN_ROOT/prompts/bounty-agent.md` | Spans entire session (dormant between setup and close) | AtlasCoin API interactions |
| `finality-agent` | `PLUGIN_ROOT/prompts/finality-agent.md` | Only at session close | Verify soul purpose completion |

### Spawning Pattern

When spawning teammates, read the corresponding prompt template from `PLUGIN_ROOT/prompts/`, replace template variables (`{SESSION_SCRIPT}`, `{PROJECT_DIR}`, `{ATLASCOIN_URL}`, `{BOUNTY_ID}`), and pass the result as the task prompt.

```
Task(
  name="<agent-name>",
  team_name="session-lifecycle",
  subagent_type="general-purpose",
  prompt=<resolved prompt template>
)
```

---

# INIT MODE

> Triggered when preflight returns `"mode": "init"`.

## Step 1: Team Setup + Preflight

Create the team and dispatch preflight:

1. `TeamCreate("session-lifecycle")`
2. `TaskCreate("Run preflight check")` → task-1
3. `TaskCreate("Bootstrap session context")` → task-2, blocked by task-1
4. `TaskCreate("Create AtlasCoin bounty")` → task-3, blocked by task-2

Spawn `session-ops` teammate with its prompt template. Assign task-1 to session-ops.

**In parallel** with session-ops running preflight, ask the user Ralph questions:

Use AskUserQuestion with 1-2 questions (Question 2 only if Ralph = Automatic):

**Question 1**: "How should Ralph Loop work?"
- Options: "Automatic", "Manual", "Skip"

**Question 2** (only if Ralph = Automatic): "What intensity?"
- Options: "Small (5 iterations)", "Medium (20 iterations)", "Long (100 iterations + PRD)"

Store as `RALPH_MODE`, `RALPH_INTENSITY` (default to "Small" if Automatic but no intensity given).

## Step 2: Determine Brainstorm Weight

Using `DIRECTIVE` and `project_signals` from session-ops preflight result, classify:

| Condition | Weight | Brainstorm Behavior |
|-----------|--------|---------------------|
| DIRECTIVE has 3+ words AND project has code/readme | **lightweight** | 1-2 quick clarifying questions, confirm direction, produce soul purpose |
| DIRECTIVE has 3+ words AND empty project | **standard** | Explore what to build, 3-5 questions, produce soul purpose + approach |
| No directive AND project has readme/code | **lightweight** | Present what you see in project_signals, ask 1-2 questions to focus the session |
| No directive AND empty project | **full** | Full brainstorm — purpose, constraints, approach, design |

Store `BRAINSTORM_WEIGHT` and `BRAINSTORM_CONTEXT` for use in Step 4.

### File organization (only if `root_file_count > 15`)

Message session-ops to run `check-clutter`.

If result `status` is "cluttered", present the grouped move map to the user for approval:

"Your project root has [N] misplaced files. Proposed cleanup: [M] docs → docs/archive/, [P] screenshots → docs/screenshots/, [Q] scripts → scripts/, [R] to delete. Approve cleanup?"
- Options: "Yes, clean up", "Show details first", "Skip"

**If "Show details first"**: Display the full `moves_by_dir` grouped listing, then re-ask.
**If "Yes, clean up"**: Message session-ops to execute the moves (using `git mv` if `is_git`).
**If "Skip"**: Continue.

## Step 3: Silent Bootstrap

Message session-ops to run the bootstrap sequence with the user's Ralph answers:

1. `init --soul-purpose "DIRECTIVE_OR_PENDING" --ralph-mode "RALPH_MODE" --ralph-intensity "RALPH_INTENSITY"`
2. `ensure-governance --ralph-mode "RALPH_MODE" --ralph-intensity "RALPH_INTENSITY"`
3. `cache-governance`

Wait for session-ops to complete and report success.

Then run `/init` in main thread (Claude Code built-in that refreshes CLAUDE.md — must be main thread).

Then message session-ops to run `restore-governance`.

**Then read the plugin's `custom.md`** if it exists (at `PLUGIN_ROOT/custom.md`), and follow any instructions under "During Init".

## Step 4: Brainstorm + AtlasCoin Bounty + Continuation

Transition directly into work. No "session initialized" message.

**Brainstorm runs first (always)**:

Invoke brainstorming with the weight and context determined in Step 2:

- **lightweight**: Invoke `skill: "superpowers:brainstorming"` with args containing the `BRAINSTORM_CONTEXT` + instruction: "This is a lightweight brainstorm. Confirm direction with 1-2 questions, derive a soul purpose statement, then transition to work. Do NOT write a design doc for lightweight brainstorms."
- **standard**: Invoke `skill: "superpowers:brainstorming"` with args containing the `BRAINSTORM_CONTEXT`. Follow normal brainstorm flow but skip design doc if the task is clear enough.
- **full**: Invoke `skill: "superpowers:brainstorming"` with full `BRAINSTORM_CONTEXT` args. Follow complete brainstorm flow including design doc.

After brainstorm completes, write the derived soul purpose:

1. Message session-ops to run: `archive --old-purpose "DIRECTIVE_OR_PENDING" --new-purpose "DERIVED_SOUL_PURPOSE"`

2. **Spawn bounty-agent** with its prompt template. Message bounty-agent to:
   - Check AtlasCoin health
   - If healthy: create bounty with escrow based on Ralph intensity (see Escrow Scaling below)
   - Write `BOUNTY_ID.txt` to `session-context/`

3. **If AtlasCoin is down**: bounty-agent reports failure. Main agent tells user: "AtlasCoin is not available at {URL}. Start the service or check the connection. Continuing without bounty tracking."

4. **Shutdown session-ops**: `SendMessage(type="shutdown_request", recipient="session-ops")`

5. **bounty-agent stays alive** (dormant) — needed at session close for settlement.

### Escrow Scaling

| Ralph Intensity | Escrow | Stake (10%) |
|----------------|--------|-------------|
| skip           | 50     | 5           |
| small          | 100    | 10          |
| medium         | 200    | 20          |
| long           | 500    | 50          |

### Ralph Loop Invocation

When `RALPH_MODE = "automatic"`, you MUST use the `Skill` tool to actually start the Ralph Loop.
Construct the invocation based on `RALPH_INTENSITY`:

| Intensity | Skill tool call |
|-----------|----------------|
| **Small** | `skill: "ralph-wiggum:ralph-loop"`, `args: "SOUL_PURPOSE --max-iterations 5 --completion-promise 'Soul purpose fulfilled'"` |
| **Medium** | `skill: "ralph-wiggum:ralph-loop"`, `args: "SOUL_PURPOSE --max-iterations 20 --completion-promise 'Soul purpose fulfilled and code tested'"` |
| **Long** | First invoke `skill: "prd-taskmaster"`, `args: "SOUL_PURPOSE"`. Wait for PRD completion. THEN invoke `skill: "ralph-wiggum:ralph-loop"`, `args: "SOUL_PURPOSE --max-iterations 100 --completion-promise 'Must validate sequentially with 3x doubt agents and 1x finality agent'"` |

Replace `SOUL_PURPOSE` with the derived soul purpose text. Quote the full prompt if it contains spaces.

**CRITICAL**: You must call the `Skill` tool — not just mention it in text. The Ralph Loop only activates when `setup-ralph-loop.sh` runs via the Skill tool invocation.

---

# RECONCILE MODE

> Triggered when preflight returns `"mode": "reconcile"`.

**CRITICAL UX REMINDER**: Everything in Steps 1-2 is invisible to the user. Do NOT output "Running reconcile mode", "Assessing context", "Reading soul purpose", "Creating team", or ANY description of what you are doing. The user's first visible interaction is either a question (Step 3) or seamless continuation into work (Step 4). Nothing before that.

## Step 1: Team Setup + Silent Assessment

1. `TeamCreate("session-lifecycle")`
2. `TaskCreate("Validate and read context")` → task-1
3. `TaskCreate("Check root clutter")` → task-2, blocked by task-1
4. `TaskCreate("Check bounty status")` → task-3 (independent)

Spawn session-ops and bounty-agent **in parallel**:

- **session-ops**: Assign task-1. Runs: `validate` → `cache-governance` → reports ready.
- **bounty-agent**: Assign task-3. Reads `session-context/BOUNTY_ID.txt`, checks bounty status via `GET /api/bounties/:id`. If no BOUNTY_ID.txt exists, reports "No existing bounty".

Wait for session-ops to report validation complete.

Run `/init` in main thread.

Message session-ops to run: `restore-governance` → `read-context`.

Receive `read-context` JSON and bounty status from their respective agents.

**Then read the plugin's `custom.md`** if it exists (at `PLUGIN_ROOT/custom.md`), and follow any instructions under "During Reconcile".

### Root Cleanup Check

Use `root_file_count` from preflight (already available from session-ops).

**If `root_file_count > 15`**: Message session-ops to run `check-clutter`.

If result `status` is "cluttered", present the move map to the user as part of Step 3 questions:

"Your project root has [N] misplaced files. Proposed cleanup: [M] docs → docs/archive/, [P] screenshots → docs/screenshots/, [Q] scripts → scripts/, [R] to delete. Approve cleanup?"
- Options: "Yes, clean up", "Show details first", "Skip"

**If "Show details first"**: Display the full `moves_by_dir` grouped listing, then re-ask.
**If "Yes, clean up"**: Message session-ops to execute the moves.
**If "Skip"**: Continue.

## Step 2: Directive Check + Self-Assessment

**If DIRECTIVE is non-empty (3+ words) AND `status_hint` is `no_purpose`**:
- Message session-ops to set soul purpose to DIRECTIVE via archive command
- Skip Step 3, go to Step 4 with a lightweight brainstorm to confirm direction

**If DIRECTIVE is non-empty (3+ words) AND soul purpose exists**:
- Skip Step 3, go to Step 4 — work on directive (it overrides for this session)

**Otherwise** (no directive): Proceed with self-assessment below.

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
Ask ONE question combining assessment, bounty status, and decision:

"Soul purpose: '[purpose text]'. [1-2 sentence assessment]. [Bounty: active/none]. What would you like to do?"
- Options: "Continue", "Verify first", "Close", "Redefine"

**If "Verify first"**: Dispatch doubt-agent, fold findings into re-presented question (without "Verify first" option).

**If "Close" or "Redefine"**: Run the Settlement Flow (see below).

## Step 4: Continuation

Transition directly into work. No "session reconciled" message.

- **If DIRECTIVE provided**: Begin working on directive.
- **If `ralph_mode` = "automatic"** (from `read-context` JSON): Check if Ralph Loop should start — see "Ralph Loop Invocation (Reconcile)" below.
- **If soul purpose just redefined**: Begin working on new purpose.
- **If `clearly_incomplete`**: Pick up where last session left off using active context.
- **If no active soul purpose**: Ask user what to work on, write as new soul purpose via archive command (through session-ops).
- **Otherwise**: Resume work using active context as guide.

Before continuing, shutdown session-ops (no longer needed for active work). Keep bounty-agent dormant for potential session close later.

### Ralph Loop Invocation (Reconcile)

When `ralph_mode` from `read-context` is "automatic", first check if Ralph Loop is already active:

```bash
test -f ~/.claude/ralph-loop.local.md && echo "active" || echo "inactive"
```

- **If active**: Skip invocation. Ralph Loop is already running or was already set up this session.
- **If inactive**: Use the `Skill` tool to start Ralph Loop. Read `ralph_intensity` from the `read-context` JSON and use the same intensity table as Init mode.

**CRITICAL**: You must call the `Skill` tool — not just mention it in text.

---

# SETTLEMENT FLOW

> Triggered when user chooses "Close" in Reconcile Step 3.

**Read the plugin's `custom.md`** if it exists, and follow any instructions under "During Settlement".

## Step 1: Harvest + Archive

Message session-ops (re-spawn if already shut down) to run:

1. `harvest` — check for promotable content
2. If harvest returns content, AI assesses what to promote (judgment call — decisions need rationale, patterns must be reused, troubleshooting must have verified solutions). Present to user for approval. After approval, append promoted content to target files via Edit tool.
3. `archive --old-purpose "OLD_PURPOSE_TEXT" --new-purpose "NEW_PURPOSE_TEXT"` (omit `--new-purpose` for close-without-redefine)

**If "Close" without new purpose**: Ask if user wants to set a new soul purpose. If declined, the archive command writes "(No active soul purpose)".

## Step 2: Bounty Submission + Verification

**If bounty exists** (BOUNTY_ID.txt present and bounty-agent confirmed active bounty):

1. Message bounty-agent to submit solution:
   ```
   POST /api/bounties/:id/submit
   Body: { claimant: "session-agent", stakeAmount: <STAKE>, evidence: { soul_purpose, commits_summary } }
   ```

2. Spawn finality-agent with its prompt template (replacing `{BOUNTY_ID}` with the actual ID):
   ```
   Task(name="finality-agent", team_name="session-lifecycle", subagent_type="general-purpose", prompt=<resolved finality prompt>)
   ```

3. Finality-agent collects evidence:
   - Reads soul purpose + active context via `read-context`
   - `git log --oneline -20`
   - Checks open tasks in active context
   - Checks session-context files have real content
   - If soul purpose mentions tests → checks for test results

4. Finality-agent calls `POST /api/bounties/:id/verify` with evidence

5. **If verified (passed)**:
   - Message bounty-agent to call `POST /api/bounties/:id/settle`
   - Tokens distributed — tell user: "Soul purpose verified and settled. [X] AtlasCoin tokens earned."

6. **If verification failed**:
   - Present failure to user with options: "Fix and re-verify" / "Close anyway (forfeit bounty)" / "Continue working"
   - **Fix and re-verify**: Return to active work, re-run settlement when ready
   - **Close anyway**: Bounty forfeited, session closes
   - **Continue working**: Return to Step 4 of Reconcile

**If no bounty exists**: Skip settlement, just archive and close.

## Step 3: Cleanup

After settlement (or close-without-bounty):

1. `SendMessage(type="shutdown_request")` to all remaining teammates (session-ops, bounty-agent, finality-agent)
2. Wait for shutdown confirmations
3. `TeamDelete("session-lifecycle")`

---

# Script Reference

All commands output JSON. Run from project root via session-ops teammate (never by main agent directly).

| Command | Purpose |
|---------|---------|
| `preflight` | Detect mode, git, CLAUDE.md, templates, session files |
| `init --soul-purpose "..." --ralph-mode "..." --ralph-intensity "..."` | Bootstrap session-context, seed active context |
| `validate` | Check/repair session files from templates |
| `cache-governance` | Cache governance sections from CLAUDE.md to /tmp |
| `restore-governance` | Restore cached governance sections after /init |
| `ensure-governance --ralph-mode "..." --ralph-intensity "..."` | Add missing governance sections to CLAUDE.md |
| `read-context` | Read soul purpose + active context summary |
| `harvest` | Scan active context for promotable content |
| `archive --old-purpose "..." [--new-purpose "..."]` | Archive soul purpose, reset active context |
| `check-clutter` | Scan root for misplaced files, return categorized move map |

---

# Work Execution: Agent Teams Enforcement

> The session-lifecycle team above handles session bootstrapping. This section governs how **actual work** (implementation, PRD tasks, Ralph Loop iterations) is executed.

## Rule: When 2+ Independent Tasks Exist, MUST Use Agent Teams

| Condition | Action |
|-----------|--------|
| Soul purpose requires 2+ independent implementation tasks | **MUST** create work team via `TeamCreate` |
| PRD/TaskMaster generates parallelizable task list | **MUST** create work team |
| Ralph Loop with Long intensity (100+ iterations) | **MUST** create work team |
| Single sequential task | Regular execution (no team needed) |

## Work Team Pattern

After brainstorm/PRD determines the work requires parallel execution, create a **separate** work team (distinct from session-lifecycle):

```
1. TeamCreate(team_name: "{project-slug}-work", description: "Soul purpose execution")
2. Create tasks via TaskCreate with dependencies (addBlockedBy)
3. Spawn teammates via Task tool with team_name parameter:
   - Each teammate gets clear file ownership boundaries (directory-level)
   - Each teammate gets explicit working directory
   - Use subagent_type: "general-purpose" for implementation
4. Teammates self-claim tasks from shared TaskList
5. Lead coordinates via SendMessage — lead does NOT implement when team is active
6. At checkpoints: lead reviews, runs verification, gates next wave
7. On completion: SendMessage type: "shutdown_request" to all work teammates
8. TeamDelete("{project-slug}-work")
```

## File Ownership (Prevent Merge Conflicts)

When spawning work teammates, assign directory-level ownership:

```
Teammate A: owns client/src/pages/, client/src/components/
Teammate B: owns server/services/, server/routes/
Teammate C: owns server/__tests__/, tests/
```

No two teammates edit the same file. If overlap is unavoidable, make tasks sequential (addBlockedBy).

## Anti-Patterns (NEVER)

- **Ad-hoc background Task agents** without TeamCreate — breaks coordination
- **Lead implementing** when work team is active — lead is coordinator only
- **Spawning without file boundaries** — causes merge conflicts
- **Forgetting shutdown** — always shut down work team after wave/phase completes

## Ralph Loop + Work Team Integration

When Ralph Loop is automatic AND work team is active:
- Ralph Loop runs as the lead's iteration cycle
- Each Ralph iteration can spawn a wave of work teammates
- Doubt agents run between waves as verification gates
- Work team persists across Ralph iterations; shutdown only at soul purpose completion

---

# Customizations

> To customize `/start` behavior, create or edit `custom.md` in the plugin root directory.

The AI reads `custom.md` at each lifecycle phase and follows matching instructions:
- **During Init**: After session-context is bootstrapped (Step 3)
- **During Reconcile**: After read-context, before assessment (Step 1-2)
- **During Settlement**: Before harvest + archive (Settlement Step 1)
- **Always**: Applied in all modes

To customize, just write what you want in English under the relevant heading. No code needed.
