# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.0.7] - 2026-02-28

### Changed

- `setup.sh`: replaced all inline Python 3 scripts with Node.js equivalents for MCP config generation, global JSON merges (`~/.claude.json`, `opencode.json`), and VS Code `settings.json` updates — Python is no longer required on Linux/macOS/WSL since Node.js is already an implicit dependency (used by `npx` for MCP servers)

## [0.0.6] - 2026-02-28

### Added

- Skills pipeline (`pack/shared/skills/<name>/SKILL.md`): new resource type following the open Agent Skills standard; setup generates per-tool skill files (`.claude/skills/`, `.cursor/skills/`, `.opencode/skills/`, `.github/skills/`) and symlinks them globally (`~/.claude/skills/`, `~/.config/opencode/skills/`, `~/.cursor/skills/`)
- VS Code global deployment for agents and skills: setup now updates `%APPDATA%/Code/User/settings.json` with `chat.agentFilesLocations` and `chat.agentSkillsLocations` so agents and skills are available in every workspace
- `.github/skills/` added to `.gitignore`

### Changed

- `ConvertTo-OrderedHash` helper moved out of the MCP `if` block in `setup.ps1` so it is available unconditionally (fixes a crash when `pack/shared/mcp.json` is absent but VS Code settings update runs)
- Final report in both `setup.ps1` and `setup.sh` replaced with a comprehensive "Global deployment summary" covering all 4 resource types across all 4 tools
- README rewritten from scratch: concise structure covering commands, agents, skills, and MCP with per-tool frontmatter key catalogs, generation/deployment tables, and a quick-start guide

## [0.0.5] - 2026-02-28

### Changed

- `web-researcher` agent (`pack/shared/agents/web-researcher.md`): updated opencode model from `claude-haiku-4-20250514` to `claude-haiku-4-5`; narrowed VS Code model list to `Claude Haiku 4.5 (copilot)` only (previously included `Claude Sonnet 4.5` and `GPT-5.2`)

## [0.0.4] - 2026-02-27

### Added

- `web-researcher` agent (`pack/shared/agents/web-researcher.md`): deep web research subagent that performs iterative multi-layered searches (broad exploration → deep dive → synthesis) and returns a structured answer with cited sources
- `/resolve-conflicts` command (`pack/shared/commands/resolve-conflicts.md`): AI-assisted merge conflict resolution supporting both merge and rebase modes; auto-detects the default branch, reads conflict markers, applies the most sensible resolution strategy, and stages results
- `pack/shared/mcp.json`: new canonical MCP server source file; define all MCP servers once (SearXNG pre-configured); `setup` reads this file and generates per-tool configs automatically
- MCP config generation in `setup.sh` and `setup.ps1`: produces per-tool project-level configs (`.mcp.json` for Claude Code, `.cursor/mcp.json` for Cursor, `.vscode/mcp.json` for VS Code Copilot) and deploys globally — merges `mcpServers` into `~/.claude.json`, symlinks to `~/.cursor/mcp.json` and VS Code's user dir, and merges the `mcp` key into `~/.config/opencode/opencode.json`
- Generated MCP config files (`.mcp.json`, `.vscode/mcp.json`) added to `.gitignore`

## [0.0.3] - 2026-02-27

### Added

- Global distribution step in `setup.sh` and `setup.ps1`: generated files are now symlinked (or copied as fallback) to each tool's global config directory (`~/.config/opencode/`, `~/.claude/`, `~/.cursor/`)
- Symlink capability probe to detect whether the OS supports real symlinks; falls back to file copy on Windows without Developer Mode
- Safe backup logic: existing files at global targets are backed up with `.bak.YYYYMMDD-HHMMSS` before replacement
- Idempotent global step: skips files that already match (symlink target or file content)
- VS Code reminder printed at the end of setup (no global dir; requires `chat.agentFilesLocations` setting)
- `/commit` command: proposes a commit message from staged changes in `short`, `normal`, or `verbose` format following conventional commit conventions
- `/documentation` command: analyses staged changes and updates affected documentation files (`README.md`, `CONTRIBUTING.md`, `ARCHITECTURE.md`, `docs/`, etc.)

### Changed

- `/changelog` command: clarified mode descriptions (`create or update [Unreleased]`) and removed stale commit-message options from the output spec (that responsibility now lives in `/commit`)

### Fixed

- Removed stale `.ruff_cache/` and `__pycache__/` entries from `.gitignore` (leftover from deleted Python setup)
