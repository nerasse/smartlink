# Smartlink

Write commands, agents, skills, and MCP server configs **once** — deploy them to **Claude Code**, **Cursor**, **OpenCode**, and **VS Code Copilot** simultaneously, both at project level and globally on your machine.

```
pack/shared/          <-- you edit here (single source of truth)
  commands/*.md
  agents/*.md
  skills/<name>/SKILL.md
  mcp.json

setup.cmd             <-- generates + deploys everything
```

## Quick start

```bash
# Linux / macOS / WSL
./setup.sh

# Windows
setup.cmd
```

Setup does two things:

1. **Generates** tool-specific files in `.claude/`, `.cursor/`, `.opencode/`, `.github/`, `.vscode/`
2. **Deploys globally** via symlinks (or copy fallback) so every project on your machine gets them

## How it works

Each resource type lives in `pack/shared/` as a single markdown file with YAML frontmatter. Setup reads the frontmatter, extracts per-tool overrides, and writes the correct format for each tool.

### Frontmatter namespacing

Every canonical file uses prefixed keys to target specific tools:

```yaml
---
name: my-resource
description: What it does

# Shared fallback (used when a tool-specific key is absent)
common.model: inherit

# Per-tool overrides
claude.model: haiku
opencode.model: anthropic/claude-haiku-4-5
cursor.model: fast
vscode.model: ['Claude Haiku 4.5 (copilot)']

# Pass-through (forwarded as-is to the tool's output)
opencode.extra.top_p: 0.9
---
```

**Resolution order:** `<tool>.<field>` > `common.<field>` > default/omitted.

---

## Commands

Slash commands / prompt files that the user triggers manually (e.g. `/commit`, `/changelog`).

### Source format

`pack/shared/commands/<name>.md`

```yaml
---
name: commit
description: Propose a commit message from staged git changes
argument-hint: "[short|normal|verbose|help]"
claude.disable-model-invocation: true
vscode.agent: agent
---
Goal: propose a commit message from staged git changes.
...
```

### Generated outputs

| Tool | Project path | Global path |
|---|---|---|
| Claude Code | `.claude/commands/<name>.md` | `~/.claude/commands/` |
| Cursor | `.cursor/commands/<name>.md` | `~/.cursor/commands/` |
| OpenCode | `.opencode/commands/<name>.md` | `~/.config/opencode/commands/` |
| VS Code | `.github/prompts/<name>.prompt.md` | via `settings.json` (see below) |

### Supported frontmatter keys

| Key | Claude | OpenCode | Cursor | VS Code |
|---|---|---|---|---|
| `name` | name | *(filename)* | *(filename)* | name |
| `description` | description | description | *(body only)* | description |
| `argument-hint` | argument-hint | — | — | argument-hint |
| `disable-model-invocation` | disable-model-invocation | — | — | — |
| `user-invocable` | user-invocable | — | — | — |
| `allowed-tools` | allowed-tools | — | — | — |
| `model` | model | model | — | model |
| `context` | context (fork) | — | — | — |
| `agent` | agent | agent | — | agent |
| `hooks` | hooks | — | — | — |
| `subtask` | — | subtask | — | — |
| `tools` | — | — | — | tools |

### Included commands

| Command | Description |
|---|---|
| `/commit` | Propose a conventional commit message from staged changes |
| `/changelog` | Update changelog from staged changes (Keep a Changelog format) |
| `/documentation` | Update affected docs (README, CONTRIBUTING, etc.) from staged changes |
| `/resolve-conflicts` | AI-assisted merge/rebase conflict resolution |

---

## Agents (sub-agents)

Specialized AI personas that can be invoked as sub-agents (by the main agent or explicitly).

### Source format

`pack/shared/agents/<name>.md`

```yaml
---
name: web-researcher
description: Deep web research agent — iterative search, analysis, and synthesis
claude.model: haiku
claude.maxTurns: 30
claude.mcpServers: ["searxng"]
opencode.mode: subagent
opencode.model: anthropic/claude-haiku-4-5
cursor.model: fast
cursor.readonly: true
vscode.tools: ['fetch','search','readFile','agent','searxng/*']
---
You are a deep web research agent...
```

### Generated outputs

| Tool | Project path | Global path |
|---|---|---|
| Claude Code | `.claude/agents/<name>.md` | `~/.claude/agents/` |
| Cursor | `.cursor/agents/<name>.md` | `~/.cursor/agents/` |
| OpenCode | `.opencode/agents/<name>.md` | `~/.config/opencode/agents/` |
| VS Code | `.github/agents/<name>.agent.md` | via `settings.json` |

### Supported frontmatter keys

| Key | Claude | OpenCode | Cursor | VS Code |
|---|---|---|---|---|
| `name` | name | *(filename)* | name | name |
| `description` | description | description | description | description |
| `model` | model | model | model | model |
| `tools` | tools | tools (JSON obj) | — | tools |
| `disallowedTools` | disallowedTools | — | — | — |
| `permissionMode` | permissionMode | — | — | — |
| `maxTurns` | maxTurns | — | — | — |
| `mcpServers` | mcpServers | — | — | mcp-servers |
| `hooks` | hooks | — | — | — |
| `memory` | memory | — | — | — |
| `background` | background | — | — | — |
| `isolation` | isolation | — | — | — |
| `mode` | — | mode | — | — |
| `temperature` | — | temperature | — | — |
| `steps` | — | steps | — | — |
| `permission` | — | permission (JSON) | — | — |
| `hidden` | — | hidden | — | — |
| `color` | — | color | — | — |
| `top_p` | — | top_p | — | — |
| `readonly` | — | — | readonly | — |
| `is_background` | — | — | is_background | — |
| `agents` | — | — | — | agents |
| `user-invokable` | — | — | — | user-invokable |
| `disable-model-invocation` | — | — | — | disable-model-invocation |
| `handoffs` | — | — | — | handoffs |

### Included agents

| Agent | Description |
|---|---|
| `web-researcher` | Deep iterative web research with SearXNG MCP — broad search, deep dive, synthesis |
| `frontend-ui` | Frontend UI specialist — accessibility, UX, reusable components |

---

## Skills

Reusable knowledge packages that agents can load on demand. Skills follow the open [Agent Skills](https://agentskills.io) standard (`SKILL.md`).

### Source format

`pack/shared/skills/<name>/SKILL.md`

```yaml
---
name: code-review
description: >-
  Structured code review workflow. Use when asked to review a PR,
  check code quality, or audit for security issues.
claude.allowed-tools: Read, Glob, Grep
opencode.permission: {"edit":"deny"}
---
## Step 1 — Understand the change
Read the diff and identify the intent...

## Step 2 — Check for issues
...
```

A skill directory can also contain supporting files (references, scripts, templates) — reference them from the SKILL.md body so the agent knows when to load them.

### Generated outputs

| Tool | Project path | Global path |
|---|---|---|
| Claude Code | `.claude/skills/<name>/SKILL.md` | `~/.claude/skills/` |
| Cursor | `.cursor/skills/<name>/SKILL.md` | `~/.cursor/skills/` |
| OpenCode | `.opencode/skills/<name>/SKILL.md` | `~/.config/opencode/skills/` |
| VS Code | `.github/skills/<name>/SKILL.md` | via `settings.json` |

### Supported frontmatter keys

| Key | Claude | OpenCode | Cursor | VS Code |
|---|---|---|---|---|
| `name` | name | name | name | name |
| `description` | description | description | description | description |
| `allowed-tools` | allowed-tools | — | — | — |
| `disable-model-invocation` | disable-model-invocation | — | — | disable-model-invocation |
| `model` | model | — | — | — |
| `permission` | — | permission | — | — |
| `user-invokable` | — | — | — | user-invokable |

### Skills vs Commands vs Agents

| | Commands | Agents | Skills |
|---|---|---|---|
| **Trigger** | User types `/name` | Main agent delegates or user invokes | Agent loads automatically when relevant |
| **Context** | Runs in current session | Runs in its own sub-context | Injected into the calling agent's context |
| **Scope** | One-shot task | Persistent persona with tools | Reusable knowledge/workflow |
| **Example** | `/commit`, `/changelog` | `web-researcher`, `frontend-ui` | `code-review`, `deployment` |

---

## MCP servers

External tool servers that agents can call (search engines, databases, APIs, etc.).

### Source format

`pack/shared/mcp.json` — flat object, one key per server:

```json
{
  "searxng": {
    "command": "npx",
    "args": ["-y", "mcp-searxng"],
    "env": { "SEARXNG_URL": "https://search.example.com/" }
  },
  "github": {
    "type": "http",
    "url": "https://api.githubcopilot.com/mcp/",
    "headers": { "Authorization": "Bearer ${GITHUB_TOKEN}" }
  }
}
```

### Transport types

| `type` | When to use | Required fields |
|---|---|---|
| `stdio` *(default)* | Local program launched as subprocess | `command`, `args` |
| `http` *(recommended for remote)* | Streamable HTTP server | `url` |
| `sse` | Legacy Server-Sent Events | `url` |

If `type` is omitted: `stdio` when `command` is present, `http` when only `url` is present.

### How setup transforms each server

**stdio servers:**

| | Claude Code | Cursor | VS Code | OpenCode |
|---|---|---|---|---|
| type | *(omitted)* | *(omitted)* | *(omitted)* | `"local"` |
| command | `"npx"` (string) | `"npx"` (string) | `"npx"` (string) | `["npx","-y","pkg"]` (array) |
| env key | `env` | `env` | `env` | `environment` |
| root key | `mcpServers` | `mcpServers` | `servers` | `mcp` in `opencode.json` |

**Remote servers (http/sse):**

| | Claude Code | Cursor | VS Code | OpenCode |
|---|---|---|---|---|
| type | `"http"` / `"sse"` | *(omitted)* | `"http"` / `"sse"` | `"remote"` |
| root key | `mcpServers` | `mcpServers` | `servers` | `mcp` in `opencode.json` |

### Generated outputs

| Tool | Project path | Global path |
|---|---|---|
| Claude Code | `.mcp.json` | `~/.claude.json` (`mcpServers` key merged) |
| Cursor | `.cursor/mcp.json` | `~/.cursor/mcp.json` (symlinked) |
| VS Code | `.vscode/mcp.json` | `Code/User/mcp.json` (symlinked) |
| OpenCode | *(in opencode.json)* | `~/.config/opencode/opencode.json` (`mcp` key merged) |

### Variable interpolation

Values in `env` and `headers` are copied verbatim. Use the syntax your tool expects:

| Tool | Syntax | Example |
|---|---|---|
| Claude Code | `${VAR}` or `${VAR:-default}` | `"Bearer ${GITHUB_TOKEN}"` |
| Cursor | `${env:VAR}` | `"Bearer ${env:GITHUB_TOKEN}"` |
| OpenCode | `{env:VAR}` (no `$`) | `"Bearer {env:GITHUB_TOKEN}"` |
| VS Code | `${input:id}` (prompted) or `${VAR}` | `"Bearer ${input:token}"` |

For cross-tool compatibility, use plain env vars set in your shell — all tools inherit them.

---

## Global deployment details

Setup deploys everything to user-level config directories so agents, commands, skills, and MCP are available in **every project** on the machine.

| Tool | Commands | Agents | Skills | MCP |
|---|---|---|---|---|
| Claude Code | `~/.claude/commands/` | `~/.claude/agents/` | `~/.claude/skills/` | `~/.claude.json` merge |
| Cursor | `~/.cursor/commands/` | `~/.cursor/agents/` | `~/.cursor/skills/` | `~/.cursor/mcp.json` |
| OpenCode | `~/.config/opencode/commands/` | `~/.config/opencode/agents/` | `~/.config/opencode/skills/` | `opencode.json` merge |
| VS Code | `settings.json` * | `settings.json` * | `settings.json` * | `Code/User/mcp.json` |

\* VS Code has no fixed global directory for agents/skills/prompts. Setup adds paths to `Code/User/settings.json`:

```json
{
  "chat.agentFilesLocations": ["/path/to/smartlink/.github/agents"],
  "chat.agentSkillsLocations": ["/path/to/smartlink/.github/skills"]
}
```

### Symlinks vs copies

On systems with symlink support (Linux, macOS, Windows with Developer Mode), setup creates symlinks — changes propagate automatically on next `setup` run. Without symlinks (default Windows), files are copied and you must re-run `setup` after editing sources.

---

## Project structure

```
pack/shared/
  commands/
    changelog.md
    commit.md
    documentation.md
    resolve-conflicts.md
  agents/
    frontend-ui.md
    web-researcher.md
  skills/                     <-- add skill directories here
    <name>/SKILL.md
  mcp.json

setup.sh                      <-- Linux / macOS / WSL
setup.ps1                     <-- Windows (PowerShell)
setup.cmd                     <-- Windows (calls setup.ps1)
```

Generated files (all gitignored):

```
.claude/commands/  agents/  skills/     <-- Claude Code
.cursor/commands/  agents/  skills/     <-- Cursor
.opencode/commands/  agents/  skills/   <-- OpenCode
.github/prompts/  agents/  skills/      <-- VS Code Copilot
.mcp.json  .cursor/mcp.json  .vscode/mcp.json
```

## Adding new resources

**New command:**
```bash
# Create pack/shared/commands/my-command.md with frontmatter + body
# Run setup
setup.cmd   # or ./setup.sh
```

**New agent:**
```bash
# Create pack/shared/agents/my-agent.md with frontmatter + body
setup.cmd
```

**New skill:**
```bash
# Create pack/shared/skills/my-skill/SKILL.md with frontmatter + body
# Optionally add supporting files in the same directory
setup.cmd
```

**New MCP server:**
```bash
# Add an entry to pack/shared/mcp.json
setup.cmd
```

Convention: the filename (commands/agents) or directory name (skills) should match the `name` field in the frontmatter.
