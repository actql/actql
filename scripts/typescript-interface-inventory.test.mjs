import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {typescriptInterface, typescriptInterfaceClosure} from './typescript-interface-inventory.mjs';

for (const [name, source] of [
  ['import type query', 'export type View = import("../outside/owner.js").Host;'],
  ['triple slash reference', '/// <reference path="../outside/owner.d.ts" />\nexport interface View {}'],
  ['external module reference', 'import Host = require("../outside/owner.cjs"); export {Host};'],
]) {
  test(`actual TypeScript closure retains ${name} outside the entry directory`, t => {
    const root = mkdtempSync(join(tmpdir(), 'actql-if-types-'));
    t.after(() => rmSync(root, {recursive: true}));
    mkdirSync(join(root, 'sdk'));
    mkdirSync(join(root, 'outside'));
    writeFileSync(join(root, 'sdk/index.d.ts'), source);
    writeFileSync(join(root, 'outside/owner.d.ts'), 'export interface Host { read(): void; }');
    writeFileSync(join(root, 'outside/owner.d.cts'), 'declare class Host {read(): void;} export = Host;');
    const result = typescriptInterfaceClosure(root, ['sdk/index.d.ts']);
    assert.equal(result.length, 2);
    assert(result.some(value => value.module.startsWith('outside/owner.')));
  });
}

test('private TS arrow helpers and global declaration interfaces have actual names', () => {
  assert.equal(typescriptInterface('const decide = (run: string) => run;').operations[0].name, 'decide');
  assert.deepEqual(typescriptInterface('interface PublicHost {read(): void;}', 'global.d.ts').exports, ['PublicHost']);
  assert.deepEqual(typescriptInterface('export default class Host {}').exports, ['default']);
});

test('TS and reflective compiler field access require the same generated authority', () => {
  assert.deepEqual(typescriptInterface('export const value = Reflect.get(result, "$tag") || result._0;').compilerFields,
    ['$tag', '_0']);
});

test('TS closed literal and computed compiler fields cannot bypass the existing representation policy', () => {
  for (const source of ['value[`$tag`]', "value['_' + 0]", "Object.getOwnPropertyDescriptor(value, '$tag')?.value",
    'const {_0: item} = value;', 'const {_0} = value;', 'const item = {_0: value};', 'value[`_${index}`]',
    "Reflect.get(value, '_' + index)"]) {
    assert(typescriptInterface(source).compilerFields.length, `Missing TS compiler representation: ${source}`);
  }
  assert.deepEqual(typescriptInterface('export const wire = {name: "_0", text: "$tag"};').compilerFields, []);
  assert.deepEqual(typescriptInterface("value['_' + 'column']; const [_0] = input;").compilerFields, []);
});
