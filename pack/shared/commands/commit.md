---
name: commit
description: Run docs, changelog, and commit from staged git changes
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
# claude.argument-hint: "[short|normal|verbose|help]"
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
# vscode.argument-hint: "[short|normal|verbose|help]"
# vscode.agent: agent
# vscode.model: ['GPT-5.2','Claude Sonnet 4.5']
# vscode.tools: ['search','read','editFiles','terminalLastCommand','githubRepo','my-mcp/*']
# vscode.extra.name: commit
# vscode.extra.description: Run docs, changelog, and commit from staged git changes
vscode.agent: agent
---
Goal: run a commit flow from staged git changes: update documentation, update changelog in unreleased mode, and create one commit using the requested message format.

Modes:

- `/commit help` or `--help`: return a short usage guide and stop.
- `/commit`: run the full flow and create a `normal` commit message (default).
- `/commit short`: run the full flow and create a `short` commit message.
- `/commit normal`: run the full flow and create a `normal` commit message.
- `/commit verbose`: run the full flow and create a `verbose` commit message.

Formats:

- `short`: one-line subject, max 72 chars, conventional commit format (`type: description`).
- `normal`: subject line + blank line + 1-3 sentence body explaining the why.
- `verbose`: subject line + blank line + bullet list covering all meaningful changes.

Rules:

- Start from staged changes as source of truth (`git diff --cached`). If nothing is staged, say so and stop before any write operation.
- Treat this prompt as self-contained: do not rely on hidden/system prompts for documentation, changelog, or commit conventions.
- If `AGENTS.md` exists and contains commit/changelog/documentation directives, follow them with priority.
- Run documentation updates first on files affected by staged changes: `README.md`, `CONTRIBUTING.md`, `ARCHITECTURE.md`, inline doc headers, usage examples, CLI help text, and any file under `docs/`.
- For documentation edits, update only sections impacted by staged changes, preserve each file's existing tone/structure, add missing docs for staged new behavior, remove or mark removed behavior, and keep wording concise and accessible.
- In monorepos, scope documentation updates to touched packages only.
- Then run changelog update in unreleased mode on any `CHANGELOG.md` file(s).
- Keep a Keep a Changelog structure, do not rewrite historical releases, and only create or update `## [Unreleased]` (never create a versioned release section in `/commit`).
- In changelog entries, group by package (monorepos) then feature, ignore documentation-only or ancillary resource changes, and keep entries concise, actionable, deduplicated, and clear for beginners and experts.
- Use changelog type mapping: `feat`/`add`/`new` -> Added; `fix` -> Fixed; `refactor`/`perf` -> Changed; `chore`/`build`/`ci`/`test` -> Changed only when user-impacting, otherwise ignore.
- Stage documentation/changelog edits required by this flow, then create one commit using the requested format.
- Allowed git commands are read-only (`git status`, `git diff`, `git log`, `git show`) plus `git add` and `git commit`.
- Use conventional commit prefixes: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `perf`, `ci`, `build`.
- Do not invent information: only describe what the code actually does.
- Keep the message concise, accurate, and focused on the "why" over the "what".

Output:

- Clean diff for documentation/changelog updates.
- Updated changelog section(s), limited to `## [Unreleased]`.
- Created commit hash.
- Final commit message in the requested format (default: `normal`).
- 3-5 bullet recap of what was committed and why.
