---
name: resolve-conflicts
description: AI-assisted merge conflict resolution
argument-hint: "[branch] [rebase]"

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
# common.argument-hint: "[branch] [rebase]"
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
# claude.argument-hint: "[branch] [rebase]"
# claude.disable-model-invocation: false
# claude.user-invocable: true
# claude.allowed-tools: Read, Glob, Grep, Bash(git *), Write, Edit
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
# vscode.argument-hint: "[branch] [rebase]"
# vscode.agent: agent
# vscode.model: ['GPT-5.2','Claude Sonnet 4.5']
# vscode.tools: ['search','read','editFiles','terminalLastCommand','githubRepo','my-mcp/*']
# vscode.extra.name: resolve-conflicts
# vscode.extra.description: AI-assisted merge conflict resolution
vscode.agent: agent
---
Goal: resolve merge conflicts between the current branch and a target branch.

Modes:

- `/resolve-conflicts help` or `--help`: return a short usage guide and stop.
- `/resolve-conflicts`: merge the default branch (auto-detected) into the current branch, resolve conflicts.
- `/resolve-conflicts <branch>`: merge `<branch>` into the current branch, resolve conflicts.
- `/resolve-conflicts <branch> rebase`: rebase the current branch onto `<branch>`, resolve conflicts (linear history, no merge commit).

Default branch detection (when no argument is given):

1. `git symbolic-ref refs/remotes/origin/HEAD` (the remote default branch).
2. Fallback to `main`.

Workflow:

1. **Pre-flight checks**:
   - Confirm the working tree is clean (`git status --porcelain`). If dirty, warn and stop — do not risk losing uncommitted work.
   - Confirm the current branch is not the target branch itself.
   - Run `git fetch origin` to ensure the target ref is up to date.

2. **Start merge or rebase**:
   - Merge mode (default): `git merge --no-commit --no-ff origin/<branch>`.
   - Rebase mode: `git rebase origin/<branch>` (conflicts handled one commit at a time).
   - If there are no conflicts, report success and let the merge/rebase complete normally.

3. **Identify conflicts**:
   - List conflicted files: `git diff --name-only --diff-filter=U`.
   - For each file, read the full content including conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`).

4. **Resolve each conflict**:
   - Read both sides of each conflict block and the surrounding context.
   - If `AGENTS.md` exists and contains conflict resolution directives, follow them.
   - Apply the most sensible resolution:
     - Independent changes (different logical concerns) -> keep both.
     - Overlapping changes (same logic modified differently) -> merge intent from both sides, preserving correctness.
     - Refactor vs feature -> keep feature behavior with refactored style/naming.
     - Deleted file vs modified file -> ask the user which to keep.
   - After editing, remove all conflict markers. The file must be clean.
   - Stage the resolved file: `git add <file>`.

5. **Finalize**:
   - Merge mode: `git merge --continue`.
   - Rebase mode: `git rebase --continue` (repeat step 4 for each conflicting commit).

6. **Post-resolution checks**:
   - Confirm no conflict markers remain anywhere: search for `<<<<<<<` in tracked files.
   - If a build/lint/test command is obvious from the project (package.json scripts, Makefile, etc.), suggest running it but do not run it automatically.

7. **Report**:
   - Summary of resolved files and what was chosen for each.
   - The merge/rebase commit hash.
   - If rebase was used, remind the user that force-push may be needed (`git push --force-with-lease`).

Rules:

- Never force-push, delete branches, or reset commits. Only merge/rebase and resolve.
- Never modify files that are not in conflict.
- If a conflict is ambiguous and cannot be resolved with confidence, show both sides to the user and ask which to keep.
- Allowed git commands: `git status`, `git diff`, `git log`, `git show`, `git fetch`, `git merge`, `git rebase`, `git add`, `git branch`, `git symbolic-ref`, `git rev-parse`. No `git push`, `git reset --hard`, `git clean`.
- If the merge/rebase gets into a bad state, abort cleanly (`git merge --abort` or `git rebase --abort`) and report what happened.
- Do not invent code. Resolutions must only combine or select from what already exists in both sides.

Output:

- Per-file summary: file path, conflict type, resolution chosen.
- Final status: merge/rebase complete or aborted with reason.
