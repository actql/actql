// Read actual installed members, including dormant helpers. Callers retain the
// existing package/wheel/CLI/Cloud artifact validators; this does not mint an
// adopted artifact set from filenames or equal package versions.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstatSync, readFileSync, readdirSync, realpathSync} from 'node:fs';
import {relative, resolve} from 'node:path';
import {javascriptInterface, packageEntrances} from './interface-inventory.mjs';
import {typescriptInterface} from './typescript-interface-inventory.mjs';
import {pythonModuleInterfaces} from './python-interface-sources.mjs';

export function installedInterfaceInventory(directory, {artifacts = []} = {}) {
  assert(!lstatSync(directory).isSymbolicLink(), 'Installed interface root must not be a link');
  const root = realpathSync(directory), files = [], modules = [], generated = [];
  const manifest = JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8'));
  const entrances = packageEntrances(manifest, root).map(path => relative(root, path));
  function walk(path) {
    for (const entry of readdirSync(path, {withFileTypes: true})) {
      const file = resolve(path, entry.name), stat = lstatSync(file);
      assert(!stat.isSymbolicLink(), `Linked distributed member: ${relative(root, file)}`);
      if (stat.isDirectory()) walk(file);
      else {
        assert(stat.isFile(), 'Special file in installed interface');
        files.push(relative(root, file));
      }
    }
  }
  walk(root);
  for (const entrance of entrances) assert(files.includes(entrance), `Missing installed interface entrance: ${entrance}`);
  const binary = /\.(?:wasm|cwasm|node|dylib|so|dll|exe)$/u;
  for (const module of files.sort()) {
    const proof = artifacts.find(value => value.module === module);
    if (proof || binary.test(module)) {
      assert(proof && proof.sourceSha && proof.target && proof.verification,
        `Unregistered compiled interface artifact: ${module}`);
      const sha256 = createHash('sha256').update(readFileSync(resolve(root, module))).digest('hex');
      assert.equal(sha256, proof.sha256, `Mixed interface artifact: ${module}`);
      generated.push({...proof, module, sha256});
      continue;
    }
    if (!/\.(?:[cm]?js|[cm]?tsx?|[ch])$/u.test(module)) continue;
    const bytes = readFileSync(resolve(root, module)), sha256 = createHash('sha256').update(bytes).digest('hex');
    const syntax = /\.[cm]?tsx?$/u.test(module) ? typescriptInterface(bytes.toString('utf8'), module)
      : /\.[cm]?js$/u.test(module) ? javascriptInterface(bytes.toString('utf8'))
        : {exports: [], operations: [], imports: [], qualification: 'native-source-requires-owner-declaration'};
    modules.push({module, sha256, ...syntax});
  }
  modules.push(...pythonModuleInterfaces(root, files.filter(path => /\.pyi?$/u.test(path))));
  for (const proof of artifacts) assert(files.includes(proof.module), `Missing declared interface artifact: ${proof.module}`);
  return {qualification: 'installed-member-syntax-only', name: manifest.name, entrances,
    modules: modules.sort((a, b) => a.module.localeCompare(b.module)), artifacts: generated};
}
