---
name: release
description: Run docs, changelog, commit, tag, and push for a release
argument-hint: "<tag>|help"

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
# claude.argument-hint: "<tag>|help"
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
# vscode.argument-hint: "<tag>|help"
# vscode.agent: agent
# vscode.model: ['GPT-5.2','Claude Sonnet 4.5']
# vscode.tools: ['search','read','editFiles','terminalLastCommand','githubRepo','my-mcp/*']
# vscode.extra.name: release
# vscode.extra.description: Run docs, changelog, commit, tag, and push for a release
vscode.agent: agent
---
Goal: run a full release flow in one command: update documentation, update changelog, create a normal commit, create a tag, and push branch + tag.

Modes:

- `/release help` or `--help`: return a short usage guide and stop.
- `/release <tag>`: run the full release pipeline using `<tag>`.

Rules:

- The tag argument is mandatory. If missing, ask the user for a tag and stop before any write operation.
- If `AGENTS.md` exists and contains release/changelog/documentation/commit/tag directives, follow it with priority.
- If no tag naming convention is defined in `AGENTS.md`, do not enforce a format; recommend `vX.Y.Z` as option 1 and continue with the user's chosen tag.
- Start from staged changes as source of truth. If nothing is staged, stop and explain why.
- Run documentation updates first (same intent as `/documentation`, staged changes only).
- Then run changelog update with the provided tag (same intent as `/changelog <tag>`).
- Stage documentation/changelog edits required by this flow, then create one release commit.
- Commit message must be `normal` format (same standard as `/commit normal`).
- Before creating a tag, verify whether it already exists locally or on remote. If it exists, stop and ask the user what to do.
- Create an annotated tag using the provided tag.
- Push branch first, then push the tag.
- Never use `--force`, never delete/rewrite existing tags, and never amend published history.

Allowed git commands:

- Read-only: `git status`, `git diff`, `git log`, `git show`, `git branch`, `git remote`, `git rev-parse`, `git tag --list`, `git ls-remote --tags`.
- Write: `git add`, `git commit`, `git tag -a`, `git push`.

Output:

- Clean diff for documentation/changelog updates.
- Created commit hash and tag name.
- Push result for branch and tag.
- 3-5 bullet recap of what was released and why.
