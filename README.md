# Claude Session Init -- `/start` Skill for Claude Code

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub stars](https://img.shields.io/github/stars/anombyte93/claude-session-init)](https://github.com/anombyte93/claude-session-init/stargazers)
[![Last Commit](https://img.shields.io/github/last-commit/anombyte93/claude-session-init)](https://github.com/anombyte93/claude-session-init/commits/main)
[![GitHub Issues](https://img.shields.io/github/issues/anombyte93/claude-session-init)](https://github.com/anombyte93/claude-session-init/issues)

Persistent project memory and lifecycle management for Claude Code. Run `/start` in any directory to bootstrap structured session context, organize files, and manage soul purpose lifecycle across sessions.

> **Featured in**: [I just delivered on a $30,000 contract thanks to Claude Code](https://www.reddit.com/r/ClaudeAI/comments/1r0n1qz/i_just_delivered_on_a_30000_contract_thanks_to/) (r/ClaudeAI)

---

## What This Solves

Claude Code has no persistent memory between sessions. Every time you start a new conversation, Claude starts from zero. This creates three problems:

1. **No persistent memory** -- You re-explain context, decisions, and progress every session. Claude forgets what you were working on, why you made architectural choices, and what problems you already solved.

2. **Project sprawl** -- Files accumulate at the project root with no organization. Scripts, docs, configs, and logs pile up. New sessions dump more files. The codebase becomes harder to navigate for both you and Claude.

3. **No lifecycle management** -- Projects have goals, but there is no mechanism to track progress toward those goals, verify completion, or transition to new objectives. You manually manage "what is done" and "what is next" in your head.

`/start` solves all three by creating a structured `session-context/` directory with five memory files, auto-organizing project files into clean directory structures, and providing a soul purpose lifecycle with completion verification and context harvesting.

---

## What's New in v2 -- Codification

v2 is a major architectural change: the skill is now split into a **slim orchestrator** (SKILL.md) and a **deterministic script** (session-init.py).

### Why Codify?

v1 was a single 867-line SKILL.md that instructed Claude to perform all operations -- file creation, validation, governance caching, context reading -- via natural language instructions interpreted at runtime. This worked, but:

- **Non-deterministic**: Claude sometimes interpreted instructions differently across sessions
- **Context-hungry**: 867 lines of instructions consumed a large portion of the context window
- **Fragile**: File operations described in prose are harder to test and debug than actual code

v2 extracts all deterministic operations into `session-init.py` (548 lines, 9 subcommands). The SKILL.md drops to 203 lines and only handles what AI is actually good at: asking questions, making judgment calls, and deciding what to do next.

### v2 Architecture

```
~/.claude/skills/start/
  SKILL.md          # 203 lines -- AI orchestrator (questions, judgment, continuation)
  session-init.py   # 548 lines -- deterministic ops (9 JSON-outputting subcommands)
```

**SKILL.md** tells Claude *when* to call the script and *what to do* with the results.
**session-init.py** handles *how* -- file operations, validation, governance caching, context parsing.

### session-init.py Subcommands

All commands output JSON. Run from project root.

| Command | Purpose |
|---------|---------|
| `preflight` | Detect mode (init/reconcile), git, CLAUDE.md, templates, session files |
| `init --soul-purpose "..." --ralph-mode "..."` | Bootstrap session-context, seed active context |
| `validate` | Check/repair session files from templates |
| `cache-governance` | Cache governance sections from CLAUDE.md to /tmp |
| `restore-governance` | Restore cached governance sections after `/init` |
| `ensure-governance --ralph-mode "..."` | Add missing governance sections to CLAUDE.md |
| `read-context` | Read soul purpose + active context summary |
| `harvest` | Scan active context for promotable content |
| `archive --old-purpose "..." [--new-purpose "..."]` | Archive soul purpose, reset active context |

### What Stayed the Same

- Templates directory is unchanged and immutable
- Session context file structure (5 files) is identical
- User experience is identical -- you still just run `/start`
- Both init mode and reconcile mode work the same way from the user's perspective

---

## How It Works

`/start` has two modes, auto-detected from directory state:

### Init Mode (first run)

Triggered when `session-context/` does not exist.

1. Captures your project's soul purpose
2. Detects environment (git, existing files, structure)
3. Bootstraps `session-context/` with 5 memory bank files from templates
4. Scans root-level files and proposes an organization map (scripts, docs, config, logs)
5. Generates or updates `CLAUDE.md` with project structure and governance sections
6. Runs Claude's built-in `/init` to enrich `CLAUDE.md` with codebase analysis
7. Onboards Ralph Loop (automatic, manual, or skip)
8. Seeds active context so the first Reconcile run finds meaningful state

### Reconcile Mode (returning)

Triggered when `session-context/` already exists.

1. Runs Claude's `/init` to refresh `CLAUDE.md` from current codebase state
2. Restores governance sections if `/init` overwrote them
3. Reads soul purpose and active context
4. Self-assesses soul purpose status (clearly incomplete, probably complete, uncertain)
5. Optionally runs doubt agent verification (user chooses)
6. Offers lifecycle decision: close, continue, or redefine soul purpose
7. Harvests durable knowledge from active context on closure (promotes decisions, patterns, troubleshooting entries)
8. Checks Ralph Loop preference and acts accordingly

---

## Target User

AI-first developers, solopreneurs, and consultants who use Claude Code as their primary development tool and want structured project memory that persists across sessions. If you find yourself re-explaining context to Claude every session, or your project roots are a mess of unsorted files, this skill is for you.

---

## Use Cases

1. **New project bootstrap** -- `/start` on a fresh directory captures your soul purpose, organizes existing files into a clean structure, and generates `CLAUDE.md` with project-specific instructions.

2. **Session continuity** -- `/start` on returning to a project reconciles state, checks soul purpose progress, and loads all context so Claude picks up where it left off.

3. **Project lifecycle** -- Close completed soul purposes, harvest durable knowledge (decisions, patterns, troubleshooting) into permanent files, and redefine new objectives.

4. **Multi-project management** -- Each project gets its own `session-context/` with a consistent five-file structure. Switch between projects and Claude immediately has the right context.

---

## User Stories

- *"As a solo developer, I want Claude to remember what I was working on across sessions so I don't waste time re-explaining context."*

- *"As a consultant managing multiple client projects, I want each project to have a consistent memory structure so Claude can pick up where it left off."*

- *"As someone who accumulates files at the project root, I want an automated organizer that categorizes scripts, docs, and configs into a clean structure."*

- *"As a power user of Claude Code, I want lifecycle management for my project goals so I can track completion, verify with doubt agents, and transition to new objectives."*

---

## Installation

```bash
git clone https://github.com/anombyte93/claude-session-init.git
cd claude-session-init
./install.sh
```

This installs (v2 by default):
- The skill to `~/.claude/skills/start/SKILL.md`
- The script to `~/.claude/skills/start/session-init.py`
- Templates to `~/claude-session-init-templates/`

### Version Toggle

```bash
# Install v2 (default) -- slim SKILL.md + session-init.py
./install.sh

# Install v1 -- monolithic SKILL.md (867 lines, no script)
./install.sh --version v1

# Revert from v2 back to v1 (backs up v2 files first)
./install.sh --revert
```

### Manual Install

```bash
# Create the skill directory (Claude Code requires <name>/SKILL.md structure)
mkdir -p ~/.claude/skills/start

# Copy v2 skill files
cp SKILL.md ~/.claude/skills/start/SKILL.md
cp session-init.py ~/.claude/skills/start/session-init.py
chmod +x ~/.claude/skills/start/session-init.py

# Copy templates
mkdir -p ~/claude-session-init-templates
cp templates/* ~/claude-session-init-templates/
```

---

## File Structure

```
claude-session-init/
  SKILL.md                  # v2 skill file (203 lines, AI orchestrator)
  session-init.py           # v2 script (548 lines, 9 subcommands)
  start.md                  # Legacy alias for SKILL.md
  SKILL.md.pre-codify       # v1 SKILL.md preserved for reference
  install.sh                # Installer with version toggle
  v1/
    SKILL.md                # v1 monolithic skill (867 lines)
  templates/
    CLAUDE-activeContext.md
    CLAUDE-decisions.md
    CLAUDE-mdReference.md
    CLAUDE-patterns.md
    CLAUDE-soul-purpose.md
    CLAUDE-troubleshooting.md
  README.md
  LICENSE
  CODE_OF_CONDUCT.md
  CONTRIBUTING.md
  .github/
    FUNDING.yml
```

---

## Quick Start

In any project directory with Claude Code:

```
/start
```

That is all. The skill auto-detects whether to initialize or reconcile.

---

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- Python 3.6+ (for session-init.py)
- Templates at `~/claude-session-init-templates/` (installed by `install.sh`)
- Git (optional, but recommended -- enables `git mv` for tracked files)

---

## License

MIT
