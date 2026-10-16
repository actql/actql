import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {chmodSync, mkdtempSync, mkdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {installedInterfaceInventory} from './installed-interface-inventory.mjs';
import {pythonInterfaceSources} from './python-interface-sources.mjs';
import {assertInterfaceCoverage} from './interface-inventory.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-if-installed-'));
  t.after(() => rmSync(root, {recursive: true}));
  const put = (name, text) => {
    mkdirSync(join(root, name, '..'), {recursive: true});
    writeFileSync(join(root, name), text);
  };
  put('package.json', JSON.stringify({name: '@actql/fixture', exports: './entry.mjs'}));
  put('entry.mjs', 'export function read() {}');
  return {root, put};
}

test('actual members include dormant JavaScript, Python and native helper additions', t => {
  const {root, put} = fixture(t);
  put('outside/private-helper.mjs', 'function decideUnknown() {return true;}');
  put('outside/python_helper.py', 'def decide_unknown(value):\n    return value\n');
  put('outside/helper.c', 'int decide_unknown(int value) { return value; }');
  const result = installedInterfaceInventory(root);
  assert.equal(result.qualification, 'installed-member-syntax-only');
  assert.deepEqual(result.modules.map(value => value.module),
    ['entry.mjs', 'outside/helper.c', 'outside/private-helper.mjs', 'outside/python_helper.py']);
  assert.equal(result.modules.at(-1).operations[0].name, 'decide_unknown');
});

test('compiled artifact mixing fails the declared artifact assertion, not a parser error', t => {
  const {root, put} = fixture(t);
  put('runtime.wasm', Buffer.from([0, 97, 115, 109, 1, 0, 0, 0]));
  assert.throws(() => installedInterfaceInventory(root), /Unregistered compiled interface artifact/u);
  const proof = {module: 'runtime.wasm', sourceSha: 'a'.repeat(40), target: 'wasm',
    verification: {path: 'owner-receipt.json'}, sha256: '0'.repeat(64)};
  assert.throws(() => installedInterfaceInventory(root, {artifacts: [proof]}), /Mixed interface artifact/u);
  proof.sha256 = createHash('sha256').update(Buffer.from([0, 97, 115, 109, 1, 0, 0, 0])).digest('hex');
  assert.equal(installedInterfaceInventory(root, {artifacts: [proof]}).artifacts.length, 1);
});

test('missing real exported member refuses at the package entrance', t => {
  const {root, put} = fixture(t);
  put('package.json', JSON.stringify({name: '@actql/fixture', exports: './missing.mjs'}));
  assert.throws(() => installedInterfaceInventory(root), /Missing installed interface entrance/u);
});

test('extensionless Node and Python commands remain actual inventoried interfaces', t => {
  const {root, put} = fixture(t);
  put('package.json', JSON.stringify({name: '@actql/fixture', bin: {policy: 'bin/policy', probe: 'bin/probe'}}));
  put('bin/policy', '#!/usr/bin/env node\nexport function decideUnknown(value) {return value;}\n');
  put('bin/probe', '#!/usr/bin/env python3\ndef decide_unknown(value):\n    return value\n');
  const result = installedInterfaceInventory(root);
  assert.deepEqual(result.modules.find(value => value.module === 'bin/policy').operations.map(value => value.name),
    ['decideUnknown']);
  assert.deepEqual(result.modules.find(value => value.module === 'bin/probe').operations.map(value => value.name),
    ['decide_unknown']);
  assert.throws(() => assertInterfaceCoverage({root, modules: result.modules, declarations: []}),
    /Unregistered distributed interface: bin\/policy/u);
});

test('extensionless compiled commands require the same original artifact binding', t => {
  const {root, put} = fixture(t), bytes = Buffer.from([0x7f, 69, 76, 70, 0]);
  put('package.json', JSON.stringify({name: '@actql/fixture', bin: {actql: 'bin/actql-native-client'}}));
  put('bin/actql-native-client', bytes);
  assert.throws(() => installedInterfaceInventory(root), /Unregistered executable interface: bin\/actql-native-client/u);
  const proof = {module: 'bin/actql-native-client', sourceSha: 'a'.repeat(40), target: 'native',
    verification: {path: 'artifact.json'}, sha256: createHash('sha256').update(bytes).digest('hex')};
  const result = installedInterfaceInventory(root, {artifacts: [proof]});
  assert.equal(result.artifacts[0].module, 'bin/actql-native-client');
  assert.equal(result.qualification, 'installed-member-syntax-only');
});

test('unknown executable helpers and noncode commands refuse at the policy assertion', t => {
  const {root, put} = fixture(t);
  put('outside/policy', '#!/bin/sh\nexit 0\n');
  chmodSync(join(root, 'outside/policy'), 0o755);
  assert.throws(() => installedInterfaceInventory(root), /Unregistered executable interface: outside\/policy/u);
  chmodSync(join(root, 'outside/policy'), 0o644);
  put('package.json', JSON.stringify({name: '@actql/fixture', bin: {policy: 'policy.json'}}));
  put('policy.json', '{}');
  assert.throws(() => installedInterfaceInventory(root), /Unregistered executable interface: policy\.json/u);
});

test('normal Python source roots are parsed without importing product or Local engines', () => {
  const result = pythonInterfaceSources(process.cwd());
  assert(result.roots.length >= 3);
  assert(result.modules.some(value => value.module.endsWith('/_local_core.py')));
});
