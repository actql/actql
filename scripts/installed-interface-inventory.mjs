// Read actual installed members, including dormant helpers. Callers retain the
// existing package/wheel/CLI/Cloud artifact validators; this does not mint an
// adopted artifact set from filenames or equal package versions.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {closeSync, constants, fstatSync, lstatSync, openSync, readFileSync, readdirSync, readSync, realpathSync} from 'node:fs';
import {relative, resolve} from 'node:path';
import {javascriptInterface, packageEntrances} from './interface-inventory.mjs';
import {typescriptInterface} from './typescript-interface-inventory.mjs';
import {pythonModuleInterfaces} from './python-interface-sources.mjs';

function artifactDigest(path) {
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const before = fstatSync(fd);
    assert(before.isFile(), 'Compiled interface must be a regular file');
    const digest = createHash('sha256'), buffer = Buffer.alloc(1024 * 1024);
    let read;
    while ((read = readSync(fd, buffer, 0, buffer.length, null))) digest.update(buffer.subarray(0, read));
    const after = fstatSync(fd);
    assert(before.size === after.size && before.mtimeMs === after.mtimeMs,
      'Compiled interface changed during inventory');
    return digest.digest('hex');
  } finally { closeSync(fd); }
}

export function installedInterfaceInventory(directory, {artifacts = []} = {}) {
  assert(!lstatSync(directory).isSymbolicLink(), 'Installed interface root must not be a link');
  const root = realpathSync(directory), files = [], modules = [], generated = [];
  const manifest = JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8'));
  const entrances = packageEntrances(manifest, root).map(path => relative(root, path));
  const commands = new Set(packageEntrances({bin: manifest.bin}, root).map(path => relative(root, path)));
  const executableMembers = new Set();
  function walk(path) {
    for (const entry of readdirSync(path, {withFileTypes: true})) {
      const file = resolve(path, entry.name), stat = lstatSync(file);
      assert(!stat.isSymbolicLink(), `Linked distributed member: ${relative(root, file)}`);
      if (stat.isDirectory()) walk(file);
      else {
        assert(stat.isFile(), 'Special file in installed interface');
        files.push(relative(root, file));
        if (stat.mode & 0o111) executableMembers.add(relative(root, file));
      }
    }
  }
  walk(root);
  for (const entrance of entrances) assert(files.includes(entrance), `Missing installed interface entrance: ${entrance}`);
  const binary = /\.(?:wasm|cwasm|node|dylib|so|dll|exe)$/u;
  const python = [];
  for (const module of files.sort()) {
    const proof = artifacts.find(value => value.module === module);
    if (proof || binary.test(module)) {
      assert(proof && /^[0-9a-f]{40}$/u.test(proof.sourceSha) && typeof proof.target === 'string' &&
        proof.target.length && proof.verification,
        `Unregistered compiled interface artifact: ${module}`);
      const sha256 = artifactDigest(resolve(root, module));
      assert.equal(sha256, proof.sha256, `Mixed interface artifact: ${module}`);
      generated.push({...proof, module, sha256});
      continue;
    }
    if (/\.pyi?$/u.test(module)) {
      python.push(module);
      continue;
    }
    const script = /\.(?:[cm]?js|[cm]?tsx?|[ch])$/u.test(module);
    // Manifest commands and executable members cannot disappear merely because
    // they have no extension. Recognize only the existing Node/Python readers;
    // other execution formats require their ordinary artifact owner binding.
    const executable = commands.has(module) || executableMembers.has(module) ||
      entrances.includes(module) && !/\.[^/]+$/u.test(module);
    if (!script && !executable) continue;
    const bytes = readFileSync(resolve(root, module)), sha256 = createHash('sha256').update(bytes).digest('hex');
    if (!script) {
      const line = bytes.subarray(0, 256).toString('utf8').split(/\r?\n/u, 1)[0];
      if (/^#!(?:\/usr\/bin\/env[ \t]+python3?|\/usr\/bin\/python3?)(?:[ \t]|$)/u.test(line)) {
        python.push(module);
        continue;
      }
      assert(/^#!(?:\/usr\/bin\/env[ \t]+node|\/usr\/bin\/node)(?:[ \t]|$)/u.test(line),
        `Unregistered executable interface: ${module}`);
    }
    const syntax = /\.[cm]?tsx?$/u.test(module) ? typescriptInterface(bytes.toString('utf8'), module)
      : /\.[ch]$/u.test(module)
        ? {exports: [], operations: [], imports: [], qualification: 'native-source-requires-owner-declaration'}
        : javascriptInterface(bytes.toString('utf8'));
    modules.push({module, sha256, ...syntax});
  }
  modules.push(...pythonModuleInterfaces(root, python));
  for (const command of commands) assert(modules.some(value => value.module === command) ||
    generated.some(value => value.module === command), `Unregistered executable interface: ${command}`);
  for (const proof of artifacts) assert(files.includes(proof.module), `Missing declared interface artifact: ${proof.module}`);
  return {qualification: 'installed-member-syntax-only', name: manifest.name, entrances,
    modules: modules.sort((a, b) => a.module.localeCompare(b.module)), artifacts: generated};
}
