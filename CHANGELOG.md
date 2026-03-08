# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.0.11] - 2026-03-08

### Changed

- `/commit` and `/release` commands (`pack/shared/commands/commit.md`, `pack/shared/commands/release.md`): now scope their documentation and changelog update steps to the concrete files they are expected to touch, making the staged-change release flow more predictable

## [0.0.10] - 2026-03-08

### Changed

- `/commit` command (`pack/shared/commands/commit.md`): now mirrors the release preflight by updating affected documentation, refreshing `## [Unreleased]` changelog entries from staged changes, staging those edits, and creating the commit without tagging or pushing
- `/changelog` command (`pack/shared/commands/changelog.md`): now also proposes a `normal` commit message after updating the changelog so the next commit can be created immediately without running `/commit` separately

## [0.0.9] - 2026-03-03

### Added

- VS Code profile discovery in `setup.sh` and `setup.ps1`: setup now detects Code/Code Insiders/VSCodium user and remote roots, includes `profiles/<profile-id>/`, and deploys prompts plus `mcp.json` per effective profile

### Changed

- VS Code deployment now prefers named profiles over root `User` paths when both exist, and removes managed legacy root symlinks to prevent duplicate command/MCP entries
- VS Code `settings.json` updates now normalize `chat.agentFilesLocations` and `chat.agentSkillsLocations` as location maps across detected profiles, improving compatibility with existing settings shapes

## [v0.0.8] - 2026-03-01

### Added

- `/release` command (`pack/shared/commands/release.md`): adds a one-command release flow that updates documentation and changelog from staged changes, creates a normal commit, creates an annotated tag, and pushes both branch and tag

### Changed

- `setup.sh`: file mode changed to executable (`100755`) so it can be run directly as `./setup.sh`

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
