# Smartlink

`smartlink` is a cross-platform Node.js CLI for distributing shared AI resources across Claude Code, Cursor, OpenCode, and VS Code Copilot.

It has two modes:

- `smartlink setup` installs the built-in `shared` pack globally
- `smartlink sync` interactively installs optional packs into the current workspace only

## Quick start

### Shared global setup

```bash
node smartlink.js setup
```

After global install:

```bash
npm install -g .
smartlink setup
```

Legacy wrappers still work:

```bash
./setup.sh
setup.cmd
```

### Workspace pack sync

Run this from the repo you want to customize:

```bash
smartlink sync
```

Smartlink shows the target workspace, lets you choose optional packs, then links or copies those resources into the workspace.

## CLI

```bash
smartlink setup
smartlink generate
smartlink install
smartlink sync
smartlink doctor
```

Useful flags:

```bash
smartlink setup --dry-run
smartlink setup --copy
smartlink setup --link
smartlink sync --workspace /path/to/project
smartlink sync --dry-run
smartlink --root /path/to/smartlink-repo setup
```

## Packs

```text
pack/
  shared/
  packSample/
```

- `shared` is special: it is always global-only
- every other `pack/*` is optional and can be synced into a workspace
- `packSample` is an example optional pack

Optional packs can contain:

```text
commands/
agents/
skills/
mcp.json
pack.json
```

## Behavior

### `smartlink setup`

Reads `pack/shared/`, generates the tool-specific files in this repo, then installs them into user-level global config locations.

### `smartlink sync`

Reads optional packs under `pack/*` except `shared`, then installs the selected packs into the target workspace only.

Workspace sync uses:

- visible workspace folders like `.claude/`, `.cursor/`, `.opencode/`, `.github/`, `.vscode/`
- hidden state in `.smartlink/sync-state.json`
- hidden staging in `.smartlink/staging/`

## Conflict rules

Resource priority is:

1. `shared`
2. first optional pack selected by the user
3. later selected packs

If two packs define the same command, agent, skill, or MCP server name, Smartlink keeps the winner and prints a warning for the skipped duplicate.

## Source of truth

Edit the canonical pack files only:

```text
pack/shared/
pack/packSample/
```

Generated outputs are written to:

```text
.claude/
.cursor/
.opencode/
.github/
.vscode/
.mcp.json
```

## Global install targets

- Claude Code: `~/.claude/commands/`, `~/.claude/agents/`, `~/.claude/skills/`, `~/.claude.json`
- Cursor: `~/.cursor/commands/`, `~/.cursor/agents/`, `~/.cursor/skills/`, `~/.cursor/mcp.json`
- OpenCode: `~/.config/opencode/commands/`, `~/.config/opencode/agents/`, `~/.config/opencode/skills/`, `~/.config/opencode/opencode.json`
- VS Code Copilot: detected profile folders for prompts, MCP, and settings

## Workspace install targets

- Claude Code: `.claude/commands/`, `.claude/agents/`, `.claude/skills/`, `.mcp.json`
- Cursor: `.cursor/commands/`, `.cursor/agents/`, `.cursor/skills/`, `.cursor/mcp.json`
- OpenCode: `.opencode/commands/`, `.opencode/agents/`, `.opencode/skills/`, `opencode.json`
- VS Code Copilot: `.github/prompts/`, `.github/agents/`, `.github/skills/`, `.vscode/mcp.json`

## Project structure

```text
package.json
smartlink.js
lib/
  paths.js
  generate.js
  install.js
  sync.js
pack/
  shared/
  packSample/
setup.sh
setup.cmd
```

## Development

Useful local commands:

```bash
node smartlink.js doctor
node smartlink.js generate
node smartlink.js setup --dry-run
node smartlink.js sync --workspace /tmp/example --dry-run
```

## Notes

- `setup.ps1` was removed; the same Node CLI now drives every OS.
- `setup.sh` and `setup.cmd` are compatibility wrappers.
- On systems without symlink support, Smartlink falls back to copying files.
