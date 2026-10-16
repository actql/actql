import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync, mkdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {installedInterfaceInventory} from './installed-interface-inventory.mjs';
import {pythonInterfaceSources} from './python-interface-sources.mjs';

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

test('normal Python source roots are parsed without importing product or Local engines', () => {
  const result = pythonInterfaceSources(process.cwd());
  assert(result.roots.length >= 3);
  assert(result.modules.some(value => value.module.endsWith('/_local_core.py')));
});
