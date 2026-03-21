#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function safeReadText(filePath) {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch {
    return null;
  }
}

function main() {
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const agentsPath = path.join(projectDir, 'AGENTS.md');
  const claudePath = path.join(projectDir, 'CLAUDE.md');

  if (!fs.existsSync(agentsPath)) {
    return;
  }

  const claudeContent = safeReadText(claudePath);
  if (claudeContent && claudeContent.includes('@AGENTS.md')) {
    return;
  }

  const agentsContent = safeReadText(agentsPath);
  if (!agentsContent) {
    return;
  }

  process.stdout.write('=== Project AGENTS.md ===\n');
  process.stdout.write(agentsContent);
  if (!agentsContent.endsWith('\n')) {
    process.stdout.write('\n');
  }
}

main();
