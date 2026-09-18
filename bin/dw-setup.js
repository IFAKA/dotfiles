#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DEV_HOSTNAME = 'development-eu01-kiwoko.demandware.net';
const DEV_CODE_VERSION = 'test';

function fail(message) {
  console.error(`dw: ${message}`);
  process.exitCode = 1;
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    fail(`invalid JSON in ${file}: ${error.message}`);
    process.exit(1);
  }
}

function writeJsonAtomic(file, value) {
  const temporary = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  fs.chmodSync(temporary, 0o600);
  fs.renameSync(temporary, file);
}

function projectStore(root) {
  const configHome = process.env.XDG_CONFIG_HOME || path.join(process.env.HOME, '.config');
  const id = crypto.createHash('sha256').update(root).digest('hex').slice(0, 24);
  const directory = path.join(configHome, 'dotfiles', 'dw', id);
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  fs.chmodSync(directory, 0o700);
  return directory;
}

function classify(config) {
  const hostname = String(config.hostname || '').toLowerCase();
  if (hostname === DEV_HOSTNAME || hostname.includes('development') || hostname.includes('dev')) return 'dev';
  return 'sbx';
}

function sandboxNumber(hostname) {
  const match = String(hostname || '').match(/(?:^|[-.])(\d{3})(?:[-.]|$)/);
  return match ? match[1] : '';
}

function complete(profile) {
  return Boolean(profile && profile.hostname && profile.username && profile.password && profile['code-version']);
}

function findRoot(start) {
  let current = path.resolve(start);
  while (true) {
    if (fs.existsSync(path.join(current, 'dw.json'))) return current;
    const parent = path.dirname(current);
    if (parent === current) return null;
    current = parent;
  }
}

function redact(value) {
  if (Array.isArray(value)) return value.map(redact);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, item]) =>
      [key, /pass(word)?|secret|token/i.test(key) ? '********' : redact(item)]));
  }
  return value;
}

function usage() {
  console.log('Usage: dw-setup.js ROOT [dev|sbx|--migrate]');
}

function migrate(root) {
  const store = projectStore(root);
  const imported = [];
  for (const name of ['dev', 'sbx']) {
    const legacyFile = path.join(root, `dw.${name}.json`);
    if (!fs.existsSync(legacyFile)) continue;
    const profile = readJson(legacyFile);
    if (!complete(profile)) {
      fail(`cannot migrate ${legacyFile}: it is missing hostname, username, password, or code-version`);
      return;
    }
    writeJsonAtomic(path.join(store, `${name}.json`), profile);
    imported.push(name);
  }

  const active = readJson(path.join(root, 'dw.json'));
  const activeName = classify(active);
  writeJsonAtomic(path.join(store, `${activeName}.json`), active);
  if (!imported.includes(activeName)) imported.unshift(activeName);
  console.log(`DW profiles imported to ${store}: ${imported.join(', ')}.`);
  console.log('Project files were not changed. Verify the import, then remove dw.dev.json and dw.sbx.json if desired.');
}

function setup(root, requestedTarget) {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    fail('environment setup requires an interactive terminal (run dw in a terminal or use prefix e)');
    return;
  }

  const activeFile = path.join(root, 'dw.json');
  const active = readJson(activeFile);
  const current = classify(active);
  const target = requestedTarget || (current === 'dev' ? 'sbx' : 'dev');
  const store = projectStore(root);
  const currentFile = path.join(store, `${current}.json`);
  const targetFile = path.join(store, `${target}.json`);

  // Always preserve the exact active file before asking any questions.
  writeJsonAtomic(currentFile, active);
  const existing = fs.existsSync(targetFile) ? readJson(targetFile) : {};
  const sharedUsername = active.username || existing.username || '';
  const targetProfile = { ...existing, username: sharedUsername };
  if (target === 'dev') {
    targetProfile.hostname = DEV_HOSTNAME;
    targetProfile['code-version'] = DEV_CODE_VERSION;
  } else {
    targetProfile.hostname ||= active.hostname && current === 'sbx' ? active.hostname : '';
    targetProfile['code-version'] ||= active['code-version'] && current === 'sbx' ? active['code-version'] : '';
  }

  const fields = target === 'dev'
    ? [{ key: 'password', label: 'Dev password', secret: true }]
    : [
        { key: 'sandbox', label: 'Sandbox number' },
        { key: 'password', label: 'Sandbox password', secret: true },
        { key: 'code-version', label: 'Code version' },
      ];
  if (!sharedUsername) fields.unshift({ key: 'username', label: 'Email' });
  if (target === 'sbx' && !targetProfile.sandbox) targetProfile.sandbox = sandboxNumber(targetProfile.hostname);

  if (complete(targetProfile)) {
    writeJsonAtomic(activeFile, targetProfile);
    console.log(`Switched to ${target}${target === 'sbx' ? ` ${sandboxNumber(targetProfile.hostname)}` : ''}.`);
    return;
  }

  const values = fields.map((field) => ({ ...field, value: field.key === 'sandbox' ? (targetProfile.sandbox || '') : (targetProfile[field.key] || '') }));
  const missing = () => values.filter((field) => !field.value);
  let index = Math.max(0, values.findIndex((field) => !field.value));
  if (index < 0) index = 0;
  let input = '';
  let pasteMode = false;
  let pasteBuffer = '';

  const render = (message = '') => {
    process.stdout.write('\x1b[2J\x1b[H');
    console.log('DW environment setup');
    console.log(`Current: ${current}${current === 'sbx' ? ` ${sandboxNumber(active.hostname) || ''}` : ''}`);
    console.log(`Target:  ${target}`);
    console.log('');
    values.forEach((field, position) => {
      const displayed = position === index
        ? (field.secret ? '*'.repeat(input.length) : input)
        : (field.secret && field.value ? '********' : field.value);
      console.log(`${position === index ? '>' : ' '} ${field.label}: ${displayed}`);
    });
    console.log('');
    if (message) console.log(message);
    console.log('Enter: next/submit   Tab: next   Shift-Tab: previous   Esc: cancel');
  };

  const cancel = () => {
    process.stdout.write('\x1b[?2004l\x1b[?25h\n');
    process.stdin.setRawMode(false);
    process.stdin.pause();
    console.log(`Cancelled. Staying in ${current}${current === 'sbx' ? ` ${sandboxNumber(active.hostname) || ''}` : ''}.`);
    process.exit(0);
  };

  const submit = () => {
    if (missing().length) {
      render('Complete the remaining required fields.');
      return;
    }
    targetProfile.username = targetProfile.username || sharedUsername;
    for (const field of values) targetProfile[field.key] = field.value;
    if (target === 'sbx') {
      targetProfile.hostname = `bdlq-${targetProfile.sandbox}.dx.commercecloud.salesforce.com`;
      delete targetProfile.sandbox;
    }
    if (target === 'dev') {
      targetProfile.hostname = DEV_HOSTNAME;
      targetProfile['code-version'] = DEV_CODE_VERSION;
    }
    writeJsonAtomic(targetFile, targetProfile);
    writeJsonAtomic(activeFile, targetProfile);
    process.stdout.write('\x1b[?2004l\x1b[?25h');
    process.stdin.setRawMode(false);
    process.stdin.pause();
    console.log(`Switched to ${target}${target === 'sbx' ? ` ${sandboxNumber(targetProfile.hostname)}` : ''}.`);
  };

  const focusNextMissing = () => {
    const next = values.findIndex((field, position) => position > index && !field.value);
    if (next >= 0) return next;
    return values.findIndex((field) => !field.value);
  };

  const applyInput = (value, wasPaste = false) => {
    input = value.replace(/[\r\n]/g, '');
    values[index].value = input;
    render();
    if (wasPaste) {
      if (!missing().length) submit();
      else {
        const next = focusNextMissing();
        if (next >= 0) { index = next; input = values[index].value; render(); }
      }
    }
  };

  const move = (delta) => {
    values[index].value = input;
    index = (index + delta + values.length) % values.length;
    input = values[index].value;
    render();
  };

  const enter = () => {
    values[index].value = input;
    const next = focusNextMissing();
    if (next >= 0) { index = next; input = values[index].value; render(); }
    else submit();
  };

  let buffer = '';
  const handle = (data) => {
    buffer += data.toString('utf8');
    while (buffer) {
      if (buffer.startsWith('\x1b[200~')) {
        const end = buffer.indexOf('\x1b[201~', 6);
        if (end < 0) return;
        applyInput(buffer.slice(6, end), true);
        buffer = buffer.slice(end + 6);
        continue;
      }
      if (buffer.startsWith('\x1b[Z')) { move(-1); buffer = buffer.slice(3); continue; }
      if (buffer.startsWith('\x1b')) { cancel(); return; }
      const character = buffer[0]; buffer = buffer.slice(1);
      if (character === '\u0003' || character === '\u0004') { cancel(); return; }
      if (character === '\r' || character === '\n') { enter(); continue; }
      if (character === '\t') { move(1); continue; }
      if (character === '\u007f' || character === '\b') { input = input.slice(0, -1); applyInput(input); continue; }
      if (character >= ' ') { input += character; applyInput(input); }
    }
  };

  process.stdout.write('\x1b[?2004h\x1b[?25l');
  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.on('data', handle);
  render();
}

const root = process.argv[2];
const requestedTarget = process.argv[3];
if (!root || !['dev', 'sbx', '--migrate', undefined].includes(requestedTarget)) {
  usage(); process.exit(2);
}
if (requestedTarget === '--migrate') migrate(root);
else setup(root, requestedTarget);
