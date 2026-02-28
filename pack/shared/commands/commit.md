---
name: commit
description: Propose a commit message from staged git changes
argument-hint: "[short|normal|verbose|help]"

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
# claude.argument-hint: "[help]"
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
# vscode.argument-hint: "[help]"
# vscode.agent: agent
# vscode.model: ['GPT-5.2','Claude Sonnet 4.5']
# vscode.tools: ['search','read','editFiles','terminalLastCommand','githubRepo','my-mcp/*']
# vscode.extra.name: commit
# vscode.extra.description: Propose a commit message from staged git changes
vscode.agent: agent
---
Goal: propose a commit message from staged git changes.

Modes:

- `/commit help` or `--help`: return a short usage guide and stop.
- `/commit`: propose a `normal` commit message (default).
- `/commit short`: propose a `short` commit message.
- `/commit normal`: propose a `normal` commit message.
- `/commit verbose`: propose a `verbose` commit message.

Formats:

- `short`: one-line subject, max 72 chars, conventional commit format (`type: description`).
- `normal`: subject line + blank line + 1-3 sentence body explaining the why.
- `verbose`: subject line + blank line + bullet list covering all meaningful changes.

Rules:

- Inspect staged changes only (`git diff --cached`). If nothing is staged, say so and stop.
- Never run `git add`, commit, or push. Allowed git commands are read-only (`git status`, `git diff`, `git log`, `git show`).
- If `AGENTS.md` exists and contains commit message directives, follow them.
- Use conventional commit prefixes: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `perf`, `ci`, `build`.
- Do not invent information: only describe what the code actually does.
- Keep the message concise, accurate, and focused on the "why" over the "what".

Output:

- The commit message in the requested format (default: `normal`).
