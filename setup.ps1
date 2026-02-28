$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$SharedCommandsDir = Join-Path $Root "pack/shared/commands"
$SharedAgentsDir   = Join-Path $Root "pack/shared/agents"
$SharedSkillsDir   = Join-Path $Root "pack/shared/skills"

function Quote-Yaml {
    param([string]$Value)

    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
}

function Test-RawYamlValue {
    param([string]$Value)

    if ($null -eq $Value) {
        return $false
    }

    $trimmed = $Value.Trim()
    if ($trimmed -match '^(true|false|null)$') {
        return $true
    }
    if ($trimmed -match '^-?[0-9]+(\.[0-9]+)?$') {
        return $true
    }
    if ($trimmed.StartsWith("[") -and $trimmed.EndsWith("]")) {
        $inner = $trimmed.Substring(1, $trimmed.Length - 2)
        if (
            $inner.Contains(",") -or
            $inner.Contains(":") -or
            $inner.Contains('"') -or
            $inner.Contains("'") -or
            $inner.Contains("{") -or
            $inner.Contains("[")
        ) {
            return $true
        }
    }

    if ($trimmed.StartsWith("{") -and $trimmed.EndsWith("}")) {
        $inner = $trimmed.Substring(1, $trimmed.Length - 2)
        if ($inner.Contains(":")) {
            return $true
        }
    }

    return $false
}

function Parse-CanonicalDoc {
    param([string]$Path)

    $raw = [System.IO.File]::ReadAllText($Path)
    $raw = $raw -replace "`r`n", "`n"

    $match = [regex]::Match($raw, '(?s)^---\n(.*?)\n---\n?(.*)$')
    if (-not $match.Success) {
        throw "${Path}: missing or invalid frontmatter"
    }

    $frontmatter = $match.Groups[1].Value
    $body = $match.Groups[2].Value.TrimEnd("`n")
    if ([string]::IsNullOrWhiteSpace($body)) {
        throw "${Path}: empty body"
    }

    $metadata = [ordered]@{}
    foreach ($line in ($frontmatter -split "`n")) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
            continue
        }

        $fmMatch = [regex]::Match($line, '^\s*([^:]+)\s*:\s*(.*)\s*$')
        if (-not $fmMatch.Success) {
            throw "${Path}: invalid frontmatter line: $line"
        }

        $key = $fmMatch.Groups[1].Value.Trim()
        $value = $fmMatch.Groups[2].Value.Trim()

        if ($value.Length -ge 2) {
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }

        $metadata[$key] = $value
    }

    $name = if ($metadata.Contains("name") -and -not [string]::IsNullOrWhiteSpace($metadata["name"])) {
        $metadata["name"]
    }
    else {
        [System.IO.Path]::GetFileNameWithoutExtension($Path)
    }

    $description = if ($metadata.Contains("description")) { $metadata["description"] } else { "" }
    $argumentHint = if ($metadata.Contains("argument-hint")) { $metadata["argument-hint"] } else { $null }

    if ([string]::IsNullOrWhiteSpace($description)) {
        throw "${Path}: missing description"
    }

    return [pscustomobject]@{
        Name = $name
        Description = $description
        ArgumentHint = $argumentHint
        Body = "$body`n"
        Metadata = $metadata
        Source = $Path
    }
}

function Resolve-AgentValue {
    param(
        [System.Collections.IDictionary]$Metadata,
        [string]$Tool,
        [string]$Field
    )

    $toolKey = "$Tool.$Field"
    if ($Metadata.Contains($toolKey)) {
        return [string]$Metadata[$toolKey]
    }

    $commonKey = "common.$Field"
    if ($Metadata.Contains($commonKey)) {
        return [string]$Metadata[$commonKey]
    }

    return $null
}

function Add-OptionalEntry {
    param(
        [ref]$Entries,
        [string]$Key,
        [string]$Value,
        [switch]$Raw
    )

    if ($null -eq $Value -or $Value -eq "") {
        return
    }

    $entry = @{ Key = $Key; Value = $Value }

    if ($Raw.IsPresent -or (Test-RawYamlValue -Value $Value)) {
        $entry.Raw = $true
    }

    $Entries.Value += $entry
}

function Add-ExtraEntries {
    param(
        [ref]$Entries,
        [System.Collections.IDictionary]$Metadata,
        [string]$Prefix
    )

    foreach ($key in $Metadata.Keys) {
        if ($key.StartsWith($Prefix, [System.StringComparison]::Ordinal)) {
            $field = $key.Substring($Prefix.Length)
            Add-OptionalEntry -Entries ([ref]$Entries.Value) -Key $field -Value ([string]$Metadata[$key])
        }
    }
}

function Build-Frontmatter {
    param([array]$Entries)

    $lines = @("---")
    foreach ($entry in $Entries) {
        if ($null -eq $entry.Value) {
            continue
        }

        if ($entry.ContainsKey("Raw") -and $entry.Raw) {
            $lines += "$($entry.Key): $($entry.Value)"
        }
        else {
            $lines += "$($entry.Key): $(Quote-Yaml ([string]$entry.Value))"
        }
    }
    $lines += "---"
    return ($lines -join "`n")
}

function With-Frontmatter {
    param(
        [array]$Entries,
        [string]$Body
    )

    $frontmatter = Build-Frontmatter -Entries $Entries
    return "$frontmatter`n`n$($Body.TrimEnd("`n"))`n"
}

function Write-IfChanged {
    param(
        [string]$Path,
        [string]$Content,
        [string]$RootPath,
        [ref]$Written,
        [ref]$Unchanged,
        [ref]$Total
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $status = "write"
    if (Test-Path -LiteralPath $Path) {
        $existing = [System.IO.File]::ReadAllText($Path)
        $existing = $existing -replace "`r`n", "`n"
        if ($existing -ceq $Content) {
            $status = "ok"
        }
    }

    if ($status -eq "write") {
        [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
        $Written.Value++
    }
    else {
        $Unchanged.Value++
    }
    $Total.Value++

    $rel = $Path
    if ($Path.StartsWith($RootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $Path.Substring($RootPath.Length).TrimStart([char]'\', [char]'/')
    }
    Write-Host ("{0,-5} {1}" -f $status, $rel)
}

$commandFiles = @()
if (Test-Path -LiteralPath $SharedCommandsDir) {
    $commandFiles = Get-ChildItem -LiteralPath $SharedCommandsDir -Filter "*.md" -File | Sort-Object Name
}

$agentFiles = @()
if (Test-Path -LiteralPath $SharedAgentsDir) {
    $agentFiles = Get-ChildItem -LiteralPath $SharedAgentsDir -Filter "*.md" -File | Sort-Object Name
}

$skillDirs = @()
if (Test-Path -LiteralPath $SharedSkillsDir) {
    $skillDirs = Get-ChildItem -LiteralPath $SharedSkillsDir -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName "SKILL.md")
    } | Sort-Object Name
}

if ($commandFiles.Count -eq 0 -and $agentFiles.Count -eq 0 -and $skillDirs.Count -eq 0) {
    Write-Error "Nothing to generate. Add canonical files in pack/shared/commands, pack/shared/agents, or pack/shared/skills/<name>/SKILL.md."
    exit 1
}

$outputs = New-Object System.Collections.Generic.List[object]

foreach ($file in $commandFiles) {
    $doc = Parse-CanonicalDoc -Path $file.FullName

    $meta = $doc.Metadata

    # Claude Code command/skill frontmatter
    $claudeEntries = @(
        @{ Key = "name"; Value = $doc.Name },
        @{ Key = "description"; Value = $doc.Description }
    )

    $claudeArgHint = Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "argument-hint"
    if ([string]::IsNullOrWhiteSpace($claudeArgHint)) {
        $claudeArgHint = $doc.ArgumentHint
    }
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "argument-hint" -Value $claudeArgHint

    $claudeDisableModelInvocation = Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "disable-model-invocation"
    if ([string]::IsNullOrWhiteSpace($claudeDisableModelInvocation)) {
        $claudeDisableModelInvocation = "true"
    }
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "disable-model-invocation" -Value $claudeDisableModelInvocation

    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "user-invocable" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "user-invocable")
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "allowed-tools" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "allowed-tools")
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "model" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "model")
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "context" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "context")
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "agent" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "agent")
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "hooks" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "hooks")
    Add-ExtraEntries -Entries ([ref]$claudeEntries) -Metadata $meta -Prefix "claude.extra."

    $outputs.Add([pscustomobject]@{
            Path = Join-Path $Root ".claude/commands/$($doc.Name).md"
            Content = With-Frontmatter -Entries $claudeEntries -Body $doc.Body
        })

    # Cursor command files are markdown-only
    $outputs.Add([pscustomobject]@{
            Path = Join-Path $Root ".cursor/commands/$($doc.Name).md"
            Content = "$($doc.Body.TrimEnd("`n"))`n"
        })

    # OpenCode command frontmatter
    $openCodeCommandEntries = @(
        @{ Key = "description"; Value = $doc.Description }
    )
    Add-OptionalEntry -Entries ([ref]$openCodeCommandEntries) -Key "agent" -Value (Resolve-AgentValue -Metadata $meta -Tool "opencode" -Field "agent")
    Add-OptionalEntry -Entries ([ref]$openCodeCommandEntries) -Key "subtask" -Value (Resolve-AgentValue -Metadata $meta -Tool "opencode" -Field "subtask")
    Add-OptionalEntry -Entries ([ref]$openCodeCommandEntries) -Key "model" -Value (Resolve-AgentValue -Metadata $meta -Tool "opencode" -Field "model")
    Add-ExtraEntries -Entries ([ref]$openCodeCommandEntries) -Metadata $meta -Prefix "opencode.extra."

    $outputs.Add([pscustomobject]@{
            Path = Join-Path $Root ".opencode/commands/$($doc.Name).md"
            Content = With-Frontmatter -Entries $openCodeCommandEntries -Body $doc.Body
        })

    # VS Code prompt file frontmatter
    $vsCodePromptEntries = @(
        @{ Key = "name"; Value = $doc.Name },
        @{ Key = "description"; Value = $doc.Description }
    )

    $vsCodeArgHint = Resolve-AgentValue -Metadata $meta -Tool "vscode" -Field "argument-hint"
    if ([string]::IsNullOrWhiteSpace($vsCodeArgHint)) {
        $vsCodeArgHint = $doc.ArgumentHint
    }
    Add-OptionalEntry -Entries ([ref]$vsCodePromptEntries) -Key "argument-hint" -Value $vsCodeArgHint

    $vsCodeAgent = Resolve-AgentValue -Metadata $meta -Tool "vscode" -Field "agent"
    if ([string]::IsNullOrWhiteSpace($vsCodeAgent)) {
        $vsCodeAgent = "agent"
    }
    Add-OptionalEntry -Entries ([ref]$vsCodePromptEntries) -Key "agent" -Value $vsCodeAgent

    Add-OptionalEntry -Entries ([ref]$vsCodePromptEntries) -Key "model" -Value (Resolve-AgentValue -Metadata $meta -Tool "vscode" -Field "model")
    Add-OptionalEntry -Entries ([ref]$vsCodePromptEntries) -Key "tools" -Value (Resolve-AgentValue -Metadata $meta -Tool "vscode" -Field "tools")
    Add-ExtraEntries -Entries ([ref]$vsCodePromptEntries) -Metadata $meta -Prefix "vscode.extra."

    $outputs.Add([pscustomobject]@{
            Path = Join-Path $Root ".github/prompts/$($doc.Name).prompt.md"
            Content = With-Frontmatter -Entries $vsCodePromptEntries -Body $doc.Body
        })
}

foreach ($file in $agentFiles) {
    $doc = Parse-CanonicalDoc -Path $file.FullName
    $meta = $doc.Metadata

    # Claude Code
    $claudeEntries = @(
        @{ Key = "name"; Value = $doc.Name },
        @{ Key = "description"; Value = $doc.Description }
    )
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "tools" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "tools")
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "disallowedTools" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "disallowedTools")
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "model" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "model")
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "permissionMode" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "permissionMode")
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "maxTurns" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "maxTurns")
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "mcpServers" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "mcpServers")
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "hooks" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "hooks")
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "memory" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "memory")
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "background" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "background")
    Add-OptionalEntry -Entries ([ref]$claudeEntries) -Key "isolation" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "isolation")
    Add-ExtraEntries -Entries ([ref]$claudeEntries) -Metadata $meta -Prefix "claude.extra."

    $agentBodyContent = With-Frontmatter -Entries $claudeEntries -Body $doc.Body
    $outputs.Add([pscustomobject]@{
            Path = Join-Path $Root ".claude/agents/$($doc.Name).md"
            Content = $agentBodyContent
        })

    # Cursor
    $cursorEntries = @(
        @{ Key = "name"; Value = $doc.Name },
        @{ Key = "description"; Value = $doc.Description }
    )
    Add-OptionalEntry -Entries ([ref]$cursorEntries) -Key "model" -Value (Resolve-AgentValue -Metadata $meta -Tool "cursor" -Field "model")
    Add-OptionalEntry -Entries ([ref]$cursorEntries) -Key "readonly" -Value (Resolve-AgentValue -Metadata $meta -Tool "cursor" -Field "readonly")
    Add-OptionalEntry -Entries ([ref]$cursorEntries) -Key "is_background" -Value (Resolve-AgentValue -Metadata $meta -Tool "cursor" -Field "is_background")
    Add-ExtraEntries -Entries ([ref]$cursorEntries) -Metadata $meta -Prefix "cursor.extra."

    $outputs.Add([pscustomobject]@{
            Path = Join-Path $Root ".cursor/agents/$($doc.Name).md"
            Content = With-Frontmatter -Entries $cursorEntries -Body $doc.Body
        })

    # OpenCode
    $openCodeEntries = @(
        @{ Key = "description"; Value = $doc.Description }
    )

    $opMode = Resolve-AgentValue -Metadata $meta -Tool "opencode" -Field "mode"
    if ([string]::IsNullOrWhiteSpace($opMode)) {
        $opMode = "subagent"
    }

    Add-OptionalEntry -Entries ([ref]$openCodeEntries) -Key "mode" -Value $opMode
    Add-OptionalEntry -Entries ([ref]$openCodeEntries) -Key "model" -Value (Resolve-AgentValue -Metadata $meta -Tool "opencode" -Field "model")
    Add-OptionalEntry -Entries ([ref]$openCodeEntries) -Key "temperature" -Value (Resolve-AgentValue -Metadata $meta -Tool "opencode" -Field "temperature")
    Add-OptionalEntry -Entries ([ref]$openCodeEntries) -Key "steps" -Value (Resolve-AgentValue -Metadata $meta -Tool "opencode" -Field "steps")
    Add-OptionalEntry -Entries ([ref]$openCodeEntries) -Key "disable" -Value (Resolve-AgentValue -Metadata $meta -Tool "opencode" -Field "disable")
    Add-OptionalEntry -Entries ([ref]$openCodeEntries) -Key "tools" -Value (Resolve-AgentValue -Metadata $meta -Tool "opencode" -Field "tools")
    Add-OptionalEntry -Entries ([ref]$openCodeEntries) -Key "permission" -Value (Resolve-AgentValue -Metadata $meta -Tool "opencode" -Field "permission")
    Add-OptionalEntry -Entries ([ref]$openCodeEntries) -Key "hidden" -Value (Resolve-AgentValue -Metadata $meta -Tool "opencode" -Field "hidden")
    Add-OptionalEntry -Entries ([ref]$openCodeEntries) -Key "color" -Value (Resolve-AgentValue -Metadata $meta -Tool "opencode" -Field "color")
    Add-OptionalEntry -Entries ([ref]$openCodeEntries) -Key "top_p" -Value (Resolve-AgentValue -Metadata $meta -Tool "opencode" -Field "top_p")
    Add-ExtraEntries -Entries ([ref]$openCodeEntries) -Metadata $meta -Prefix "opencode.extra."

    $outputs.Add([pscustomobject]@{
            Path = Join-Path $Root ".opencode/agents/$($doc.Name).md"
            Content = With-Frontmatter -Entries $openCodeEntries -Body $doc.Body
        })

    # VS Code Copilot
    $vsCodeEntries = @(
        @{ Key = "name"; Value = $doc.Name },
        @{ Key = "description"; Value = $doc.Description }
    )

    Add-OptionalEntry -Entries ([ref]$vsCodeEntries) -Key "argument-hint" -Value (Resolve-AgentValue -Metadata $meta -Tool "vscode" -Field "argument-hint")
    Add-OptionalEntry -Entries ([ref]$vsCodeEntries) -Key "tools" -Value (Resolve-AgentValue -Metadata $meta -Tool "vscode" -Field "tools")
    Add-OptionalEntry -Entries ([ref]$vsCodeEntries) -Key "agents" -Value (Resolve-AgentValue -Metadata $meta -Tool "vscode" -Field "agents")
    Add-OptionalEntry -Entries ([ref]$vsCodeEntries) -Key "model" -Value (Resolve-AgentValue -Metadata $meta -Tool "vscode" -Field "model")
    Add-OptionalEntry -Entries ([ref]$vsCodeEntries) -Key "user-invokable" -Value (Resolve-AgentValue -Metadata $meta -Tool "vscode" -Field "user-invokable")
    Add-OptionalEntry -Entries ([ref]$vsCodeEntries) -Key "disable-model-invocation" -Value (Resolve-AgentValue -Metadata $meta -Tool "vscode" -Field "disable-model-invocation")
    Add-OptionalEntry -Entries ([ref]$vsCodeEntries) -Key "target" -Value (Resolve-AgentValue -Metadata $meta -Tool "vscode" -Field "target")
    Add-OptionalEntry -Entries ([ref]$vsCodeEntries) -Key "mcp-servers" -Value (Resolve-AgentValue -Metadata $meta -Tool "vscode" -Field "mcp-servers")
    Add-OptionalEntry -Entries ([ref]$vsCodeEntries) -Key "handoffs" -Value (Resolve-AgentValue -Metadata $meta -Tool "vscode" -Field "handoffs")
    Add-ExtraEntries -Entries ([ref]$vsCodeEntries) -Metadata $meta -Prefix "vscode.extra."

    $outputs.Add([pscustomobject]@{
            Path = Join-Path $Root ".github/agents/$($doc.Name).agent.md"
            Content = With-Frontmatter -Entries $vsCodeEntries -Body $doc.Body
        })
}

# ── Skills generation ─────────────────────────────────────────────────
foreach ($skillDir in $skillDirs) {
    $skillFile = Join-Path $skillDir.FullName "SKILL.md"
    $doc  = Parse-CanonicalDoc -Path $skillFile
    $meta = $doc.Metadata
    $name = $doc.Name

    # Claude Code
    $claudeSkillEntries = @(
        @{ Key = "name";        Value = $name },
        @{ Key = "description"; Value = $doc.Description }
    )
    Add-OptionalEntry -Entries ([ref]$claudeSkillEntries) -Key "allowed-tools"            -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "allowed-tools")
    Add-OptionalEntry -Entries ([ref]$claudeSkillEntries) -Key "disable-model-invocation" -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "disable-model-invocation")
    Add-OptionalEntry -Entries ([ref]$claudeSkillEntries) -Key "model"                    -Value (Resolve-AgentValue -Metadata $meta -Tool "claude" -Field "model")
    Add-ExtraEntries  -Entries ([ref]$claudeSkillEntries) -Metadata $meta -Prefix "claude.extra."
    $outputs.Add([pscustomobject]@{
        Path    = Join-Path $Root ".claude/skills/$name/SKILL.md"
        Content = With-Frontmatter -Entries $claudeSkillEntries -Body $doc.Body
    })

    # Cursor
    $cursorSkillEntries = @(
        @{ Key = "name";        Value = $name },
        @{ Key = "description"; Value = $doc.Description }
    )
    Add-ExtraEntries -Entries ([ref]$cursorSkillEntries) -Metadata $meta -Prefix "cursor.extra."
    $outputs.Add([pscustomobject]@{
        Path    = Join-Path $Root ".cursor/skills/$name/SKILL.md"
        Content = With-Frontmatter -Entries $cursorSkillEntries -Body $doc.Body
    })

    # OpenCode
    $openCodeSkillEntries = @(
        @{ Key = "name";        Value = $name },
        @{ Key = "description"; Value = $doc.Description }
    )
    Add-OptionalEntry -Entries ([ref]$openCodeSkillEntries) -Key "permission" -Value (Resolve-AgentValue -Metadata $meta -Tool "opencode" -Field "permission")
    Add-ExtraEntries  -Entries ([ref]$openCodeSkillEntries) -Metadata $meta -Prefix "opencode.extra."
    $outputs.Add([pscustomobject]@{
        Path    = Join-Path $Root ".opencode/skills/$name/SKILL.md"
        Content = With-Frontmatter -Entries $openCodeSkillEntries -Body $doc.Body
    })

    # VS Code (.github/skills/)
    $vsCodeSkillEntries = @(
        @{ Key = "name";        Value = $name },
        @{ Key = "description"; Value = $doc.Description }
    )
    Add-OptionalEntry -Entries ([ref]$vsCodeSkillEntries) -Key "user-invokable"            -Value (Resolve-AgentValue -Metadata $meta -Tool "vscode" -Field "user-invokable")
    Add-OptionalEntry -Entries ([ref]$vsCodeSkillEntries) -Key "disable-model-invocation"  -Value (Resolve-AgentValue -Metadata $meta -Tool "vscode" -Field "disable-model-invocation")
    Add-ExtraEntries  -Entries ([ref]$vsCodeSkillEntries) -Metadata $meta -Prefix "vscode.extra."
    $outputs.Add([pscustomobject]@{
        Path    = Join-Path $Root ".github/skills/$name/SKILL.md"
        Content = With-Frontmatter -Entries $vsCodeSkillEntries -Body $doc.Body
    })
}

# ── MCP config generation ────────────────────────────────────────────
$SharedMcpFile = Join-Path $Root "pack/shared/mcp.json"
if (Test-Path -LiteralPath $SharedMcpFile) {
    $mcpRaw = [System.IO.File]::ReadAllText($SharedMcpFile) | ConvertFrom-Json

    # ── Build per-tool MCP configs ───────────────────────────────────────────
    # Canonical type: "stdio" (local subprocess) | "http" (streamable HTTP) | "sse" (legacy SSE)
    # Inferred: explicit "type" field > "url" present → "http" > default "stdio"
    $claudeMcp   = [ordered]@{}
    $cursorMcp   = [ordered]@{}
    $vscodeMcp   = [ordered]@{}
    $opencodeMcp = [ordered]@{}

    foreach ($prop in $mcpRaw.PSObject.Properties) {
        $server = $prop.Value
        $name   = $prop.Name

        $canonType = if ($null -ne $server.type -and "$($server.type)".Trim() -ne "") {
            "$($server.type)".Trim()
        } elseif ($null -ne $server.url) {
            "http"
        } else {
            "stdio"
        }

        if ($canonType -eq "stdio") {
            # ── Local subprocess ─────────────────────────────────────────────
            # Claude Code / Cursor / VS Code: command (string) + args (array) + env
            $entry = [ordered]@{}
            if ($null -ne $server.command) { $entry["command"] = $server.command }
            if ($null -ne $server.args)    { $entry["args"] = @($server.args) }
            if ($null -ne $server.env) {
                $envObj = [ordered]@{}
                foreach ($e in $server.env.PSObject.Properties) { $envObj[$e.Name] = $e.Value }
                $entry["env"] = $envObj
            }
            $claudeMcp[$name] = $entry
            $cursorMcp[$name] = $entry  # identical for stdio
            $vscodeMcp[$name] = $entry  # identical for stdio

            # OpenCode: type="local", command=[cmd, ...args], environment
            $cmdArray = @()
            if ($null -ne $server.command) { $cmdArray += $server.command }
            if ($null -ne $server.args)    { $cmdArray += @($server.args) }
            $ocEntry = [ordered]@{ type = "local"; command = $cmdArray }
            if ($null -ne $server.env) {
                $envObj = [ordered]@{}
                foreach ($e in $server.env.PSObject.Properties) { $envObj[$e.Name] = $e.Value }
                $ocEntry["environment"] = $envObj
            }
            $opencodeMcp[$name] = $ocEntry
        } else {
            # ── Remote server: http or sse ───────────────────────────────────
            $hObj = $null
            if ($null -ne $server.headers) {
                $hObj = [ordered]@{}
                foreach ($h in $server.headers.PSObject.Properties) { $hObj[$h.Name] = $h.Value }
            }

            # Claude Code / VS Code: explicit type ("http" or "sse"), url, headers
            $entry = [ordered]@{ type = $canonType }
            if ($null -ne $server.url) { $entry["url"] = $server.url }
            if ($null -ne $hObj)       { $entry["headers"] = $hObj }
            $claudeMcp[$name] = $entry
            $vscodeMcp[$name] = $entry  # same format as Claude Code

            # Cursor: no type field (transport auto-detected from url), url, headers
            $cursorEntry = [ordered]@{}
            if ($null -ne $server.url) { $cursorEntry["url"] = $server.url }
            if ($null -ne $hObj)       { $cursorEntry["headers"] = $hObj }
            $cursorMcp[$name] = $cursorEntry

            # OpenCode: type="remote" (single value for all remote transports), url, headers
            $ocEntry = [ordered]@{ type = "remote" }
            if ($null -ne $server.url) { $ocEntry["url"] = $server.url }
            if ($null -ne $hObj)       { $ocEntry["headers"] = $hObj }
            $opencodeMcp[$name] = $ocEntry
        }
    }

    $claudeMcpJson = (@{ mcpServers = $claudeMcp } | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
    $cursorMcpJson = (@{ mcpServers = $cursorMcp } | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
    $vscodeMcpJson = (@{ servers    = $vscodeMcp } | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"

    # Project-level outputs
    $outputs.Add([pscustomobject]@{
        Path    = Join-Path $Root ".mcp.json"
        Content = "$claudeMcpJson`n"
    })
    $outputs.Add([pscustomobject]@{
        Path    = Join-Path $Root ".cursor/mcp.json"
        Content = "$cursorMcpJson`n"
    })
    $outputs.Add([pscustomobject]@{
        Path    = Join-Path $Root ".vscode/mcp.json"
        Content = "$vscodeMcpJson`n"
    })
}

$written = 0
$unchanged = 0
$total = 0

foreach ($output in ($outputs | Sort-Object Path)) {
    Write-IfChanged -Path $output.Path -Content $output.Content -RootPath $Root -Written ([ref]$written) -Unchanged ([ref]$unchanged) -Total ([ref]$total)
}

Write-Host ""
Write-Host "Generated files: $total"
Write-Host "- written: $written"
Write-Host "- unchanged: $unchanged"

# ── Global symlinks ──────────────────────────────────────────────────

$HomePath = $HOME
$OpenCodeGlobal = Join-Path $HomePath ".config/opencode"
$ClaudeGlobal = Join-Path $HomePath ".claude"
$CursorGlobal = Join-Path $HomePath ".cursor"
$VSCodeGlobal = Join-Path $env:APPDATA "Code/User"

$symlinked = 0
$copied = 0
$linkSkipped = 0
$backedUp = 0

# Probe: test if symlinks are available on this system
$symlinkFailed = $false
$probeSource = Join-Path $Root ".gitignore"
$probeTarget = Join-Path $env:TEMP "smartlink_symlink_probe_$([System.IO.Path]::GetRandomFileName())"
try {
    New-Item -ItemType SymbolicLink -Path $probeTarget -Target $probeSource -Force -ErrorAction Stop | Out-Null
    Remove-Item -LiteralPath $probeTarget -Force -ErrorAction SilentlyContinue
}
catch {
    $symlinkFailed = $true
    Write-Host "WARN  Symlinks require admin or Developer Mode. Falling back to copy."
}

function Safe-Symlink {
    param(
        [string]$Source,
        [string]$Target
    )

    $relSource = $Source
    if ($Source.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relSource = $Source.Substring($Root.Length).TrimStart([char]'\', [char]'/')
    }
    $relTarget = $Target
    if ($Target.StartsWith($HomePath, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relTarget = $Target.Substring($HomePath.Length).TrimStart([char]'\', [char]'/')
    }

    $item = $null
    if (Test-Path -LiteralPath $Target) {
        $item = Get-Item -LiteralPath $Target -Force
    }

    if ($null -ne $item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        # It's a symlink — check where it points
        $existingLink = $item.Target
        # Normalize for comparison
        $normalizedSource = $Source.Replace('/', '\')
        $normalizedExisting = if ($null -ne $existingLink) { $existingLink.Replace('/', '\') } else { "" }
        if ($normalizedExisting -eq $normalizedSource) {
            Write-Host ("link  ~/{0}  (ok)" -f $relTarget)
            $script:linkSkipped++
            return
        }
        # Symlink points elsewhere — remove it (no backup needed for symlinks)
        Remove-Item -LiteralPath $Target -Force
    }
    elseif ($null -ne $item) {
        # Regular file — check if content already matches (idempotent copy)
        if (-not $script:symlinkFailed) {
            # First time: might still succeed with symlink, so back up
            $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $backupPath = "$Target.bak.$stamp"
            Move-Item -LiteralPath $Target -Destination $backupPath -Force
            Write-Host ("backup ~/{0} -> ~/{0}.bak.{1}" -f $relTarget, $stamp)
            $script:backedUp++
        }
        else {
            # We're in copy-fallback mode — check if content matches
            $sourceContent = [System.IO.File]::ReadAllText($Source) -replace "`r`n", "`n"
            $targetContent = [System.IO.File]::ReadAllText($Target) -replace "`r`n", "`n"
            if ($sourceContent -ceq $targetContent) {
                Write-Host ("copy  ~/{0}  (ok)" -f $relTarget)
                $script:linkSkipped++
                return
            }
            Remove-Item -LiteralPath $Target -Force
        }
    }

    $parent = Split-Path -Parent $Target
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (-not $script:symlinkFailed) {
        New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force | Out-Null
        Write-Host ("link  ~/{0} -> {1}" -f $relTarget, $relSource)
        $script:symlinked++
    }
    else {
        Copy-Item -LiteralPath $Source -Destination $Target -Force
        Write-Host ("copy  ~/{0} <- {1}" -f $relTarget, $relSource)
        $script:copied++
    }
}

Write-Host ""
Write-Host "Global symlinks:"

# Symlink commands
foreach ($file in $commandFiles) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

    # OpenCode
    Safe-Symlink -Source (Join-Path $Root ".opencode/commands/$name.md") -Target (Join-Path $OpenCodeGlobal "commands/$name.md")
    # Claude Code
    Safe-Symlink -Source (Join-Path $Root ".claude/commands/$name.md") -Target (Join-Path $ClaudeGlobal "commands/$name.md")
    # Cursor
    Safe-Symlink -Source (Join-Path $Root ".cursor/commands/$name.md") -Target (Join-Path $CursorGlobal "commands/$name.md")
}

# Helper: convert PSCustomObject to ordered hashtable (PS 5.1 compat)
# Defined here so it is available for both MCP merge and VS Code settings update.
function ConvertTo-OrderedHash {
    param($InputObject)
    if ($null -eq $InputObject) { return [ordered]@{} }
    $hash = [ordered]@{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        if ($prop.Value -is [System.Management.Automation.PSCustomObject]) {
            $hash[$prop.Name] = ConvertTo-OrderedHash $prop.Value
        } elseif ($prop.Value -is [System.Array]) {
            $hash[$prop.Name] = @($prop.Value)
        } else {
            $hash[$prop.Name] = $prop.Value
        }
    }
    return $hash
}

# Symlink MCP configs
if (Test-Path -LiteralPath $SharedMcpFile) {

    # Claude Code: .mcp.json is project-only, global goes into ~/.claude.json mcpServers key
    $claudeJsonPath = Join-Path $HomePath ".claude.json"
    $claudeJsonObj = [ordered]@{}
    if (Test-Path -LiteralPath $claudeJsonPath) {
        $parsed = [System.IO.File]::ReadAllText($claudeJsonPath) | ConvertFrom-Json
        $claudeJsonObj = ConvertTo-OrderedHash $parsed
    }
    $claudeJsonObj["mcpServers"] = $claudeMcp
    $newClaudeJson = ($claudeJsonObj | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
    $newClaudeJson = "$newClaudeJson`n"
    $claudeJsonStatus = "write"
    if (Test-Path -LiteralPath $claudeJsonPath) {
        $existClaudeJson = ([System.IO.File]::ReadAllText($claudeJsonPath)) -replace "`r`n", "`n"
        if ($existClaudeJson -ceq $newClaudeJson) { $claudeJsonStatus = "ok" }
    }
    if ($claudeJsonStatus -eq "write") {
        [System.IO.File]::WriteAllText($claudeJsonPath, $newClaudeJson, [System.Text.UTF8Encoding]::new($false))
    }
    $relClaude = ".claude.json"
    Write-Host ("{0,-5} ~/{1}" -f $claudeJsonStatus, $relClaude)
    if ($claudeJsonStatus -eq "write") { $script:copied++ } else { $script:linkSkipped++ }

    # Cursor: ~/.cursor/mcp.json (standalone, symlink/copy)
    Safe-Symlink -Source (Join-Path $Root ".cursor/mcp.json") -Target (Join-Path $CursorGlobal "mcp.json")

    # VS Code: %APPDATA%/Code/User/mcp.json (standalone, symlink/copy)
    Safe-Symlink -Source (Join-Path $Root ".vscode/mcp.json") -Target (Join-Path $VSCodeGlobal "mcp.json")

    # OpenCode: merge mcp key into ~/.config/opencode/opencode.json
    $ocGlobalPath = Join-Path $OpenCodeGlobal "opencode.json"
    $ocObj = [ordered]@{}
    if (Test-Path -LiteralPath $ocGlobalPath) {
        $parsed = [System.IO.File]::ReadAllText($ocGlobalPath) | ConvertFrom-Json
        $ocObj = ConvertTo-OrderedHash $parsed
    }
    $ocObj["mcp"] = $opencodeMcp
    $newOcJson = ($ocObj | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
    $newOcJson = "$newOcJson`n"
    $ocStatus = "write"
    if (Test-Path -LiteralPath $ocGlobalPath) {
        $existOcJson = ([System.IO.File]::ReadAllText($ocGlobalPath)) -replace "`r`n", "`n"
        if ($existOcJson -ceq $newOcJson) { $ocStatus = "ok" }
    }
    if ($ocStatus -eq "write") {
        [System.IO.File]::WriteAllText($ocGlobalPath, $newOcJson, [System.Text.UTF8Encoding]::new($false))
    }
    $relOc = ".config/opencode/opencode.json (mcp merged)"
    Write-Host ("{0,-5} ~/{1}" -f $ocStatus, $relOc)
    if ($ocStatus -eq "write") { $script:copied++ } else { $script:linkSkipped++ }
}

# Symlink agents
foreach ($file in $agentFiles) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

    # OpenCode
    Safe-Symlink -Source (Join-Path $Root ".opencode/agents/$name.md") -Target (Join-Path $OpenCodeGlobal "agents/$name.md")
    # Claude Code
    Safe-Symlink -Source (Join-Path $Root ".claude/agents/$name.md") -Target (Join-Path $ClaudeGlobal "agents/$name.md")
    # Cursor
    Safe-Symlink -Source (Join-Path $Root ".cursor/agents/$name.md") -Target (Join-Path $CursorGlobal "agents/$name.md")
}

# Symlink skills globally
foreach ($skillDir in $skillDirs) {
    $name = $skillDir.Name
    Safe-Symlink -Source (Join-Path $Root ".claude/skills/$name/SKILL.md")    -Target (Join-Path $ClaudeGlobal    "skills/$name/SKILL.md")
    Safe-Symlink -Source (Join-Path $Root ".opencode/skills/$name/SKILL.md")  -Target (Join-Path $OpenCodeGlobal  "skills/$name/SKILL.md")
    Safe-Symlink -Source (Join-Path $Root ".cursor/skills/$name/SKILL.md")    -Target (Join-Path $CursorGlobal    "skills/$name/SKILL.md")
}

# ── VS Code: update global settings.json for agents + skills ─────────
if (Test-Path -LiteralPath $VSCodeGlobal) {
    $vsCodeSettingsPath = Join-Path $VSCodeGlobal "settings.json"
    $vsCodeSettingsObj  = [ordered]@{}
    $vsCodeSettingsOk   = $true

    if (Test-Path -LiteralPath $vsCodeSettingsPath) {
        try {
            $parsed = [System.IO.File]::ReadAllText($vsCodeSettingsPath) | ConvertFrom-Json
            $vsCodeSettingsObj = ConvertTo-OrderedHash $parsed
        } catch {
            Write-Host "WARN  Could not parse VS Code settings.json — skipping settings update."
            $vsCodeSettingsOk = $false
        }
    }

    if ($vsCodeSettingsOk) {
        # chat.agentFilesLocations — add .github/agents as a persistent global source
        $agentLocKey = "chat.agentFilesLocations"
        $agentLocArr = @()
        if ($vsCodeSettingsObj.Contains($agentLocKey)) {
            $existing = $vsCodeSettingsObj[$agentLocKey]
            if ($existing -is [System.Array] -or $existing -is [System.Collections.IEnumerable]) {
                $agentLocArr = @($existing | ForEach-Object { "$_" })
            }
        }
        $githubAgentsPath = (Join-Path $Root ".github" "agents").Replace('\', '/')
        if ($agentLocArr -notcontains $githubAgentsPath) {
            $agentLocArr += $githubAgentsPath
        }
        $vsCodeSettingsObj[$agentLocKey] = $agentLocArr

        # chat.agentSkillsLocations — add .github/skills if skills are present
        if ($skillDirs.Count -gt 0) {
            $skillLocKey = "chat.agentSkillsLocations"
            $skillLocArr = @()
            if ($vsCodeSettingsObj.Contains($skillLocKey)) {
                $existing = $vsCodeSettingsObj[$skillLocKey]
                if ($existing -is [System.Array] -or $existing -is [System.Collections.IEnumerable]) {
                    $skillLocArr = @($existing | ForEach-Object { "$_" })
                }
            }
            $githubSkillsPath = (Join-Path $Root ".github" "skills").Replace('\', '/')
            if ($skillLocArr -notcontains $githubSkillsPath) {
                $skillLocArr += $githubSkillsPath
            }
            $vsCodeSettingsObj[$skillLocKey] = $skillLocArr
        }

        $newVsCodeSettings = ($vsCodeSettingsObj | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
        $newVsCodeSettings = "$newVsCodeSettings`n"
        $vsCodeSettingsStatus = "write"
        if (Test-Path -LiteralPath $vsCodeSettingsPath) {
            $existVsCode = ([System.IO.File]::ReadAllText($vsCodeSettingsPath)) -replace "`r`n", "`n"
            if ($existVsCode -ceq $newVsCodeSettings) { $vsCodeSettingsStatus = "ok" }
        }
        if ($vsCodeSettingsStatus -eq "write") {
            [System.IO.File]::WriteAllText($vsCodeSettingsPath, $newVsCodeSettings, [System.Text.UTF8Encoding]::new($false))
        }
        Write-Host ("{0,-5} %APPDATA%/Code/User/settings.json (chat.agentFilesLocations)" -f $vsCodeSettingsStatus)
        if ($vsCodeSettingsStatus -eq "write") { $script:copied++ } else { $script:linkSkipped++ }
    }
} else {
    Write-Host "skip  VS Code not found at $VSCodeGlobal"
}

Write-Host ""
Write-Host "Symlink summary:"
if ($symlinked -gt 0) {
    Write-Host "- linked: $symlinked"
}
if ($copied -gt 0) {
    Write-Host "- copied: $copied"
}
Write-Host "- unchanged: $linkSkipped"
if ($backedUp -gt 0) {
    Write-Host "- backed up: $backedUp"
}
if ($symlinkFailed) {
    Write-Host ""
    Write-Host "WARN: Symlinks were not available. Files were copied instead."
    Write-Host "      Copies will NOT auto-update when you re-generate. Re-run setup after changes."
    Write-Host "      To enable symlinks, activate Developer Mode in Windows Settings > For developers."
}

Write-Host ""
Write-Host "Global deployment summary (all 4 tools):"
Write-Host ""
Write-Host "  OpenCode"
Write-Host "    workspace : .opencode/commands  .opencode/agents  .opencode/skills"
Write-Host "    global    : ~/.config/opencode/commands  agents  skills  (symlinked)"
Write-Host "    MCP       : mcp key merged into ~/.config/opencode/opencode.json"
Write-Host ""
Write-Host "  Claude Code"
Write-Host "    workspace : .claude/commands  .claude/agents  .claude/skills  .mcp.json"
Write-Host "    global    : ~/.claude/commands  agents  skills  (symlinked)"
Write-Host "    MCP       : mcpServers merged into ~/.claude.json"
Write-Host ""
Write-Host "  Cursor"
Write-Host "    workspace : .cursor/commands  .cursor/agents  .cursor/skills  .cursor/mcp.json"
Write-Host "    global    : ~/.cursor/commands  agents  skills  mcp.json  (symlinked)"
Write-Host ""
Write-Host "  VS Code Copilot"
Write-Host "    workspace : .github/prompts  .github/agents  .github/skills  .vscode/mcp.json"
Write-Host "    global MCP: %APPDATA%/Code/User/mcp.json  (symlinked)"
Write-Host "    global agents/skills: %APPDATA%/Code/User/settings.json"
Write-Host "      chat.agentFilesLocations  -> .github/agents"
if ($skillDirs.Count -gt 0) {
Write-Host "      chat.agentSkillsLocations -> .github/skills"
}
Write-Host ""
Write-Host "  All generated from the same canonical source in pack/shared/."
