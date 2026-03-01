#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_COMMANDS_DIR="$ROOT/pack/shared/commands"
SHARED_AGENTS_DIR="$ROOT/pack/shared/agents"
SHARED_SKILLS_DIR="$ROOT/pack/shared/skills"

written=0
unchanged=0
total=0

PARSED_NAME=""
PARSED_DESCRIPTION=""
PARSED_ARGUMENT_HINT=""
PARSED_BODY=""
PARSED_META_KEYS=()
PARSED_META_VALUES=()

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

strip_quotes() {
  local s="$1"
  local q="'"

  if [ "${#s}" -ge 2 ]; then
    if [ "${s:0:1}" = '"' ] && [ "${s: -1}" = '"' ]; then
      s="${s:1:${#s}-2}"
    elif [ "${s:0:1}" = "$q" ] && [ "${s: -1}" = "$q" ]; then
      s="${s:1:${#s}-2}"
    fi
  fi

  printf '%s' "$s"
}

trim_trailing_newlines() {
  local s="$1"
  while [[ "$s" == *$'\n' ]]; do
    s="${s%$'\n'}"
  done
  printf '%s' "$s"
}

yaml_quote() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

yaml_scalar_auto() {
  local s="$1"
  local inner

  if [[ "$s" =~ ^(true|false|null)$ ]]; then
    printf '%s' "$s"
    return
  fi

  if [[ "$s" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s' "$s"
    return
  fi

  if [[ "$s" == \[* && "$s" == *\] ]]; then
    inner="${s:1:${#s}-2}"
    if [[ "$inner" == *","* || "$inner" == *":"* || "$inner" == *"\""* || "$inner" == *"'"* || "$inner" == *"{"* || "$inner" == *"["* ]]; then
      printf '%s' "$s"
      return
    fi
  fi

  if [[ "$s" == \{* && "$s" == *\} ]]; then
    inner="${s:1:${#s}-2}"
    if [[ "$inner" == *":"* ]]; then
      printf '%s' "$s"
      return
    fi
  fi

  yaml_quote "$s"
}

append_yaml_field() {
  local header_var="$1"
  local key="$2"
  local value="$3"
  local rendered

  [ -z "$value" ] && return

  rendered="$(yaml_scalar_auto "$value")"
  printf -v "$header_var" '%s%s: %s\n' "${!header_var}" "$key" "$rendered"
}

write_if_changed() {
  local path="$1"
  local content="$2"
  local rel tmp

  mkdir -p "$(dirname "$path")"
  tmp="$(mktemp)"
  printf '%s' "$content" > "$tmp"

  rel="${path#$ROOT/}"

  if [ -f "$path" ] && cmp -s "$path" "$tmp"; then
    printf 'ok    %s\n' "$rel"
    unchanged=$((unchanged + 1))
    rm -f "$tmp"
  else
    mv "$tmp" "$path"
    printf 'write %s\n' "$rel"
    written=$((written + 1))
  fi

  total=$((total + 1))
}

fail_parse() {
  printf 'error: %s\n' "$1" >&2
  exit 2
}

meta_reset() {
  PARSED_META_KEYS=()
  PARSED_META_VALUES=()
}

meta_set() {
  local key="$1"
  local value="$2"
  local idx

  for idx in "${!PARSED_META_KEYS[@]}"; do
    if [ "${PARSED_META_KEYS[$idx]}" = "$key" ]; then
      PARSED_META_VALUES[$idx]="$value"
      return
    fi
  done

  PARSED_META_KEYS+=("$key")
  PARSED_META_VALUES+=("$value")
}

meta_get() {
  local key="$1"
  local idx

  for idx in "${!PARSED_META_KEYS[@]}"; do
    if [ "${PARSED_META_KEYS[$idx]}" = "$key" ]; then
      printf '%s' "${PARSED_META_VALUES[$idx]}"
      return
    fi
  done
}

resolve_agent_value() {
  local tool="$1"
  local field="$2"
  local value

  value="$(meta_get "$tool.$field")"
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return
  fi

  value="$(meta_get "common.$field")"
  printf '%s' "$value"
}

append_extra_fields() {
  local header_var="$1"
  local prefix="$2"
  local idx key field value

  for idx in "${!PARSED_META_KEYS[@]}"; do
    key="${PARSED_META_KEYS[$idx]}"
    if [[ "$key" == "$prefix"* ]]; then
      field="${key#"$prefix"}"
      value="${PARSED_META_VALUES[$idx]}"
      append_yaml_field "$header_var" "$field" "$value"
    fi
  done
}

parse_doc() {
  local file="$1"
  local mode="start"
  local line stripped key value

  PARSED_NAME=""
  PARSED_DESCRIPTION=""
  PARSED_ARGUMENT_HINT=""
  PARSED_BODY=""
  meta_reset

  while IFS= read -r line || [ -n "$line" ]; do
    case "$mode" in
      start)
        if [ "$line" != '---' ]; then
          fail_parse "$file: missing frontmatter header"
        fi
        mode="frontmatter"
        ;;
      frontmatter)
        if [ "$line" = '---' ]; then
          mode="body"
          continue
        fi

        stripped="$(trim "$line")"
        if [ -z "$stripped" ]; then
          continue
        fi
        if [[ "$stripped" == \#* ]]; then
          continue
        fi
        if [[ "$line" != *:* ]]; then
          fail_parse "$file: invalid frontmatter line: $line"
        fi

        key="$(trim "${line%%:*}")"
        value="$(trim "${line#*:}")"
        value="$(strip_quotes "$value")"

        meta_set "$key" "$value"
        ;;
      body)
        PARSED_BODY+="$line"$'\n'
        ;;
    esac
  done < "$file"

  if [ "$mode" = 'start' ] || [ "$mode" = 'frontmatter' ]; then
    fail_parse "$file: unterminated frontmatter"
  fi

  PARSED_NAME="$(meta_get "name")"
  PARSED_DESCRIPTION="$(meta_get "description")"
  PARSED_ARGUMENT_HINT="$(meta_get "argument-hint")"

  if [ -z "$PARSED_NAME" ]; then
    PARSED_NAME="$(basename "$file" .md)"
  fi
  if [ -z "$PARSED_DESCRIPTION" ]; then
    fail_parse "$file: missing description"
  fi

  PARSED_BODY="$(trim_trailing_newlines "$PARSED_BODY")"
  if [ -z "$PARSED_BODY" ]; then
    fail_parse "$file: empty body"
  fi
  PARSED_BODY+=$'\n'
}

generate_command_outputs() {
  local name="$1"
  local description="$2"
  local argument_hint="$3"
  local body="$4"
  local header content value resolved_hint

  # Claude Code command/skill frontmatter
  header='---'
  header+=$'\n'
  header+="name: $(yaml_quote "$name")"
  header+=$'\n'
  header+="description: $(yaml_quote "$description")"
  header+=$'\n'

  resolved_hint="$(resolve_agent_value "claude" "argument-hint")"
  if [ -z "$resolved_hint" ]; then
    resolved_hint="$argument_hint"
  fi
  append_yaml_field header "argument-hint" "$resolved_hint"

  value="$(resolve_agent_value "claude" "disable-model-invocation")"
  if [ -z "$value" ]; then
    value="true"
  fi
  append_yaml_field header "disable-model-invocation" "$value"

  append_yaml_field header "user-invocable" "$(resolve_agent_value "claude" "user-invocable")"
  append_yaml_field header "allowed-tools" "$(resolve_agent_value "claude" "allowed-tools")"
  append_yaml_field header "model" "$(resolve_agent_value "claude" "model")"
  append_yaml_field header "context" "$(resolve_agent_value "claude" "context")"
  append_yaml_field header "agent" "$(resolve_agent_value "claude" "agent")"
  append_yaml_field header "hooks" "$(resolve_agent_value "claude" "hooks")"
  append_extra_fields header "claude.extra."

  header+='---'
  printf -v content '%s\n\n%s' "$header" "$body"
  write_if_changed "$ROOT/.claude/commands/$name.md" "$content"

  # Cursor commands are markdown-only (no official frontmatter schema)
  write_if_changed "$ROOT/.cursor/commands/$name.md" "$body"

  # OpenCode command frontmatter
  header='---'
  header+=$'\n'
  header+="description: $(yaml_quote "$description")"
  header+=$'\n'
  append_yaml_field header "agent" "$(resolve_agent_value "opencode" "agent")"
  append_yaml_field header "subtask" "$(resolve_agent_value "opencode" "subtask")"
  append_yaml_field header "model" "$(resolve_agent_value "opencode" "model")"
  append_extra_fields header "opencode.extra."
  header+='---'

  printf -v content '%s\n\n%s' "$header" "$body"
  write_if_changed "$ROOT/.opencode/commands/$name.md" "$content"

  # VS Code prompt file frontmatter
  header='---'
  header+=$'\n'
  header+="name: $(yaml_quote "$name")"
  header+=$'\n'
  header+="description: $(yaml_quote "$description")"
  header+=$'\n'

  resolved_hint="$(resolve_agent_value "vscode" "argument-hint")"
  if [ -z "$resolved_hint" ]; then
    resolved_hint="$argument_hint"
  fi
  append_yaml_field header "argument-hint" "$resolved_hint"

  value="$(resolve_agent_value "vscode" "agent")"
  if [ -z "$value" ]; then
    value="agent"
  fi
  append_yaml_field header "agent" "$value"

  append_yaml_field header "model" "$(resolve_agent_value "vscode" "model")"
  append_yaml_field header "tools" "$(resolve_agent_value "vscode" "tools")"
  append_extra_fields header "vscode.extra."

  header+='---'

  printf -v content '%s\n\n%s' "$header" "$body"
  write_if_changed "$ROOT/.github/prompts/$name.prompt.md" "$content"
}

generate_agent_outputs() {
  local name="$1"
  local description="$2"
  local body="$3"
  local header content
  local value

  # Claude Code
  header='---'
  header+=$'\n'
  header+="name: $(yaml_quote "$name")"
  header+=$'\n'
  header+="description: $(yaml_quote "$description")"
  header+=$'\n'

  append_yaml_field header "tools" "$(resolve_agent_value "claude" "tools")"
  append_yaml_field header "disallowedTools" "$(resolve_agent_value "claude" "disallowedTools")"
  append_yaml_field header "model" "$(resolve_agent_value "claude" "model")"
  append_yaml_field header "permissionMode" "$(resolve_agent_value "claude" "permissionMode")"
  append_yaml_field header "maxTurns" "$(resolve_agent_value "claude" "maxTurns")"
  append_yaml_field header "mcpServers" "$(resolve_agent_value "claude" "mcpServers")"
  append_yaml_field header "hooks" "$(resolve_agent_value "claude" "hooks")"
  append_yaml_field header "memory" "$(resolve_agent_value "claude" "memory")"
  append_yaml_field header "background" "$(resolve_agent_value "claude" "background")"
  append_yaml_field header "isolation" "$(resolve_agent_value "claude" "isolation")"
  append_extra_fields header "claude.extra."

  header+='---'
  printf -v content '%s\n\n%s' "$header" "$body"
  write_if_changed "$ROOT/.claude/agents/$name.md" "$content"

  # Cursor
  header='---'
  header+=$'\n'
  header+="name: $(yaml_quote "$name")"
  header+=$'\n'
  header+="description: $(yaml_quote "$description")"
  header+=$'\n'

  append_yaml_field header "model" "$(resolve_agent_value "cursor" "model")"
  append_yaml_field header "readonly" "$(resolve_agent_value "cursor" "readonly")"
  append_yaml_field header "is_background" "$(resolve_agent_value "cursor" "is_background")"
  append_extra_fields header "cursor.extra."

  header+='---'
  printf -v content '%s\n\n%s' "$header" "$body"
  write_if_changed "$ROOT/.cursor/agents/$name.md" "$content"

  # OpenCode
  header='---'
  header+=$'\n'
  header+="description: $(yaml_quote "$description")"
  header+=$'\n'

  value="$(resolve_agent_value "opencode" "mode")"
  if [ -z "$value" ]; then
    value="subagent"
  fi
  append_yaml_field header "mode" "$value"

  append_yaml_field header "model" "$(resolve_agent_value "opencode" "model")"
  append_yaml_field header "temperature" "$(resolve_agent_value "opencode" "temperature")"
  append_yaml_field header "steps" "$(resolve_agent_value "opencode" "steps")"
  append_yaml_field header "disable" "$(resolve_agent_value "opencode" "disable")"
  append_yaml_field header "tools" "$(resolve_agent_value "opencode" "tools")"
  append_yaml_field header "permission" "$(resolve_agent_value "opencode" "permission")"
  append_yaml_field header "hidden" "$(resolve_agent_value "opencode" "hidden")"
  append_yaml_field header "color" "$(resolve_agent_value "opencode" "color")"
  append_yaml_field header "top_p" "$(resolve_agent_value "opencode" "top_p")"
  append_extra_fields header "opencode.extra."

  header+='---'
  printf -v content '%s\n\n%s' "$header" "$body"
  write_if_changed "$ROOT/.opencode/agents/$name.md" "$content"

  # VS Code Copilot
  header='---'
  header+=$'\n'
  header+="name: $(yaml_quote "$name")"
  header+=$'\n'
  header+="description: $(yaml_quote "$description")"
  header+=$'\n'

  append_yaml_field header "argument-hint" "$(resolve_agent_value "vscode" "argument-hint")"
  append_yaml_field header "tools" "$(resolve_agent_value "vscode" "tools")"
  append_yaml_field header "agents" "$(resolve_agent_value "vscode" "agents")"
  append_yaml_field header "model" "$(resolve_agent_value "vscode" "model")"
  append_yaml_field header "user-invokable" "$(resolve_agent_value "vscode" "user-invokable")"
  append_yaml_field header "disable-model-invocation" "$(resolve_agent_value "vscode" "disable-model-invocation")"
  append_yaml_field header "target" "$(resolve_agent_value "vscode" "target")"
  append_yaml_field header "mcp-servers" "$(resolve_agent_value "vscode" "mcp-servers")"
  append_yaml_field header "handoffs" "$(resolve_agent_value "vscode" "handoffs")"
  append_extra_fields header "vscode.extra."

  header+='---'
  printf -v content '%s\n\n%s' "$header" "$body"
  write_if_changed "$ROOT/.github/agents/$name.agent.md" "$content"
}

generate_skill_outputs() {
  local name="$1"
  local description="$2"
  local body="$3"
  local header content

  # Claude Code skill
  header='---'
  header+=$'\n'
  header+="name: $(yaml_quote "$name")"
  header+=$'\n'
  header+="description: $(yaml_quote "$description")"
  header+=$'\n'
  append_yaml_field header "allowed-tools"            "$(resolve_agent_value "claude" "allowed-tools")"
  append_yaml_field header "disable-model-invocation" "$(resolve_agent_value "claude" "disable-model-invocation")"
  append_yaml_field header "model"                    "$(resolve_agent_value "claude" "model")"
  append_extra_fields header "claude.extra."
  header+='---'
  printf -v content '%s\n\n%s' "$header" "$body"
  write_if_changed "$ROOT/.claude/skills/$name/SKILL.md" "$content"

  # Cursor skill
  header='---'
  header+=$'\n'
  header+="name: $(yaml_quote "$name")"
  header+=$'\n'
  header+="description: $(yaml_quote "$description")"
  header+=$'\n'
  append_extra_fields header "cursor.extra."
  header+='---'
  printf -v content '%s\n\n%s' "$header" "$body"
  write_if_changed "$ROOT/.cursor/skills/$name/SKILL.md" "$content"

  # OpenCode skill
  header='---'
  header+=$'\n'
  header+="name: $(yaml_quote "$name")"
  header+=$'\n'
  header+="description: $(yaml_quote "$description")"
  header+=$'\n'
  append_yaml_field header "permission" "$(resolve_agent_value "opencode" "permission")"
  append_extra_fields header "opencode.extra."
  header+='---'
  printf -v content '%s\n\n%s' "$header" "$body"
  write_if_changed "$ROOT/.opencode/skills/$name/SKILL.md" "$content"

  # VS Code skill (.github/skills/)
  header='---'
  header+=$'\n'
  header+="name: $(yaml_quote "$name")"
  header+=$'\n'
  header+="description: $(yaml_quote "$description")"
  header+=$'\n'
  append_yaml_field header "user-invokable"           "$(resolve_agent_value "vscode" "user-invokable")"
  append_yaml_field header "disable-model-invocation" "$(resolve_agent_value "vscode" "disable-model-invocation")"
  append_extra_fields header "vscode.extra."
  header+='---'
  printf -v content '%s\n\n%s' "$header" "$body"
  write_if_changed "$ROOT/.github/skills/$name/SKILL.md" "$content"
}

command_count=0
for file in "$SHARED_COMMANDS_DIR"/*.md; do
  [ -f "$file" ] || continue
  command_count=$((command_count + 1))
  parse_doc "$file"
  generate_command_outputs "$PARSED_NAME" "$PARSED_DESCRIPTION" "$PARSED_ARGUMENT_HINT" "$PARSED_BODY"
done

agent_count=0
for file in "$SHARED_AGENTS_DIR"/*.md; do
  [ -f "$file" ] || continue
  agent_count=$((agent_count + 1))
  parse_doc "$file"
  generate_agent_outputs "$PARSED_NAME" "$PARSED_DESCRIPTION" "$PARSED_BODY"
done

skill_count=0
skill_dirs=()
if [ -d "$SHARED_SKILLS_DIR" ]; then
  while IFS= read -r -d '' d; do
    [ -f "$d/SKILL.md" ] || continue
    skill_dirs+=("$d")
    skill_count=$((skill_count + 1))
  done < <(find "$SHARED_SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
fi

if [ "$command_count" -eq 0 ] && [ "$agent_count" -eq 0 ] && [ "$skill_count" -eq 0 ]; then
  printf 'Nothing to generate. Add canonical files in pack/shared/commands, pack/shared/agents, or pack/shared/skills/<name>/SKILL.md.\n' >&2
  exit 1
fi

# ── Skills generation ─────────────────────────────────────────────────
for skill_dir in "${skill_dirs[@]}"; do
  parse_doc "$skill_dir/SKILL.md"
  generate_skill_outputs "$PARSED_NAME" "$PARSED_DESCRIPTION" "$PARSED_BODY"
done

# ── MCP config generation ──────────────────────────────────────────────
SHARED_MCP_FILE="$ROOT/pack/shared/mcp.json"
MCP_GENERATED=0

if [ -f "$SHARED_MCP_FILE" ]; then
  if ! command -v node &>/dev/null; then
    printf 'WARN  node not found — skipping MCP config generation.\n' >&2
  else
    MCP_GENERATED=1

    # Single Node.js transform: canonical type → per-tool format
    # type "stdio" (default) = local subprocess
    # type "http"            = streamable HTTP (recommended for remote)
    # type "sse"             = legacy SSE remote
    _mcp_js="$(mktemp)"
    cat > "$_mcp_js" << 'JSEOF'
const fs = require('fs');
const src = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const claude = {}, cursor = {}, vscode = {}, opencode = {};

for (const [name, srv] of Object.entries(src)) {
  const ct = (srv.type || (srv.url ? 'http' : 'stdio')).trim();
  if (ct === 'stdio') {
    const e = {};
    if (srv.command) e.command = srv.command;
    if (srv.args)    e.args = [...srv.args];
    if (srv.env)     e.env = srv.env;
    claude[name] = cursor[name] = vscode[name] = e;
    const oc = { type: 'local' };
    oc.command = [...(srv.command ? [srv.command] : []), ...(srv.args || [])];
    if (srv.env) oc.environment = srv.env;
    opencode[name] = oc;
  } else {
    const h = srv.headers;
    const cc = { type: ct };
    if (srv.url) cc.url = srv.url;
    if (h)       cc.headers = h;
    claude[name] = vscode[name] = cc;
    const cu = {};
    if (srv.url) cu.url = srv.url;
    if (h)       cu.headers = h;
    cursor[name] = cu;
    const oc = { type: 'remote' };
    if (srv.url) oc.url = srv.url;
    if (h)       oc.headers = h;
    opencode[name] = oc;
  }
}

const fmt = process.argv[3];
if (fmt === 'claude')   console.log(JSON.stringify({ mcpServers: claude }, null, 2));
if (fmt === 'cursor')   console.log(JSON.stringify({ mcpServers: cursor }, null, 2));
if (fmt === 'vscode')   console.log(JSON.stringify({ servers:    vscode }, null, 2));
if (fmt === 'opencode') console.log(JSON.stringify(opencode, null, 2));
JSEOF

    claude_mcp_json="$(node   "$_mcp_js" "$SHARED_MCP_FILE" claude)"
    cursor_mcp_json="$(node   "$_mcp_js" "$SHARED_MCP_FILE" cursor)"
    vscode_mcp_json="$(node   "$_mcp_js" "$SHARED_MCP_FILE" vscode)"
    opencode_mcp_json="$(node "$_mcp_js" "$SHARED_MCP_FILE" opencode)"
    rm -f "$_mcp_js"

    # Write project-level MCP configs
    write_if_changed "$ROOT/.mcp.json"        "$claude_mcp_json"$'\n'
    write_if_changed "$ROOT/.cursor/mcp.json" "$cursor_mcp_json"$'\n'
    write_if_changed "$ROOT/.vscode/mcp.json" "$vscode_mcp_json"$'\n'
  fi
fi

printf '\n'
printf 'Generated files: %s\n' "$total"
printf -- '- written: %s\n' "$written"
printf -- '- unchanged: %s\n' "$unchanged"

# ── Global symlinks ──────────────────────────────────────────────────

OPENCODE_GLOBAL="$HOME/.config/opencode"
CLAUDE_GLOBAL="$HOME/.claude"
CURSOR_GLOBAL="$HOME/.cursor"
if [[ "$(uname)" == "Darwin" ]]; then
  VSCODE_GLOBAL="$HOME/Library/Application Support/Code/User"
else
  VSCODE_GLOBAL="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"
fi

symlinked=0
copied=0
skipped=0
backed_up=0

# Probe: test if symlinks are available on this system
symlink_failed=0
probe_target="$(mktemp -u)"
if ln -s "$ROOT/.gitignore" "$probe_target" 2>/dev/null && [ -L "$probe_target" ]; then
  rm -f "$probe_target"
else
  rm -f "$probe_target" 2>/dev/null
  symlink_failed=1
  printf 'WARN  Symlinks not available. Falling back to copy.\n'
fi

safe_symlink() {
  local source="$1"
  local target="$2"
  local rel_source rel_target stamp

  rel_source="${source#$ROOT/}"
  rel_target="${target#$HOME/}"

  if [ -L "$target" ]; then
    local existing_link
    existing_link="$(readlink "$target")"
    if [ "$existing_link" = "$source" ]; then
      printf 'link  ~/%s  (ok)\n' "$rel_target"
      skipped=$((skipped + 1))
      return
    fi
    # Symlink exists but points elsewhere — remove it (no backup needed for symlinks)
    rm -f "$target"
  elif [ -f "$target" ]; then
    if [ "$symlink_failed" -eq 1 ]; then
      # Copy-fallback mode — check if content matches
      if cmp -s "$source" "$target"; then
        printf 'copy  ~/%s  (ok)\n' "$rel_target"
        skipped=$((skipped + 1))
        return
      fi
      rm -f "$target"
    else
      stamp="$(date +%Y%m%d-%H%M%S)"
      mv "$target" "$target.bak.$stamp"
      printf 'backup ~/%s -> ~/%s.bak.%s\n' "$rel_target" "$rel_target" "$stamp"
      backed_up=$((backed_up + 1))
    fi
  fi

  mkdir -p "$(dirname "$target")"

  if [ "$symlink_failed" -eq 0 ]; then
    ln -s "$source" "$target"
    printf 'link  ~/%s -> %s\n' "$rel_target" "$rel_source"
    symlinked=$((symlinked + 1))
  else
    cp "$source" "$target"
    printf 'copy  ~/%s <- %s\n' "$rel_target" "$rel_source"
    copied=$((copied + 1))
  fi
}

printf '\nGlobal symlinks:\n'

# Symlink commands
for file in "$SHARED_COMMANDS_DIR"/*.md; do
  [ -f "$file" ] || continue
  name="$(basename "$file" .md)"

  # OpenCode
  safe_symlink "$ROOT/.opencode/commands/$name.md" "$OPENCODE_GLOBAL/commands/$name.md"
  # Claude Code
  safe_symlink "$ROOT/.claude/commands/$name.md" "$CLAUDE_GLOBAL/commands/$name.md"
  # Cursor
  safe_symlink "$ROOT/.cursor/commands/$name.md" "$CURSOR_GLOBAL/commands/$name.md"
done

# Symlink MCP configs
if [ "$MCP_GENERATED" -eq 1 ]; then

  # Claude Code: merge mcpServers key into ~/.claude.json
  claude_json_path="$HOME/.claude.json"
  new_claude_json="$(node -e "
const fs = require('fs');
let existing = {};
try { existing = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); } catch {}
const mcp = JSON.parse(process.argv[2]);
existing.mcpServers = mcp.mcpServers;
console.log(JSON.stringify(existing, null, 2));
" "$claude_json_path" "$claude_mcp_json" 2>/dev/null || echo "$claude_mcp_json")"

  tmp_claude="$(mktemp)"
  printf '%s\n' "$new_claude_json" > "$tmp_claude"
  if [ -f "$claude_json_path" ] && cmp -s "$claude_json_path" "$tmp_claude"; then
    printf 'ok    ~/.claude.json\n'
    skipped=$((skipped + 1))
  else
    mv "$tmp_claude" "$claude_json_path"
    printf 'write ~/.claude.json\n'
    copied=$((copied + 1))
  fi
  rm -f "$tmp_claude" 2>/dev/null

  # Cursor: ~/.cursor/mcp.json (standalone, symlink/copy)
  safe_symlink "$ROOT/.cursor/mcp.json" "$CURSOR_GLOBAL/mcp.json"

  # VS Code: global user-level mcp.json
  safe_symlink "$ROOT/.vscode/mcp.json" "$VSCODE_GLOBAL/mcp.json"

  # OpenCode: merge mcp key into ~/.config/opencode/opencode.json
  oc_global_path="$OPENCODE_GLOBAL/opencode.json"
  new_oc_json="$(node -e "
const fs = require('fs');
let existing = {};
try { existing = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); } catch {}
existing.mcp = JSON.parse(process.argv[2]);
console.log(JSON.stringify(existing, null, 2));
" "$oc_global_path" "$opencode_mcp_json" 2>/dev/null || printf '{"mcp": %s}' "$opencode_mcp_json")"

  mkdir -p "$OPENCODE_GLOBAL"
  tmp_oc="$(mktemp)"
  printf '%s\n' "$new_oc_json" > "$tmp_oc"
  if [ -f "$oc_global_path" ] && cmp -s "$oc_global_path" "$tmp_oc"; then
    printf 'ok    ~/.config/opencode/opencode.json (mcp merged)\n'
    skipped=$((skipped + 1))
  else
    mv "$tmp_oc" "$oc_global_path"
    printf 'write ~/.config/opencode/opencode.json (mcp merged)\n'
    copied=$((copied + 1))
  fi
  rm -f "$tmp_oc" 2>/dev/null
fi

# Symlink agents
for file in "$SHARED_AGENTS_DIR"/*.md; do
  [ -f "$file" ] || continue
  name="$(basename "$file" .md)"

  # OpenCode
  safe_symlink "$ROOT/.opencode/agents/$name.md" "$OPENCODE_GLOBAL/agents/$name.md"
  # Claude Code
  safe_symlink "$ROOT/.claude/agents/$name.md" "$CLAUDE_GLOBAL/agents/$name.md"
  # Cursor
  safe_symlink "$ROOT/.cursor/agents/$name.md" "$CURSOR_GLOBAL/agents/$name.md"
done

# Symlink skills globally
for skill_dir in "${skill_dirs[@]}"; do
  name="$(basename "$skill_dir")"
  safe_symlink "$ROOT/.claude/skills/$name/SKILL.md"    "$CLAUDE_GLOBAL/skills/$name/SKILL.md"
  safe_symlink "$ROOT/.opencode/skills/$name/SKILL.md"  "$OPENCODE_GLOBAL/skills/$name/SKILL.md"
  safe_symlink "$ROOT/.cursor/skills/$name/SKILL.md"    "$CURSOR_GLOBAL/skills/$name/SKILL.md"
done

# ── VS Code: update global settings.json for agents + skills ─────────
if [ -d "$VSCODE_GLOBAL" ]; then
  vscode_settings_path="$VSCODE_GLOBAL/settings.json"
  if command -v node &>/dev/null; then
    _skills_arg=""
    [ "$skill_count" -gt 0 ] && _skills_arg="$ROOT/.github/skills"

    new_vscode_settings="$(node -e "
const fs = require('fs');
const [settingsPath, agentsPath, skillsPath] = process.argv.slice(1);
let existing = {};
try { existing = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); } catch {}
const key = 'chat.agentFilesLocations';
const arr = Array.isArray(existing[key]) ? [...existing[key]] : [];
if (!arr.includes(agentsPath)) arr.push(agentsPath);
existing[key] = arr;
if (skillsPath) {
  const key2 = 'chat.agentSkillsLocations';
  const arr2 = Array.isArray(existing[key2]) ? [...existing[key2]] : [];
  if (!arr2.includes(skillsPath)) arr2.push(skillsPath);
  existing[key2] = arr2;
}
console.log(JSON.stringify(existing, null, 2));
" "$vscode_settings_path" "$ROOT/.github/agents" "$_skills_arg")"
    if [ -n "$new_vscode_settings" ]; then
      tmp_vscode="$(mktemp)"
      printf '%s\n' "$new_vscode_settings" > "$tmp_vscode"
      if [ -f "$vscode_settings_path" ] && cmp -s "$vscode_settings_path" "$tmp_vscode"; then
        printf 'ok    ~/.../Code/User/settings.json (chat.agentFilesLocations)\n'
        skipped=$((skipped + 1))
      else
        mv "$tmp_vscode" "$vscode_settings_path"
        printf 'write ~/.../Code/User/settings.json (chat.agentFilesLocations)\n'
        copied=$((copied + 1))
      fi
      rm -f "$tmp_vscode" 2>/dev/null
    fi
  else
    printf 'skip  VS Code settings.json — node not found\n'
  fi
else
  printf 'skip  VS Code not found at %s\n' "$VSCODE_GLOBAL"
fi

printf '\nSymlink summary:\n'
if [ "$symlinked" -gt 0 ]; then
  printf -- '- linked: %s\n' "$symlinked"
fi
if [ "$copied" -gt 0 ]; then
  printf -- '- copied: %s\n' "$copied"
fi
printf -- '- unchanged: %s\n' "$skipped"
if [ "$backed_up" -gt 0 ]; then
  printf -- '- backed up: %s\n' "$backed_up"
fi
if [ "$symlink_failed" -eq 1 ]; then
  printf '\n'
  printf 'WARN: Symlinks were not available. Files were copied instead.\n'
  printf '      Copies will NOT auto-update when you re-generate. Re-run setup after changes.\n'
  printf '      To enable symlinks, activate Developer Mode in Windows Settings > For developers.\n'
fi

printf '\nGlobal deployment summary (all 4 tools):\n'
printf '\n'
printf '  OpenCode\n'
printf '    workspace : .opencode/commands  .opencode/agents  .opencode/skills\n'
printf '    global    : ~/.config/opencode/commands  agents  skills  (symlinked)\n'
printf '    MCP       : mcp key merged into ~/.config/opencode/opencode.json\n'
printf '\n'
printf '  Claude Code\n'
printf '    workspace : .claude/commands  .claude/agents  .claude/skills  .mcp.json\n'
printf '    global    : ~/.claude/commands  agents  skills  (symlinked)\n'
printf '    MCP       : mcpServers merged into ~/.claude.json\n'
printf '\n'
printf '  Cursor\n'
printf '    workspace : .cursor/commands  .cursor/agents  .cursor/skills  .cursor/mcp.json\n'
printf '    global    : ~/.cursor/commands  agents  skills  mcp.json  (symlinked)\n'
printf '\n'
printf '  VS Code Copilot\n'
printf '    workspace : .github/prompts  .github/agents  .github/skills  .vscode/mcp.json\n'
printf '    global MCP: ~/.config/Code/User/mcp.json  (symlinked)\n'
printf '    global agents/skills: ~/.config/Code/User/settings.json\n'
printf '      chat.agentFilesLocations  -> .github/agents\n'
[ "$skill_count" -gt 0 ] && printf '      chat.agentSkillsLocations -> .github/skills\n'
printf '\n'
printf '  All generated from the same canonical source in pack/shared/.\n'
