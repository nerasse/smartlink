---
name: documentation
description: Update repo documentation from staged git changes
argument-hint: "[help]"

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
# vscode.extra.name: documentation
# vscode.extra.description: Update repo documentation from staged git changes
vscode.agent: agent
---
Goal: update the repository's documentation files so they accurately reflect staged git changes. Be concise but complete.

Modes:

- `/documentation help` or `--help`: return a short usage guide and stop (no file edits).
- `/documentation`: analyse staged changes and update all relevant doc files.

Rules:

- Inspect staged changes only (`git diff --cached`). If nothing is staged, stop and say so — do not edit any file.
- Never run `git add`, commit, or push. Allowed git commands are read-only (`git status`, `git diff`, `git log`, `git show`).
- If `AGENTS.md` exists and contains documentation directives, follow them strictly.
- Documentation files to consider: `README.md`, `CONTRIBUTING.md`, `ARCHITECTURE.md`, inline doc headers, usage examples, CLI help text, and any file under `docs/`.
- Only update sections affected by the staged changes. Do not rewrite unrelated sections.
- Keep language concise, precise, and accessible to both beginners and experts.
- Preserve the existing tone and structure of each doc file.
- In monorepos, scope updates to the packages touched by the staged changes.
- If a new feature or command is staged but not yet documented, add the missing section.
- If a feature or command is removed in staged changes, remove or mark its documentation accordingly.
- Do not invent information: only document what the code actually does.

Output:

- Clean diff on every documentation file updated.
- 3-5 bullet recap of what was updated and why.
