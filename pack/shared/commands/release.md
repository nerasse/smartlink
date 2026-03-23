---
name: release
description: Run versioning, docs, changelog, commit, tag, and push for a release
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
# vscode.extra.description: Run versioning, docs, changelog, commit, tag, and push for a release
vscode.agent: agent
---
Goal: run a full release flow in one command: bump versions for changed packages, update documentation, update changelog, create a normal commit, create a tag, and push branch + tag.

Modes:

- `/release help` or `--help`: return a short usage guide and stop.
- `/release <tag>`: run the full release pipeline using `<tag>`.

Rules:

- Treat this prompt as self-contained: do not rely on hidden/system prompts for documentation, changelog, or commit conventions.
- The tag argument is mandatory. If missing, ask the user for a tag and stop before any write operation.
- If `AGENTS.md` exists and contains release/changelog/documentation/commit/tag directives, follow it with priority.
- If no tag naming convention is defined in `AGENTS.md`, do not enforce a format; recommend `vX.Y.Z` as option 1 and continue with the user's chosen tag.
- Start from staged changes as source of truth (`git diff --cached`). If nothing is staged, stop and explain why.
- Detect changed package scopes from staged changes, then bump versions only for packages that changed in non-documentation files.
- Version files to check include `package.json`, `Cargo.toml`, `pyproject.toml`, and equivalent manifests that declare package versions.
- Infer bump level per package from staged change intent: major for breaking changes, minor for new backward-compatible features, patch for fixes/refactors/perf/chore/build/test changes that affect behavior. If uncertain, default to patch and state the assumption.
- If a staged manifest already includes a manual version bump, keep the staged version instead of overwriting it.
- Apply version bumps without creating extra commits or tags (for example, do not run `npm version` in its default commit/tag mode).
- Update lock/version companion files when required by the ecosystem and tracked in the repo (for example `package-lock.json`, `pnpm-lock.yaml`, `Cargo.lock`).
- In monorepos, scope versioning, documentation, and changelog updates to touched packages only.
- Then run documentation updates on files affected by staged changes: `README.md`, `CONTRIBUTING.md`, `ARCHITECTURE.md`, inline doc headers, usage examples, CLI help text, and any file under `docs/`.
- For documentation edits, update only sections impacted by staged changes, preserve the existing tone/structure, add missing docs for staged new behavior, remove or mark removed behavior, and keep wording concise and accessible.
- Then run changelog update with the provided tag on any `CHANGELOG.md` file(s).
- For changelog edits, keep a Keep a Changelog structure, do not rewrite historical releases, and create/update `## [<tag>] - YYYY-MM-DD` from `## [Unreleased]` while keeping `## [Unreleased]` for future changes.
- In changelog entries, group by package (monorepos) then feature, ignore documentation-only or ancillary resource changes, and keep entries concise, actionable, deduplicated, and clear for beginners and experts.
- Use changelog type mapping: `feat`/`add`/`new` -> Added; `fix` -> Fixed; `refactor`/`perf` -> Changed; `chore`/`build`/`ci`/`test` -> Changed only when user-impacting, otherwise ignore.
- Stage versioning/documentation/changelog edits required by this flow, then create one release commit.
- Commit message must be `normal` format (same standard as `/commit normal`): subject line + blank line + 1-3 sentence body explaining the why.
- Use conventional commit prefixes (`feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `perf`, `ci`, `build`) and never invent information in the message.
- Before creating a tag, verify whether it already exists locally or on remote. If it exists, stop and ask the user what to do.
- Create an annotated tag using the provided tag.
- Push branch first, then push the tag.
- Never use `--force`, never delete/rewrite existing tags, and never amend published history.

Allowed git commands:

- Read-only: `git status`, `git diff`, `git log`, `git show`, `git branch`, `git remote`, `git rev-parse`, `git tag --list`, `git ls-remote --tags`.
- Write: `git add`, `git commit`, `git tag -a`, `git push`.

Output:

- Clean diff for versioning/documentation/changelog updates.
- Bumped packages with old -> new version and bump rationale.
- Changelog file(s) updated and target release section(s) created.
- Created commit hash and tag name.
- Final release commit message in `normal` format.
- Push result for branch and tag.
- 3-5 bullet recap of what was released and why.
