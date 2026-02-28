---
name: changelog
description: Update changelog files from staged git changes
argument-hint: "[version|help]"

# ==================================================================================
# SINGLE SOURCE - COMMAND CONFIG CATALOG (commented examples)
#
# Convention:
# - common.<field>     = shared fallback for all tools (when the field exists)
# - opencode.<field>   = OpenCode command override
# - claude.<field>     = Claude Code command/skill override
# - cursor.<field>     = Cursor command notes (metadata is limited)
# - vscode.<field>     = VS Code prompt file override
# - <tool>.extra.<k>   = free pass-through field
# ==================================================================================

# --- Common (dedupe)
# common.argument-hint: "[target]"
# common.model: inherit
# common.agent: agent
# common.tools: ['read','search']

# --- OpenCode command fields
# opencode.agent: build
# opencode.subtask: true
# opencode.model: openai/gpt-5.3-codex
# opencode.extra.temperature: 0.2
# opencode.extra.top_p: 0.9

# --- Claude command/skill fields
# claude.argument-hint: "[version|help]"
# claude.disable-model-invocation: true
# claude.user-invocable: true
# claude.allowed-tools: Read, Glob, Grep, Bash(git *), Write
# claude.model: sonnet
# claude.context: fork
# claude.agent: Explore
# claude.hooks: [{"event":"PreToolUse","command":"python scripts/audit.py"}]
# claude.extra.reasoningEffort: high
claude.disable-model-invocation: true

# --- Cursor command fields
# Cursor custom commands are markdown-only (no official frontmatter schema yet).
# cursor.extra.note: "no-op"

# --- VS Code prompt file fields
# vscode.argument-hint: "[version|help]"
# vscode.agent: agent
# vscode.model: ['GPT-5.2','Claude Sonnet 4.5']
# vscode.tools: ['search','read','editFiles','terminalLastCommand','githubRepo','my-mcp/*']
# vscode.extra.name: changelog
# vscode.extra.description: Update changelog files from staged git changes
vscode.agent: agent
---
Goal: update changelog file(s) from staged git changes only.

Modes:

- `/changelog help` or `--help`: return a short usage guide and stop (no file edits).
- `/changelog`: create or update `## [Unreleased]` only.
- `/changelog <version>`: create/update `## [<version>] - YYYY-MM-DD` from `[Unreleased]`.

Rules:

- Inspect staged changes only.
- Never run `git add`, commit, or push.
- Allowed git commands are read-only (`git status`, `git diff`, `git log`, `git show`).
- If `AGENTS.md` includes changelog directives, follow them.
- Keep a Changelog structure and do not rewrite historical releases unless explicitly requested.
- In monorepos, group entries by package, then by feature.
- User-facing entries must be clear for both beginners and experts.
- Keep entries concise, actionable, and deduplicated.
- Ignore documentation-only or ancillary resource changes (for example `docs/`, `README*`, guides, images, assets, notes).
- If nothing is staged, do not edit changelog files.

Type mapping:

- `feat`, `add`, `new` -> Added
- `fix` -> Fixed
- `refactor`, `perf` -> Changed
- `chore`, `build`, `ci`, `test` -> Changed only when user-impacting; otherwise ignore

Output:

- Clean diff on updated changelog file(s).
- 3-5 bullet recap of what changed and why.
