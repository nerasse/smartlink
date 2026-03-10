import fs from "node:fs";
import os from "node:os";
import path from "node:path";

function isDirectory(targetPath) {
  try {
    return fs.statSync(targetPath).isDirectory();
  } catch {
    return false;
  }
}

function addUnique(list, value) {
  if (!value || !isDirectory(value)) {
    return;
  }

  const normalized = path.resolve(value);
  if (!list.includes(normalized)) {
    list.push(normalized);
  }
}

export function normalizeForVsCode(value) {
  return path.resolve(value).split(path.sep).join("/");
}

export function formatPathForDisplay(targetPath, homeDir = os.homedir()) {
  const normalizedHome = path.resolve(homeDir);
  const normalizedTarget = path.resolve(targetPath);

  if (normalizedTarget === normalizedHome) {
    return "~";
  }

  if (normalizedTarget.startsWith(`${normalizedHome}${path.sep}`)) {
    return `~/${path.relative(normalizedHome, normalizedTarget).split(path.sep).join("/")}`;
  }

  return normalizedTarget;
}

export function findProjectRoot(startDir) {
  let current = path.resolve(startDir);

  while (true) {
    if (isDirectory(path.join(current, "pack", "shared"))) {
      return current;
    }

    const parent = path.dirname(current);
    if (parent === current) {
      return null;
    }

    current = parent;
  }
}

export function resolveSourceRoot(explicitRoot, moduleRoot) {
  const root = path.resolve(explicitRoot || moduleRoot);

  if (!isDirectory(path.join(root, "pack", "shared"))) {
    throw new Error(`Smartlink source root not found at ${root}`);
  }

  return root;
}

export function resolveWorkspaceRoot(explicitWorkspace, cwd = process.cwd()) {
  return path.resolve(explicitWorkspace || cwd);
}

export function discoverVsCodeProfiles(homeDir = os.homedir()) {
  const profileDirs = [];
  const userRoots = [];
  const appData = process.env.APPDATA;

  if (process.platform === "win32" && appData) {
    userRoots.push(
      path.join(appData, "Code", "User"),
      path.join(appData, "Code - Insiders", "User"),
      path.join(appData, "VSCodium", "User"),
      path.join(appData, "VSCodium - Insiders", "User"),
    );
  } else if (process.platform === "darwin") {
    userRoots.push(
      path.join(homeDir, "Library", "Application Support", "Code", "User"),
      path.join(homeDir, "Library", "Application Support", "Code - Insiders", "User"),
      path.join(homeDir, "Library", "Application Support", "VSCodium", "User"),
      path.join(homeDir, "Library", "Application Support", "VSCodium - Insiders", "User"),
    );
  } else {
    const configHome = process.env.XDG_CONFIG_HOME || path.join(homeDir, ".config");
    userRoots.push(
      path.join(configHome, "Code", "User"),
      path.join(configHome, "Code - Insiders", "User"),
      path.join(configHome, "VSCodium", "User"),
      path.join(configHome, "VSCodium - Insiders", "User"),
    );
  }

  const remoteRoots = [
    path.join(homeDir, ".vscode-server", "data", "User"),
    path.join(homeDir, ".vscode-server-insiders", "data", "User"),
    path.join(homeDir, ".vscode-remote", "data", "User"),
    path.join(homeDir, ".vscode-remote-insiders", "data", "User"),
  ];

  for (const root of [...userRoots, ...remoteRoots]) {
    if (!isDirectory(root)) {
      continue;
    }

    addUnique(profileDirs, root);

    const profilesRoot = path.join(root, "profiles");
    if (!isDirectory(profilesRoot)) {
      continue;
    }

    for (const entry of fs.readdirSync(profilesRoot, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        addUnique(profileDirs, path.join(profilesRoot, entry.name));
      }
    }
  }

  const effective = [];
  const skipped = [];
  const namedProfiles = profileDirs.filter((value) => value.includes(`${path.sep}profiles${path.sep}`));

  for (const profile of namedProfiles) {
    addUnique(effective, profile);
  }

  for (const profile of profileDirs) {
    if (profile.includes(`${path.sep}profiles${path.sep}`)) {
      continue;
    }

    const profilesRoot = `${profile}${path.sep}profiles${path.sep}`;
    const hasNamedProfiles = profileDirs.some((candidate) => candidate.startsWith(profilesRoot));

    if (hasNamedProfiles) {
      addUnique(skipped, profile);
    } else {
      addUnique(effective, profile);
    }
  }

  return { all: profileDirs, effective, skipped };
}

export function detectRuntimePaths(root) {
  const homeDir = os.homedir();
  const configHome = process.env.XDG_CONFIG_HOME || path.join(homeDir, ".config");

  return {
    root,
    homeDir,
    configHome,
    opencodeGlobal: path.join(configHome, "opencode"),
    claudeGlobal: path.join(homeDir, ".claude"),
    cursorGlobal: path.join(homeDir, ".cursor"),
    vscodeProfiles: discoverVsCodeProfiles(homeDir),
  };
}
