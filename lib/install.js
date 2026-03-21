import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import vm from "node:vm";
import { loadPack, renderMcpContent } from "./generate.js";
import { detectRuntimePaths, formatPathForDisplay, normalizeForVsCode } from "./paths.js";

export async function pathExists(targetPath) {
  try {
    await fs.lstat(targetPath);
    return true;
  } catch {
    return false;
  }
}

function timestamp() {
  const now = new Date();
  const parts = [
    now.getFullYear(),
    String(now.getMonth() + 1).padStart(2, "0"),
    String(now.getDate()).padStart(2, "0"),
  ];
  const time = [
    String(now.getHours()).padStart(2, "0"),
    String(now.getMinutes()).padStart(2, "0"),
    String(now.getSeconds()).padStart(2, "0"),
  ];
  return `${parts.join("")}-${time.join("")}`;
}

async function readNormalizedFile(targetPath) {
  return (await fs.readFile(targetPath, "utf8")).replace(/\r\n/g, "\n");
}

async function ensureParentDir(targetPath, dryRun) {
  if (dryRun) {
    return;
  }
  await fs.mkdir(path.dirname(targetPath), { recursive: true });
}

export async function probeSymlinkSupport(root) {
  const probeSource = path.join(root, ".gitignore");
  const probeTarget = path.join(os.tmpdir(), `smartlink_symlink_probe_${process.pid}_${Date.now()}`);

  try {
    await fs.symlink(probeSource, probeTarget, "file");
    await fs.unlink(probeTarget);
    return true;
  } catch {
    try {
      await fs.unlink(probeTarget);
    } catch {
      // ignore
    }
    return false;
  }
}

async function removeManagedLink(source, target, homeDir, counters, dryRun) {
  let stat;
  try {
    stat = await fs.lstat(target);
  } catch {
    return;
  }

  if (!stat.isSymbolicLink()) {
    return;
  }

  const existingLink = await fs.readlink(target);
  const resolved = path.resolve(path.dirname(target), existingLink);
  if (resolved !== path.resolve(source)) {
    return;
  }

  console.log(`remove ${formatPathForDisplay(target, homeDir)}`);
  counters.removed += 1;

  if (!dryRun) {
    await fs.unlink(target);
  }
}

export async function safeLinkOrCopy(source, target, homeDir, mode, counters, dryRun) {
  const targetLabel = formatPathForDisplay(target, homeDir);
  const sourceLabel = path.relative(process.cwd(), source) || source;
  let stat = null;

  try {
    stat = await fs.lstat(target);
  } catch {
    stat = null;
  }

  if (stat?.isSymbolicLink()) {
    const existingLink = await fs.readlink(target);
    const resolved = path.resolve(path.dirname(target), existingLink);
    if (resolved === path.resolve(source)) {
      console.log(`${mode === "copy" ? "copy " : "link "} ${targetLabel}  (ok)`);
      counters.unchanged += 1;
      return;
    }

    if (!dryRun) {
      await fs.unlink(target);
    }
  } else if (stat) {
    if (mode === "copy") {
      const [sourceContent, targetContent] = await Promise.all([
        readNormalizedFile(source),
        readNormalizedFile(target),
      ]);

      if (sourceContent === targetContent) {
        console.log(`copy  ${targetLabel}  (ok)`);
        counters.unchanged += 1;
        return;
      }

      if (!dryRun) {
        await fs.rm(target, { force: true });
      }
    } else {
      const backupPath = `${target}.bak.${timestamp()}`;
      console.log(`backup ${targetLabel} -> ${formatPathForDisplay(backupPath, homeDir)}`);
      counters.backedUp += 1;
      if (!dryRun) {
        await fs.rename(target, backupPath);
      }
    }
  }

  await ensureParentDir(target, dryRun);

  if (mode === "copy") {
    console.log(`copy  ${targetLabel} <- ${sourceLabel}`);
    counters.copied += 1;
    if (!dryRun) {
      await fs.copyFile(source, target);
    }
    return;
  }

  console.log(`link  ${targetLabel} -> ${sourceLabel}`);
  counters.linked += 1;
  if (!dryRun) {
    await fs.symlink(source, target, "file");
  }
}

export async function readJsonFile(targetPath, fallback = {}) {
  try {
    return JSON.parse(await fs.readFile(targetPath, "utf8"));
  } catch {
    return { ...fallback };
  }
}

export async function writeJsonIfChanged(targetPath, data, homeDir, counters, dryRun, label) {
  const next = `${JSON.stringify(data, null, 2)}\n`;
  const targetLabel = label || formatPathForDisplay(targetPath, homeDir);

  if (await pathExists(targetPath)) {
    const current = await readNormalizedFile(targetPath);
    if (current === next) {
      console.log(`ok    ${targetLabel}`);
      counters.unchanged += 1;
      return;
    }
  }

  console.log(`${dryRun ? "plan " : "write "}${targetLabel}`);
  counters.copied += 1;
  if (!dryRun) {
    await fs.mkdir(path.dirname(targetPath), { recursive: true });
    await fs.writeFile(targetPath, next, "utf8");
  }
}

function parseSettingsObject(text) {
  try {
    return JSON.parse(text);
  } catch {
    // keep fallback below
  }

  try {
    const parsed = vm.runInNewContext(`(${text})`, Object.create(null), { timeout: 1000 });
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed;
    }
  } catch {
    // ignore
  }

  return null;
}

function toLocationMap(value) {
  const map = {};

  if (!value) {
    return map;
  }

  if (Array.isArray(value)) {
    for (const entry of value) {
      if (typeof entry === "string" && entry.trim()) {
        map[entry] = true;
        continue;
      }

      if (entry && typeof entry === "object") {
        for (const [key, flag] of Object.entries(entry)) {
          if (key && key.trim()) {
            map[key] = Boolean(flag);
          }
        }
      }
    }

    return map;
  }

  if (value && typeof value === "object") {
    for (const [key, flag] of Object.entries(value)) {
      if (key && key.trim()) {
        map[key] = Boolean(flag);
      }
    }
  }

  return map;
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function stableStringify(value) {
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableStringify(item)).join(",")}]`;
  }

  if (isPlainObject(value)) {
    const keys = Object.keys(value).sort((left, right) => left.localeCompare(right));
    const fields = keys.map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`);
    return `{${fields.join(",")}}`;
  }

  return JSON.stringify(value);
}

function hookHandlerSignature(handler) {
  if (!isPlainObject(handler)) {
    return "";
  }

  return stableStringify(handler);
}

function hookGroupSignature(group) {
  if (!isPlainObject(group)) {
    return "";
  }

  const matcher = typeof group.matcher === "string" ? group.matcher : "";
  const handlers = Array.isArray(group.hooks) ? group.hooks.map(hookHandlerSignature).join("||") : "";
  return `${matcher}::${handlers}`;
}

function normalizeHooksMap(value) {
  if (!isPlainObject(value)) {
    return {};
  }

  const hooks = {};

  for (const [eventName, groups] of Object.entries(value)) {
    if (!Array.isArray(groups)) {
      continue;
    }

    const normalizedGroups = groups.filter((group) => {
      if (!isPlainObject(group) || !Array.isArray(group.hooks)) {
        return false;
      }

      return group.hooks.some((handler) => isPlainObject(handler) && typeof handler.type === "string");
    });

    if (normalizedGroups.length > 0) {
      hooks[eventName] = normalizedGroups;
    }
  }

  return hooks;
}

function mergeManagedHooksIntoSettings(settings, managedHooks) {
  const currentSettings = isPlainObject(settings) ? settings : {};
  const nextSettings = { ...currentSettings };
  const existingHooksRoot = isPlainObject(currentSettings.hooks) ? currentSettings.hooks : {};
  const nextHooksRoot = { ...existingHooksRoot };

  for (const [eventName, managedGroups] of Object.entries(managedHooks)) {
    const existingGroups = Array.isArray(nextHooksRoot[eventName]) ? [...nextHooksRoot[eventName]] : [];
    const seen = new Set(existingGroups.map(hookGroupSignature));

    for (const group of managedGroups) {
      const signature = hookGroupSignature(group);
      if (seen.has(signature)) {
        continue;
      }

      existingGroups.push(group);
      seen.add(signature);
    }

    nextHooksRoot[eventName] = existingGroups;
  }

  nextSettings.hooks = nextHooksRoot;
  return nextSettings;
}

async function installClaudeHooks(root, runtime, installMode, counters, dryRun) {
  const hooksSourceDir = path.join(root, "pack", "shared", "hooks");

  if (await pathExists(hooksSourceDir)) {
    const entries = await fs.readdir(hooksSourceDir, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isFile()) {
        continue;
      }

      const sourcePath = path.join(hooksSourceDir, entry.name);
      const targetPath = path.join(runtime.claudeGlobal, "hooks", entry.name);
      await safeLinkOrCopy(sourcePath, targetPath, runtime.homeDir, installMode, counters, dryRun);
    }
  }

  const managedHooksPath = path.join(root, "pack", "shared", "claude-hooks.json");
  if (!(await pathExists(managedHooksPath))) {
    return;
  }

  const managedHooksRaw = JSON.parse(await fs.readFile(managedHooksPath, "utf8"));
  const managedHooks = normalizeHooksMap(
    isPlainObject(managedHooksRaw.hooks) ? managedHooksRaw.hooks : managedHooksRaw,
  );

  if (Object.keys(managedHooks).length === 0) {
    return;
  }

  const settingsPath = path.join(runtime.claudeGlobal, "settings.json");
  let settings = {};

  if (await pathExists(settingsPath)) {
    const parsed = parseSettingsObject(await fs.readFile(settingsPath, "utf8"));
    if (!isPlainObject(parsed)) {
      console.log(`skip  ${formatPathForDisplay(settingsPath, runtime.homeDir)} (unsupported JSON/JSONC)`);
      return;
    }
    settings = parsed;
  }

  const nextSettings = mergeManagedHooksIntoSettings(settings, managedHooks);
  await writeJsonIfChanged(
    settingsPath,
    nextSettings,
    runtime.homeDir,
    counters,
    dryRun,
    `${formatPathForDisplay(settingsPath, runtime.homeDir)} (hooks merged)`,
  );
}

async function updateVsCodeSettings(profileDir, root, hasSkills, homeDir, counters, dryRun) {
  const settingsPath = path.join(profileDir, "settings.json");
  let settings = {};

  if (await pathExists(settingsPath)) {
    const parsed = parseSettingsObject(await fs.readFile(settingsPath, "utf8"));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      console.log(`skip  ${formatPathForDisplay(settingsPath, homeDir)} (unsupported JSON/JSONC)`);
      return;
    }
    settings = parsed;
  }

  const agentPath = normalizeForVsCode(path.join(root, ".github", "agents"));
  const agentMap = toLocationMap(settings["chat.agentFilesLocations"]);
  agentMap[agentPath] = true;
  settings["chat.agentFilesLocations"] = agentMap;

  if (hasSkills) {
    const skillPath = normalizeForVsCode(path.join(root, ".github", "skills"));
    const skillMap = toLocationMap(settings["chat.agentSkillsLocations"]);
    skillMap[skillPath] = true;
    settings["chat.agentSkillsLocations"] = skillMap;
  }

  await writeJsonIfChanged(
    settingsPath,
    settings,
    homeDir,
    counters,
    dryRun,
    `${formatPathForDisplay(profileDir, homeDir)}/settings.json (chat.agentFilesLocations)`,
  );
}

export async function installAll({ root, dryRun = false, mode = "auto" }) {
  const runtime = detectRuntimePaths(root);
  const sharedPack = await loadPack(path.join(root, "pack", "shared"));
  const counters = { linked: 0, copied: 0, unchanged: 0, backedUp: 0, removed: 0 };
  const sharedMcpExists = Object.keys(sharedPack.mcpServers).length > 0;

  let installMode = mode;
  if (installMode === "auto") {
    installMode = (await probeSymlinkSupport(root)) ? "link" : "copy";
    if (installMode === "copy") {
      console.log("WARN  Symlinks not available. Falling back to copy.");
    }
  } else if (installMode === "link" && !(await probeSymlinkSupport(root))) {
    throw new Error("Symlinks are not available on this system. Retry with --copy.");
  }

  console.log("\nGlobal install:");
  console.log(`VS Code-style profile targets: ${runtime.vscodeProfiles.effective.length}`);
  for (const profile of runtime.vscodeProfiles.effective) {
    console.log(`- ${formatPathForDisplay(profile, runtime.homeDir)}`);
  }

  if (runtime.vscodeProfiles.skipped.length > 0) {
    console.log(`Skipped root profiles: ${runtime.vscodeProfiles.skipped.length}`);
    for (const profile of runtime.vscodeProfiles.skipped) {
      console.log(`- ${formatPathForDisplay(profile, runtime.homeDir)}`);
    }
  }

  for (const resource of sharedPack.commands) {
    const name = resource.name;
    await safeLinkOrCopy(path.join(root, ".opencode", "commands", `${name}.md`), path.join(runtime.opencodeGlobal, "commands", `${name}.md`), runtime.homeDir, installMode, counters, dryRun);
    await safeLinkOrCopy(path.join(root, ".claude", "commands", `${name}.md`), path.join(runtime.claudeGlobal, "commands", `${name}.md`), runtime.homeDir, installMode, counters, dryRun);
    await safeLinkOrCopy(path.join(root, ".cursor", "commands", `${name}.md`), path.join(runtime.cursorGlobal, "commands", `${name}.md`), runtime.homeDir, installMode, counters, dryRun);

    for (const profile of runtime.vscodeProfiles.effective) {
      await safeLinkOrCopy(path.join(root, ".github", "prompts", `${name}.prompt.md`), path.join(profile, "prompts", `${name}.prompt.md`), runtime.homeDir, installMode, counters, dryRun);
    }

    for (const profile of runtime.vscodeProfiles.skipped) {
      await removeManagedLink(path.join(root, ".github", "prompts", `${name}.prompt.md`), path.join(profile, "prompts", `${name}.prompt.md`), runtime.homeDir, counters, dryRun);
    }
  }

  if (sharedMcpExists) {
    const renderedMcp = renderMcpContent(sharedPack.mcpServers);
    const claudeJson = await readJsonFile(path.join(runtime.homeDir, ".claude.json"));
    claudeJson.mcpServers = JSON.parse(await fs.readFile(path.join(root, ".mcp.json"), "utf8")).mcpServers;
    await writeJsonIfChanged(path.join(runtime.homeDir, ".claude.json"), claudeJson, runtime.homeDir, counters, dryRun);

    await safeLinkOrCopy(path.join(root, ".cursor", "mcp.json"), path.join(runtime.cursorGlobal, "mcp.json"), runtime.homeDir, installMode, counters, dryRun);

    for (const profile of runtime.vscodeProfiles.effective) {
      await safeLinkOrCopy(path.join(root, ".vscode", "mcp.json"), path.join(profile, "mcp.json"), runtime.homeDir, installMode, counters, dryRun);
    }

    for (const profile of runtime.vscodeProfiles.skipped) {
      await removeManagedLink(path.join(root, ".vscode", "mcp.json"), path.join(profile, "mcp.json"), runtime.homeDir, counters, dryRun);
    }

    const opencodeJson = await readJsonFile(path.join(runtime.opencodeGlobal, "opencode.json"));
    opencodeJson.mcp = JSON.parse(renderedMcp.opencodeJson);
    await writeJsonIfChanged(path.join(runtime.opencodeGlobal, "opencode.json"), opencodeJson, runtime.homeDir, counters, dryRun, "~/.config/opencode/opencode.json (mcp merged)");
  }

  for (const resource of sharedPack.agents) {
    const name = resource.name;
    await safeLinkOrCopy(path.join(root, ".opencode", "agents", `${name}.md`), path.join(runtime.opencodeGlobal, "agents", `${name}.md`), runtime.homeDir, installMode, counters, dryRun);
    await safeLinkOrCopy(path.join(root, ".claude", "agents", `${name}.md`), path.join(runtime.claudeGlobal, "agents", `${name}.md`), runtime.homeDir, installMode, counters, dryRun);
    await safeLinkOrCopy(path.join(root, ".cursor", "agents", `${name}.md`), path.join(runtime.cursorGlobal, "agents", `${name}.md`), runtime.homeDir, installMode, counters, dryRun);
  }

  for (const resource of sharedPack.skills) {
    const name = resource.name;
    await safeLinkOrCopy(path.join(root, ".claude", "skills", name, "SKILL.md"), path.join(runtime.claudeGlobal, "skills", name, "SKILL.md"), runtime.homeDir, installMode, counters, dryRun);
    await safeLinkOrCopy(path.join(root, ".opencode", "skills", name, "SKILL.md"), path.join(runtime.opencodeGlobal, "skills", name, "SKILL.md"), runtime.homeDir, installMode, counters, dryRun);
    await safeLinkOrCopy(path.join(root, ".cursor", "skills", name, "SKILL.md"), path.join(runtime.cursorGlobal, "skills", name, "SKILL.md"), runtime.homeDir, installMode, counters, dryRun);
  }

  await installClaudeHooks(root, runtime, installMode, counters, dryRun);

  for (const profile of runtime.vscodeProfiles.effective) {
    await updateVsCodeSettings(profile, root, sharedPack.skills.length > 0, runtime.homeDir, counters, dryRun);
  }

  console.log("\nInstall summary:");
  if (counters.linked > 0) {
    console.log(`- linked: ${counters.linked}`);
  }
  if (counters.copied > 0) {
    console.log(`- copied: ${counters.copied}`);
  }
  console.log(`- unchanged: ${counters.unchanged}`);
  if (counters.backedUp > 0) {
    console.log(`- backed up: ${counters.backedUp}`);
  }
  if (counters.removed > 0) {
    console.log(`- removed legacy links: ${counters.removed}`);
  }
}
