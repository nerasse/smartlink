#!/usr/bin/env node

import { fileURLToPath } from "node:url";
import path from "node:path";
import process from "node:process";
import { generateAll } from "./lib/generate.js";
import { installAll } from "./lib/install.js";
import { syncWorkspace } from "./lib/sync.js";
import { detectRuntimePaths, formatPathForDisplay, resolveSourceRoot, resolveWorkspaceRoot } from "./lib/paths.js";

const moduleRoot = path.dirname(fileURLToPath(import.meta.url));

function printHelp() {
  console.log(`smartlink

Usage:
  smartlink [command] [options]

Commands:
  setup     Generate workspace files and install them globally (default)
  generate  Generate workspace files only
  install   Install already-generated files globally
  sync      Interactively sync optional packs into a workspace
  doctor    Show detected platform paths and profile targets

Options:
  --root <path>  Use a specific project root
  --workspace <path>  Target workspace for sync
  --dry-run      Show planned changes without writing files
  --link         Force symlink mode
  --copy         Force copy mode
  -h, --help     Show this help
`);
}

function parseArgs(argv) {
  const options = {
    command: "setup",
    dryRun: false,
    mode: "auto",
    root: null,
    workspace: null,
  };

  let commandSet = false;

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];

    if (arg === "-h" || arg === "--help") {
      options.help = true;
      continue;
    }

    if (arg === "--dry-run") {
      options.dryRun = true;
      continue;
    }

    if (arg === "--link") {
      options.mode = "link";
      continue;
    }

    if (arg === "--copy") {
      options.mode = "copy";
      continue;
    }

    if (arg === "--root") {
      const next = argv[index + 1];
      if (!next) {
        throw new Error("Missing value after --root");
      }
      options.root = path.resolve(next);
      index += 1;
      continue;
    }

    if (arg === "--workspace") {
      const next = argv[index + 1];
      if (!next) {
        throw new Error("Missing value after --workspace");
      }
      options.workspace = path.resolve(next);
      index += 1;
      continue;
    }

    if (!arg.startsWith("-") && !commandSet) {
      options.command = arg;
      commandSet = true;
      continue;
    }

    throw new Error(`Unknown argument: ${arg}`);
  }

  return options;
}

function resolveRoot(explicitRoot) {
  return resolveSourceRoot(explicitRoot, moduleRoot);
}

function printDoctor(root) {
  const runtime = detectRuntimePaths(root);

  console.log(`Platform: ${process.platform}`);
  console.log(`Project root: ${root}`);
  console.log(`Home: ${runtime.homeDir}`);
  console.log(`Config home: ${runtime.configHome}`);
  console.log(`OpenCode global: ${runtime.opencodeGlobal}`);
  console.log(`Claude global: ${runtime.claudeGlobal}`);
  console.log(`Cursor global: ${runtime.cursorGlobal}`);
  console.log(`VS Code effective profiles: ${runtime.vscodeProfiles.effective.length}`);

  for (const profile of runtime.vscodeProfiles.effective) {
    console.log(`- ${formatPathForDisplay(profile, runtime.homeDir)}`);
  }

  if (runtime.vscodeProfiles.skipped.length > 0) {
    console.log(`Skipped root profiles: ${runtime.vscodeProfiles.skipped.length}`);
    for (const profile of runtime.vscodeProfiles.skipped) {
      console.log(`- ${formatPathForDisplay(profile, runtime.homeDir)}`);
    }
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));

  if (options.help) {
    printHelp();
    return;
  }

  const root = resolveRoot(options.root);
  const workspaceRoot = resolveWorkspaceRoot(options.workspace);

  if (options.command === "doctor") {
    printDoctor(root);
    console.log(`Workspace default: ${workspaceRoot}`);
    return;
  }

  if (options.command === "generate") {
    await generateAll({ root, dryRun: options.dryRun });
    return;
  }

  if (options.command === "install") {
    await installAll({ root, dryRun: options.dryRun, mode: options.mode });
    return;
  }

  if (options.command === "setup") {
    await generateAll({ root, dryRun: options.dryRun });
    await installAll({ root, dryRun: options.dryRun, mode: options.mode });
    return;
  }

  if (options.command === "sync") {
    await syncWorkspace({
      sourceRoot: root,
      workspaceRoot,
      dryRun: options.dryRun,
      mode: options.mode,
    });
    return;
  }

  throw new Error(`Unknown command: ${options.command}`);
}

main().catch((error) => {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
});
