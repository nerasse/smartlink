import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { createInterface } from "node:readline/promises";
import { discoverPackCatalog, loadPack, renderMcpContent } from "./generate.js";
import { pathExists, probeSymlinkSupport, readJsonFile, safeLinkOrCopy, writeJsonIfChanged } from "./install.js";
import { formatPathForDisplay } from "./paths.js";

const STATE_VERSION = 1;

class PromptSession {
  constructor(stdin, stdout) {
    this.stdin = stdin;
    this.stdout = stdout;
    this.readline = stdin.isTTY ? createInterface({ input: stdin, output: stdout }) : null;
    this.bufferPromise = null;
    this.bufferedLines = null;
  }

  async loadBufferedLines() {
    if (!this.bufferPromise) {
      this.bufferPromise = (async () => {
        const chunks = [];
        for await (const chunk of this.stdin) {
          chunks.push(String(chunk));
        }
        return chunks.join("").split(/\r?\n/u);
      })();
    }

    if (!this.bufferedLines) {
      this.bufferedLines = await this.bufferPromise;
    }

    return this.bufferedLines;
  }

  async question(prompt) {
    if (this.readline) {
      return this.readline.question(prompt);
    }

    this.stdout.write(prompt);
    const lines = await this.loadBufferedLines();
    return lines.shift() ?? "";
  }

  close() {
    if (this.readline) {
      this.readline.close();
    }
  }
}

function formatWorkspacePath(workspaceRoot, targetPath) {
  const relativePath = path.relative(workspaceRoot, targetPath);

  if (!relativePath) {
    return ".";
  }

  if (!relativePath.startsWith("..") && !path.isAbsolute(relativePath)) {
    return `./${relativePath.split(path.sep).join("/")}`;
  }

  return targetPath;
}

function parseYesNo(value, fallback = true) {
  const normalized = String(value || "").trim().toLowerCase();

  if (!normalized) {
    return fallback;
  }

  return !["n", "no"].includes(normalized);
}

function dedupePreservingOrder(values) {
  const seen = new Set();
  const deduped = [];

  for (const value of values) {
    if (!seen.has(value)) {
      seen.add(value);
      deduped.push(value);
    }
  }

  return deduped;
}

function parsePackSelection(input, availablePacks) {
  const normalizedInput = input.trim().toLowerCase();
  if (normalizedInput === "none" || normalizedInput === "0") {
    return [];
  }

  const byIndex = new Map();
  const byName = new Map();

  availablePacks.forEach((pack, index) => {
    byIndex.set(String(index + 1), pack.name);
    byName.set(pack.name.toLowerCase(), pack.name);
  });

  const selectedNames = [];
  for (const rawToken of input.split(",")) {
    const token = rawToken.trim();
    if (!token) {
      continue;
    }

    const byNumber = byIndex.get(token);
    if (byNumber) {
      selectedNames.push(byNumber);
      continue;
    }

    const byPackName = byName.get(token.toLowerCase());
    if (byPackName) {
      selectedNames.push(byPackName);
      continue;
    }

    throw new Error(`Unknown pack selection: ${token}`);
  }

  return dedupePreservingOrder(selectedNames);
}

function createPackLabel(pack) {
  return pack.description ? `${pack.title} - ${pack.description}` : pack.title;
}

async function promptForPackSelection({ availablePacks, previousSelection, workspaceRoot, promptSession, stdout }) {
  stdout.write(`\nWorkspace target: ${workspaceRoot}\n`);
  const continueAnswer = await promptSession.question("Continue with this workspace? [Y/n]: ");
  if (!parseYesNo(continueAnswer, true)) {
    return null;
  }

  stdout.write("\nShared global pack: always active\n");
  stdout.write("Optional workspace packs:\n");
  availablePacks.forEach((pack, index) => {
    stdout.write(`  ${index + 1}. ${createPackLabel(pack)}\n`);
  });

  if (previousSelection.length > 0) {
    stdout.write(`Previous selection: ${previousSelection.join(", ")}\n`);
  }

  while (true) {
    const prompt = previousSelection.length > 0
      ? "Select packs to sync (comma-separated, Enter to reuse previous, type none to remove all, type cancel to abort): "
      : "Select packs to sync (comma-separated numbers, blank to cancel): ";
    const answer = await promptSession.question(prompt);

    if (answer.trim().toLowerCase() === "cancel") {
      return null;
    }

    if (!answer.trim()) {
      if (previousSelection.length > 0) {
        return previousSelection;
      }
      return null;
    }

    try {
      const selection = parsePackSelection(answer, availablePacks);
      if (selection.length === 0 && answer.trim().toLowerCase() !== "none" && answer.trim() !== "0") {
        stdout.write("No packs selected. Try again or press Enter to cancel.\n");
        continue;
      }
      return selection;
    } catch (error) {
      stdout.write(`Invalid selection: ${error.message}\n`);
    }
  }
}

export async function loadWorkspaceSyncState(workspaceRoot) {
  const statePath = path.join(workspaceRoot, ".smartlink", "sync-state.json");

  if (!(await pathExists(statePath))) {
    return null;
  }

  try {
    return JSON.parse(await fs.readFile(statePath, "utf8"));
  } catch {
    return null;
  }
}

async function writeWorkspaceSyncState(workspaceRoot, state, dryRun) {
  const statePath = path.join(workspaceRoot, ".smartlink", "sync-state.json");
  const next = `${JSON.stringify(state, null, 2)}\n`;

  if (dryRun) {
    console.log(`plan ${formatWorkspacePath(workspaceRoot, statePath)}`);
    return;
  }

  await fs.mkdir(path.dirname(statePath), { recursive: true });
  await fs.writeFile(statePath, next, "utf8");
  console.log(`write ${formatWorkspacePath(workspaceRoot, statePath)}`);
}

async function writeStageOutputs(stageRoot, outputs) {
  await fs.rm(stageRoot, { recursive: true, force: true });

  for (const [relativePath, content] of Object.entries(outputs)) {
    const targetPath = path.join(stageRoot, relativePath);
    await fs.mkdir(path.dirname(targetPath), { recursive: true });
    await fs.writeFile(targetPath, content, "utf8");
  }
}

async function removeManagedPath(workspaceRoot, relativePath, counters, dryRun) {
  const targetPath = path.join(workspaceRoot, relativePath);
  if (!(await pathExists(targetPath))) {
    return;
  }

  if (relativePath === "opencode.json") {
    const existing = await readJsonFile(targetPath);
    if (Object.prototype.hasOwnProperty.call(existing, "mcp")) {
      delete existing.mcp;

      if (Object.keys(existing).length === 0) {
        console.log(`remove ${formatWorkspacePath(workspaceRoot, targetPath)}`);
        counters.removed += 1;
        if (!dryRun) {
          await fs.rm(targetPath, { force: true });
        }
      } else {
        await writeJsonIfChanged(targetPath, existing, os.homedir(), counters, dryRun, `${formatWorkspacePath(workspaceRoot, targetPath)} (mcp cleaned)`);
      }
    }
    return;
  }

  console.log(`remove ${formatWorkspacePath(workspaceRoot, targetPath)}`);
  counters.removed += 1;
  if (!dryRun) {
    await fs.rm(targetPath, { recursive: true, force: true });
  }
}

async function removeStaleWorkspaceOutputs({ workspaceRoot, previousState, nextManagedPaths, dryRun, counters }) {
  const previousManaged = new Set(previousState?.managedPaths || []);
  const nextManaged = new Set(nextManagedPaths);

  for (const relativePath of previousManaged) {
    if (!nextManaged.has(relativePath)) {
      await removeManagedPath(workspaceRoot, relativePath, counters, dryRun);
    }
  }
}

async function installWorkspaceOutputs({ workspaceRoot, stageRoot, outputs, mode, dryRun, counters }) {
  for (const relativePath of Object.keys(outputs)) {
    const sourcePath = path.join(stageRoot, relativePath);
    const targetPath = path.join(workspaceRoot, relativePath);
    await safeLinkOrCopy(sourcePath, targetPath, os.homedir(), mode, counters, dryRun);
  }
}

async function confirmSync({ workspaceRoot, selection, mode, warnings, promptSession, stdout }) {
  stdout.write(`\nWorkspace: ${workspaceRoot}\n`);
  stdout.write(`Packs: ${selection.length > 0 ? selection.join(", ") : "none (remove optional packs)"}\n`);
  stdout.write(`Install mode: ${mode}\n`);
  if (warnings.length > 0) {
    stdout.write(`Warnings: ${warnings.length} duplicate resource(s) will be skipped\n`);
  }
  const answer = await promptSession.question("Sync these packs now? [Y/n]: ");
  return parseYesNo(answer, true);
}

function collectSharedReservations(sharedPack) {
  const owners = new Map();

  for (const resource of sharedPack.commands) {
    owners.set(`command:${resource.name}`, "shared");
  }
  for (const resource of sharedPack.agents) {
    owners.set(`agent:${resource.name}`, "shared");
  }
  for (const resource of sharedPack.skills) {
    owners.set(`skill:${resource.name}`, "shared");
  }
  for (const name of Object.keys(sharedPack.mcpServers)) {
    owners.set(`mcp:${name}`, "shared");
  }

  return owners;
}

function addResourceOutputs({ type, resources, packName, owners, outputs, warnings, resourceOwners }) {
  for (const resource of resources) {
    const resourceKey = `${type}:${resource.name}`;
    const existingOwner = owners.get(resourceKey);
    if (existingOwner) {
      warnings.push(`WARN  ${type} "${resource.name}" from pack "${packName}" skipped: already provided by ${existingOwner}`);
      continue;
    }

    owners.set(resourceKey, packName);
    resourceOwners[resourceKey] = packName;
    Object.assign(outputs, resource.outputs);
  }
}

function addMcpServers({ packName, mcpServers, owners, mergedMcp, warnings, resourceOwners }) {
  for (const [name, server] of Object.entries(mcpServers)) {
    const resourceKey = `mcp:${name}`;
    const existingOwner = owners.get(resourceKey);
    if (existingOwner) {
      warnings.push(`WARN  mcp "${name}" from pack "${packName}" skipped: already provided by ${existingOwner}`);
      continue;
    }

    owners.set(resourceKey, packName);
    resourceOwners[resourceKey] = packName;
    mergedMcp[name] = server;
  }
}

async function buildMergedPlan(sourceRoot, selectedPackNames) {
  const sharedPack = await loadPack(path.join(sourceRoot, "pack", "shared"));
  const selectedPacks = [];

  for (const packName of selectedPackNames) {
    selectedPacks.push(await loadPack(path.join(sourceRoot, "pack", packName)));
  }

  const owners = collectSharedReservations(sharedPack);
  const outputs = {};
  const warnings = [];
  const resourceOwners = {};
  const mergedMcp = {};

  for (const [resourceKey, owner] of owners.entries()) {
    resourceOwners[resourceKey] = owner;
  }

  for (const pack of selectedPacks) {
    addResourceOutputs({ type: "command", resources: pack.commands, packName: pack.name, owners, outputs, warnings, resourceOwners });
    addResourceOutputs({ type: "agent", resources: pack.agents, packName: pack.name, owners, outputs, warnings, resourceOwners });
    addResourceOutputs({ type: "skill", resources: pack.skills, packName: pack.name, owners, outputs, warnings, resourceOwners });
    addMcpServers({ packName: pack.name, mcpServers: pack.mcpServers, owners, mergedMcp, warnings, resourceOwners });
  }

  let renderedMcp = null;
  if (Object.keys(mergedMcp).length > 0) {
    renderedMcp = renderMcpContent(mergedMcp);
    outputs[".mcp.json"] = renderedMcp.claudeJson;
    outputs[".cursor/mcp.json"] = renderedMcp.cursorJson;
    outputs[".vscode/mcp.json"] = renderedMcp.vscodeJson;
  }

  return {
    outputs,
    warnings,
    renderedMcp,
    resourceOwners,
  };
}

export async function syncWorkspace({
  sourceRoot,
  workspaceRoot,
  dryRun = false,
  mode = "auto",
  stdin = process.stdin,
  stdout = process.stdout,
}) {
  const availablePacks = (await discoverPackCatalog(sourceRoot))
    .filter((pack) => !pack.isShared)
    .filter((pack) => pack.workspaceOnly !== false);

  if (availablePacks.length === 0) {
    console.log("No optional packs are available. Add a pack under pack/ first.");
    return;
  }

  const previousState = await loadWorkspaceSyncState(workspaceRoot);
  const previousSelection = (previousState?.selectedPacks || []).filter((name) => availablePacks.some((pack) => pack.name === name));
  const promptSession = new PromptSession(stdin, stdout);

  let selection;
  try {
    selection = await promptForPackSelection({
      availablePacks,
      previousSelection,
      workspaceRoot,
      promptSession,
      stdout,
    });

    if (selection === null) {
      console.log("Sync cancelled.");
      return;
    }

    let installMode = mode;
    if (installMode === "auto") {
      installMode = (await probeSymlinkSupport(sourceRoot)) ? "link" : "copy";
      if (installMode === "copy") {
        console.log("WARN  Symlinks not available. Falling back to copy.");
      }
    } else if (installMode === "link" && !(await probeSymlinkSupport(sourceRoot))) {
      throw new Error("Symlinks are not available on this system. Retry with --copy.");
    }

    const plan = await buildMergedPlan(sourceRoot, selection);
    console.log("");
    for (const warning of plan.warnings) {
      console.log(warning);
    }

    const confirmed = await confirmSync({
      workspaceRoot,
      selection,
      mode: installMode,
      warnings: plan.warnings,
      promptSession,
      stdout,
    });

    if (!confirmed) {
      console.log("Sync cancelled.");
      return;
    }

    const counters = { linked: 0, copied: 0, unchanged: 0, backedUp: 0, removed: 0 };
    const stageRoot = dryRun
      ? await fs.mkdtemp(path.join(os.tmpdir(), "smartlink-sync-"))
      : path.join(workspaceRoot, ".smartlink", "staging");

    try {
      await writeStageOutputs(stageRoot, plan.outputs);

      console.log("\nWorkspace sync:");
      console.log(`- source: ${formatPathForDisplay(sourceRoot)}`);
      console.log(`- workspace: ${workspaceRoot}`);
      console.log(`- packs: ${selection.length > 0 ? selection.join(", ") : "none"}`);

      await installWorkspaceOutputs({
        workspaceRoot,
        stageRoot,
        outputs: plan.outputs,
        mode: installMode,
        dryRun,
        counters,
      });

      const nextManagedPaths = [...Object.keys(plan.outputs)];

      if (plan.renderedMcp) {
        const opencodePath = path.join(workspaceRoot, "opencode.json");
        const opencodeJson = await readJsonFile(opencodePath);
        opencodeJson.mcp = JSON.parse(plan.renderedMcp.opencodeJson);
        await writeJsonIfChanged(opencodePath, opencodeJson, os.homedir(), counters, dryRun, `${formatWorkspacePath(workspaceRoot, opencodePath)} (mcp merged)`);
        nextManagedPaths.push("opencode.json");
      }

      await removeStaleWorkspaceOutputs({
        workspaceRoot,
        previousState,
        nextManagedPaths,
        dryRun,
        counters,
      });

      await writeWorkspaceSyncState(workspaceRoot, {
        version: STATE_VERSION,
        sourceRoot,
        selectedPacks: selection,
        installMode,
        managedPaths: nextManagedPaths.sort(),
        resourceOwners: plan.resourceOwners,
        updatedAt: new Date().toISOString(),
      }, dryRun);

      console.log("\nSync summary:");
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
        console.log(`- removed: ${counters.removed}`);
      }
      if (plan.warnings.length > 0) {
        console.log(`- warnings: ${plan.warnings.length}`);
      }
    } finally {
      if (dryRun) {
        await fs.rm(stageRoot, { recursive: true, force: true });
      }
    }
  } finally {
    promptSession.close();
  }
}
