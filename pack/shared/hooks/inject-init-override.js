#!/usr/bin/env node

const fs = require('fs');

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function getPrompt(input) {
  try {
    const parsed = JSON.parse(input);
    return typeof parsed.prompt === 'string' ? parsed.prompt : '';
  } catch {
    return '';
  }
}

function main() {
  const input = readStdin();
  const prompt = getPrompt(input);

  if (!/^\s*\/init(?:\s|$)/.test(prompt)) {
    return;
  }

  const message = [
    'IMPORTANT OVERRIDE: The file must be named AGENTS.md, not CLAUDE.md.',
    "Use '# AGENTS.md' as the file header and 'This file provides guidance to AI agents when working with code in this repository.' as the subtitle.",
    "Do NOT use '# CLAUDE.md' under any circumstances."
  ].join(' ');

  process.stdout.write(`${message}\n`);
}

main();
