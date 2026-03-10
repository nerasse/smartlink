---
name: workspace-readme
description: Draft or refresh a workspace onboarding README
argument-hint: "[focus]"
claude.disable-model-invocation: true
vscode.agent: agent
---
Goal: create or update a short workspace README that helps a teammate start quickly.

Rules:
- Inspect the current repository structure before writing.
- Focus on setup, common commands, and project-specific conventions.
- Keep the README concise and practical.
- If a README already exists, update only the relevant sections.

Output:
- Updated README content
- 3 bullet recap of what changed
