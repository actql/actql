import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {interfaceOwnerDeclarations} from './interface-owner-discovery.mjs';

test('actual owner declarations outside the original directories remain discoverable without role inference', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-owner-declarations-'));
  t.after(() => rmSync(root, {recursive: true}));
  const files = ['new-sdk/contracts/interface-boundaries.json', 'elsewhere/interface-boundaries.json',
    'another-owner/data-interface-boundaries.json',
    'fixtures/control/interface-boundaries.json'];
  for (const path of files) {
    mkdirSync(join(root, path, '..'), {recursive: true});
    writeFileSync(join(root, path), JSON.stringify([{module: 'explicitly-declared.mjs', owner: 'existing-owner'}]));
  }
  const result = interfaceOwnerDeclarations(root, files);
  assert.equal(result.length, 3);
  assert.equal(result[0].declarations[0].role, undefined, 'the loader cannot invent the missing role');
  assert.deepEqual(result.map(value => value.id), [...files.slice(0, 3)].sort());
});

test('an empty sidecar cannot silently grant module or operation coverage', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-empty-owner-'));
  t.after(() => rmSync(root, {recursive: true}));
  writeFileSync(join(root, 'interface-boundaries.json'), '{"declarations":[]}');
  assert.throws(() => interfaceOwnerDeclarations(root, ['interface-boundaries.json']), /Missing interface declarations/u);
});
