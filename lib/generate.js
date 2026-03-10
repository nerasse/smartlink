import fs from "node:fs/promises";
import path from "node:path";

function trim(value) {
  return value.trim();
}

function stripQuotes(value) {
  if (value.length >= 2) {
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      return value.slice(1, -1);
    }
  }

  return value;
}

function trimTrailingNewlines(value) {
  return value.replace(/\n+$/u, "");
}

function yamlQuote(value) {
  return `"${value.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
}

function yamlScalarAuto(value) {
  if (/^(true|false|null)$/u.test(value)) {
    return value;
  }

  if (/^-?[0-9]+(?:\.[0-9]+)?$/u.test(value)) {
    return value;
  }

  if (value.startsWith("[") && value.endsWith("]")) {
    const inner = value.slice(1, -1);
    if (/[,:"'\[{]/u.test(inner)) {
      return value;
    }
  }

  if (value.startsWith("{") && value.endsWith("}")) {
    const inner = value.slice(1, -1);
    if (inner.includes(":")) {
      return value;
    }
  }

  return yamlQuote(value);
}

function appendYamlField(lines, key, value) {
  if (value === undefined || value === null || value === "") {
    return;
  }

  lines.push(`${key}: ${yamlScalarAuto(String(value))}`);
}

function appendExtraFields(lines, metadata, prefix) {
  for (const [key, value] of metadata.entries()) {
    if (key.startsWith(prefix)) {
      appendYamlField(lines, key.slice(prefix.length), value);
    }
  }
}

function buildFrontmatter(lines) {
  return `---\n${lines.join("\n")}\n---`;
}

function resolveValue(metadata, tool, field) {
  return metadata.get(`${tool}.${field}`) ?? metadata.get(`common.${field}`) ?? "";
}

async function exists(targetPath) {
  try {
    await fs.access(targetPath);
    return true;
  } catch {
    return false;
  }
}

async function writeIfChanged(root, targetPath, content, stats, dryRun) {
  const relativePath = path.relative(root, targetPath) || path.basename(targetPath);
  const current = (await exists(targetPath)) ? await fs.readFile(targetPath, "utf8") : null;

  if (current === content) {
    console.log(`ok    ${relativePath}`);
    stats.unchanged += 1;
    stats.total += 1;
    return;
  }

  console.log(`${dryRun ? "plan " : "write "}${relativePath}`);
  stats.written += 1;
  stats.total += 1;

  if (dryRun) {
    return;
  }

  await fs.mkdir(path.dirname(targetPath), { recursive: true });
  await fs.writeFile(targetPath, content, "utf8");
}

async function parseCanonicalDoc(filePath) {
  const raw = (await fs.readFile(filePath, "utf8")).replace(/\r\n/g, "\n");
  const match = raw.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/u);

  if (!match) {
    throw new Error(`${filePath}: missing or invalid frontmatter`);
  }

  const [, frontmatter, rawBody] = match;
  const metadata = new Map();

  for (const line of frontmatter.split("\n")) {
    const stripped = trim(line);
    if (!stripped || stripped.startsWith("#")) {
      continue;
    }

    const separator = line.indexOf(":");
    if (separator === -1) {
      throw new Error(`${filePath}: invalid frontmatter line: ${line}`);
    }

    const key = trim(line.slice(0, separator));
    const value = stripQuotes(trim(line.slice(separator + 1)));
    metadata.set(key, value);
  }

  const name = metadata.get("name") || path.basename(filePath, ".md");
  const description = metadata.get("description") || "";
  const argumentHint = metadata.get("argument-hint") || "";
  const body = `${trimTrailingNewlines(rawBody)}\n`;

  if (!description) {
    throw new Error(`${filePath}: missing description`);
  }

  if (!trimTrailingNewlines(rawBody)) {
    throw new Error(`${filePath}: empty body`);
  }

  return { name, description, argumentHint, body, metadata };
}

async function readSortedFiles(dirPath, predicate = () => true) {
  try {
    const entries = await fs.readdir(dirPath, { withFileTypes: true });
    return entries
      .filter(predicate)
      .map((entry) => path.join(dirPath, entry.name))
      .sort((left, right) => left.localeCompare(right));
  } catch {
    return [];
  }
}

async function readPackManifest(packRoot) {
  const manifestPath = path.join(packRoot, "pack.json");
  let manifest = {};

  if (await exists(manifestPath)) {
    manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));
  }

  const name = String(manifest.name || path.basename(packRoot)).trim();
  const title = String(manifest.title || name).trim();
  const description = String(manifest.description || "").trim();

  return {
    name,
    title,
    description,
    workspaceOnly: manifest.workspaceOnly !== false,
  };
}

export async function discoverPackCatalog(sourceRoot) {
  const packsRoot = path.join(sourceRoot, "pack");
  const packDirs = await readSortedFiles(packsRoot, (entry) => entry.isDirectory());
  const packs = [];

  for (const packRoot of packDirs) {
    const manifest = await readPackManifest(packRoot);
    packs.push({
      ...manifest,
      packRoot,
      isShared: manifest.name === "shared",
    });
  }

  return packs;
}

export async function discoverPackResources(packRoot) {
  const commandsDir = path.join(packRoot, "commands");
  const agentsDir = path.join(packRoot, "agents");
  const skillsDir = path.join(packRoot, "skills");

  const commandFiles = await readSortedFiles(commandsDir, (entry) => entry.isFile() && entry.name.endsWith(".md"));
  const agentFiles = await readSortedFiles(agentsDir, (entry) => entry.isFile() && entry.name.endsWith(".md"));
  const skillDirs = await readSortedFiles(skillsDir, (entry) => entry.isDirectory());
  const skillFiles = [];

  for (const skillDir of skillDirs) {
    const skillFile = path.join(skillDir, "SKILL.md");
    if (await exists(skillFile)) {
      skillFiles.push(skillFile);
    }
  }

  return {
    commandFiles,
    agentFiles,
    skillFiles,
    mcpFile: path.join(packRoot, "mcp.json"),
  };
}

export async function discoverResources(root) {
  return discoverPackResources(path.join(root, "pack", "shared"));
}

function renderCommand(doc) {
  const claudeLines = [
    `name: ${yamlQuote(doc.name)}`,
    `description: ${yamlQuote(doc.description)}`,
  ];
  appendYamlField(claudeLines, "argument-hint", resolveValue(doc.metadata, "claude", "argument-hint") || doc.argumentHint);
  appendYamlField(claudeLines, "disable-model-invocation", resolveValue(doc.metadata, "claude", "disable-model-invocation") || "true");
  appendYamlField(claudeLines, "user-invocable", resolveValue(doc.metadata, "claude", "user-invocable"));
  appendYamlField(claudeLines, "allowed-tools", resolveValue(doc.metadata, "claude", "allowed-tools"));
  appendYamlField(claudeLines, "model", resolveValue(doc.metadata, "claude", "model"));
  appendYamlField(claudeLines, "context", resolveValue(doc.metadata, "claude", "context"));
  appendYamlField(claudeLines, "agent", resolveValue(doc.metadata, "claude", "agent"));
  appendYamlField(claudeLines, "hooks", resolveValue(doc.metadata, "claude", "hooks"));
  appendExtraFields(claudeLines, doc.metadata, "claude.extra.");

  const opencodeLines = [`description: ${yamlQuote(doc.description)}`];
  appendYamlField(opencodeLines, "agent", resolveValue(doc.metadata, "opencode", "agent"));
  appendYamlField(opencodeLines, "subtask", resolveValue(doc.metadata, "opencode", "subtask"));
  appendYamlField(opencodeLines, "model", resolveValue(doc.metadata, "opencode", "model"));
  appendExtraFields(opencodeLines, doc.metadata, "opencode.extra.");

  const vscodeLines = [
    `name: ${yamlQuote(doc.name)}`,
    `description: ${yamlQuote(doc.description)}`,
  ];
  appendYamlField(vscodeLines, "argument-hint", resolveValue(doc.metadata, "vscode", "argument-hint") || doc.argumentHint);
  appendYamlField(vscodeLines, "agent", resolveValue(doc.metadata, "vscode", "agent") || "agent");
  appendYamlField(vscodeLines, "model", resolveValue(doc.metadata, "vscode", "model"));
  appendYamlField(vscodeLines, "tools", resolveValue(doc.metadata, "vscode", "tools"));
  appendExtraFields(vscodeLines, doc.metadata, "vscode.extra.");

  return {
    [`.claude/commands/${doc.name}.md`]: `${buildFrontmatter(claudeLines)}\n\n${doc.body}`,
    [`.cursor/commands/${doc.name}.md`]: doc.body,
    [`.opencode/commands/${doc.name}.md`]: `${buildFrontmatter(opencodeLines)}\n\n${doc.body}`,
    [`.github/prompts/${doc.name}.prompt.md`]: `${buildFrontmatter(vscodeLines)}\n\n${doc.body}`,
  };
}

function renderAgent(doc) {
  const claudeLines = [
    `name: ${yamlQuote(doc.name)}`,
    `description: ${yamlQuote(doc.description)}`,
  ];
  appendYamlField(claudeLines, "tools", resolveValue(doc.metadata, "claude", "tools"));
  appendYamlField(claudeLines, "disallowedTools", resolveValue(doc.metadata, "claude", "disallowedTools"));
  appendYamlField(claudeLines, "model", resolveValue(doc.metadata, "claude", "model"));
  appendYamlField(claudeLines, "permissionMode", resolveValue(doc.metadata, "claude", "permissionMode"));
  appendYamlField(claudeLines, "maxTurns", resolveValue(doc.metadata, "claude", "maxTurns"));
  appendYamlField(claudeLines, "mcpServers", resolveValue(doc.metadata, "claude", "mcpServers"));
  appendYamlField(claudeLines, "hooks", resolveValue(doc.metadata, "claude", "hooks"));
  appendYamlField(claudeLines, "memory", resolveValue(doc.metadata, "claude", "memory"));
  appendYamlField(claudeLines, "background", resolveValue(doc.metadata, "claude", "background"));
  appendYamlField(claudeLines, "isolation", resolveValue(doc.metadata, "claude", "isolation"));
  appendExtraFields(claudeLines, doc.metadata, "claude.extra.");

  const cursorLines = [
    `name: ${yamlQuote(doc.name)}`,
    `description: ${yamlQuote(doc.description)}`,
  ];
  appendYamlField(cursorLines, "model", resolveValue(doc.metadata, "cursor", "model"));
  appendYamlField(cursorLines, "readonly", resolveValue(doc.metadata, "cursor", "readonly"));
  appendYamlField(cursorLines, "is_background", resolveValue(doc.metadata, "cursor", "is_background"));
  appendExtraFields(cursorLines, doc.metadata, "cursor.extra.");

  const opencodeLines = [`description: ${yamlQuote(doc.description)}`];
  appendYamlField(opencodeLines, "mode", resolveValue(doc.metadata, "opencode", "mode") || "subagent");
  appendYamlField(opencodeLines, "model", resolveValue(doc.metadata, "opencode", "model"));
  appendYamlField(opencodeLines, "temperature", resolveValue(doc.metadata, "opencode", "temperature"));
  appendYamlField(opencodeLines, "steps", resolveValue(doc.metadata, "opencode", "steps"));
  appendYamlField(opencodeLines, "disable", resolveValue(doc.metadata, "opencode", "disable"));
  appendYamlField(opencodeLines, "tools", resolveValue(doc.metadata, "opencode", "tools"));
  appendYamlField(opencodeLines, "permission", resolveValue(doc.metadata, "opencode", "permission"));
  appendYamlField(opencodeLines, "hidden", resolveValue(doc.metadata, "opencode", "hidden"));
  appendYamlField(opencodeLines, "color", resolveValue(doc.metadata, "opencode", "color"));
  appendYamlField(opencodeLines, "top_p", resolveValue(doc.metadata, "opencode", "top_p"));
  appendExtraFields(opencodeLines, doc.metadata, "opencode.extra.");

  const vscodeLines = [
    `name: ${yamlQuote(doc.name)}`,
    `description: ${yamlQuote(doc.description)}`,
  ];
  appendYamlField(vscodeLines, "argument-hint", resolveValue(doc.metadata, "vscode", "argument-hint"));
  appendYamlField(vscodeLines, "tools", resolveValue(doc.metadata, "vscode", "tools"));
  appendYamlField(vscodeLines, "agents", resolveValue(doc.metadata, "vscode", "agents"));
  appendYamlField(vscodeLines, "model", resolveValue(doc.metadata, "vscode", "model"));
  appendYamlField(vscodeLines, "user-invokable", resolveValue(doc.metadata, "vscode", "user-invokable"));
  appendYamlField(vscodeLines, "disable-model-invocation", resolveValue(doc.metadata, "vscode", "disable-model-invocation"));
  appendYamlField(vscodeLines, "target", resolveValue(doc.metadata, "vscode", "target"));
  appendYamlField(vscodeLines, "mcp-servers", resolveValue(doc.metadata, "vscode", "mcp-servers"));
  appendYamlField(vscodeLines, "handoffs", resolveValue(doc.metadata, "vscode", "handoffs"));
  appendExtraFields(vscodeLines, doc.metadata, "vscode.extra.");

  return {
    [`.claude/agents/${doc.name}.md`]: `${buildFrontmatter(claudeLines)}\n\n${doc.body}`,
    [`.cursor/agents/${doc.name}.md`]: `${buildFrontmatter(cursorLines)}\n\n${doc.body}`,
    [`.opencode/agents/${doc.name}.md`]: `${buildFrontmatter(opencodeLines)}\n\n${doc.body}`,
    [`.github/agents/${doc.name}.agent.md`]: `${buildFrontmatter(vscodeLines)}\n\n${doc.body}`,
  };
}

function renderSkill(doc) {
  const claudeLines = [
    `name: ${yamlQuote(doc.name)}`,
    `description: ${yamlQuote(doc.description)}`,
  ];
  appendYamlField(claudeLines, "allowed-tools", resolveValue(doc.metadata, "claude", "allowed-tools"));
  appendYamlField(claudeLines, "disable-model-invocation", resolveValue(doc.metadata, "claude", "disable-model-invocation"));
  appendYamlField(claudeLines, "model", resolveValue(doc.metadata, "claude", "model"));
  appendExtraFields(claudeLines, doc.metadata, "claude.extra.");

  const cursorLines = [
    `name: ${yamlQuote(doc.name)}`,
    `description: ${yamlQuote(doc.description)}`,
  ];
  appendExtraFields(cursorLines, doc.metadata, "cursor.extra.");

  const opencodeLines = [
    `name: ${yamlQuote(doc.name)}`,
    `description: ${yamlQuote(doc.description)}`,
  ];
  appendYamlField(opencodeLines, "permission", resolveValue(doc.metadata, "opencode", "permission"));
  appendExtraFields(opencodeLines, doc.metadata, "opencode.extra.");

  const vscodeLines = [
    `name: ${yamlQuote(doc.name)}`,
    `description: ${yamlQuote(doc.description)}`,
  ];
  appendYamlField(vscodeLines, "user-invokable", resolveValue(doc.metadata, "vscode", "user-invokable"));
  appendYamlField(vscodeLines, "disable-model-invocation", resolveValue(doc.metadata, "vscode", "disable-model-invocation"));
  appendExtraFields(vscodeLines, doc.metadata, "vscode.extra.");

  return {
    [`.claude/skills/${doc.name}/SKILL.md`]: `${buildFrontmatter(claudeLines)}\n\n${doc.body}`,
    [`.cursor/skills/${doc.name}/SKILL.md`]: `${buildFrontmatter(cursorLines)}\n\n${doc.body}`,
    [`.opencode/skills/${doc.name}/SKILL.md`]: `${buildFrontmatter(opencodeLines)}\n\n${doc.body}`,
    [`.github/skills/${doc.name}/SKILL.md`]: `${buildFrontmatter(vscodeLines)}\n\n${doc.body}`,
  };
}

export function renderMcpContent(source) {
  const claude = {};
  const cursor = {};
  const vscode = {};
  const opencode = {};

  for (const [name, server] of Object.entries(source)) {
    const serverType = String(server.type || (server.url ? "http" : "stdio")).trim();

    if (serverType === "stdio") {
      const entry = {};
      if (server.command) {
        entry.command = server.command;
      }
      if (server.args) {
        entry.args = [...server.args];
      }
      if (server.env) {
        entry.env = server.env;
      }

      claude[name] = entry;
      cursor[name] = entry;
      vscode[name] = entry;

      const opencodeEntry = { type: "local", command: [...(server.command ? [server.command] : []), ...(server.args || [])] };
      if (server.env) {
        opencodeEntry.environment = server.env;
      }
      opencode[name] = opencodeEntry;
      continue;
    }

    const headers = server.headers;
    const claudeEntry = { type: serverType };
    if (server.url) {
      claudeEntry.url = server.url;
    }
    if (headers) {
      claudeEntry.headers = headers;
    }
    claude[name] = claudeEntry;
    vscode[name] = { ...claudeEntry };

    const cursorEntry = {};
    if (server.url) {
      cursorEntry.url = server.url;
    }
    if (headers) {
      cursorEntry.headers = headers;
    }
    cursor[name] = cursorEntry;

    const opencodeEntry = { type: "remote" };
    if (server.url) {
      opencodeEntry.url = server.url;
    }
    if (headers) {
      opencodeEntry.headers = headers;
    }
    opencode[name] = opencodeEntry;
  }

  return {
    claudeJson: `${JSON.stringify({ mcpServers: claude }, null, 2)}\n`,
    cursorJson: `${JSON.stringify({ mcpServers: cursor }, null, 2)}\n`,
    vscodeJson: `${JSON.stringify({ servers: vscode }, null, 2)}\n`,
    opencodeJson: JSON.stringify(opencode, null, 2),
  };
}

export async function loadPack(packRoot) {
  const manifest = await readPackManifest(packRoot);
  const resources = await discoverPackResources(packRoot);
  const commands = [];
  const agents = [];
  const skills = [];

  for (const filePath of resources.commandFiles) {
    const doc = await parseCanonicalDoc(filePath);
    commands.push({ name: doc.name, outputs: renderCommand(doc) });
  }

  for (const filePath of resources.agentFiles) {
    const doc = await parseCanonicalDoc(filePath);
    agents.push({ name: doc.name, outputs: renderAgent(doc) });
  }

  for (const filePath of resources.skillFiles) {
    const doc = await parseCanonicalDoc(filePath);
    skills.push({ name: doc.name, outputs: renderSkill(doc) });
  }

  let mcpServers = {};
  if (await exists(resources.mcpFile)) {
    mcpServers = JSON.parse(await fs.readFile(resources.mcpFile, "utf8"));
  }

  return {
    ...manifest,
    packRoot,
    commands,
    agents,
    skills,
    mcpServers,
  };
}

export function flattenPackOutputs(pack, { includeMcp = true } = {}) {
  const outputs = {};

  for (const resource of [...pack.commands, ...pack.agents, ...pack.skills]) {
    Object.assign(outputs, resource.outputs);
  }

  if (includeMcp && Object.keys(pack.mcpServers).length > 0) {
    const rendered = renderMcpContent(pack.mcpServers);
    outputs[".mcp.json"] = rendered.claudeJson;
    outputs[".cursor/mcp.json"] = rendered.cursorJson;
    outputs[".vscode/mcp.json"] = rendered.vscodeJson;
  }

  return outputs;
}

export async function generateAll({ root, dryRun = false }) {
  const stats = { written: 0, unchanged: 0, total: 0 };
  const sharedRoot = path.join(root, "pack", "shared");
  const sharedPack = await loadPack(sharedRoot);
  const outputs = flattenPackOutputs(sharedPack);

  if (Object.keys(outputs).length === 0) {
    throw new Error("Nothing to generate. Add canonical files in pack/shared/commands, pack/shared/agents, pack/shared/skills/<name>/SKILL.md, or pack/shared/mcp.json.");
  }

  for (const [relativePath, content] of Object.entries(outputs)) {
    await writeIfChanged(root, path.join(root, relativePath), content, stats, dryRun);
  }

  console.log("");
  console.log(`Generated files: ${stats.total}`);
  console.log(`- written: ${stats.written}`);
  console.log(`- unchanged: ${stats.unchanged}`);

  return stats;
}
