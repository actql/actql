import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {typescriptInterface, typescriptInterfaceClosure, typescriptInterfaceInputs} from './typescript-interface-inventory.mjs';

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

test('TS destructured exports retain each actual local name instead of the entire binding text', () => {
  assert.deepEqual(typescriptInterface(`export const {value: renamed, nested: {id}, ...rest} = source;
    export const [first, , ...tail] = items; export const simple = () => 0;`).exports,
  ['first', 'id', 'renamed', 'rest', 'simple', 'tail']);
});

for (const [name, source, expected] of [
  ['typed object alias', 'export const {request: alias}: Protocol = protocol;', ['alias']],
  ['nested default and rest',
    'export const {request: {id: local = fallback, ...inner} = {}, ...outer}: Protocol = protocol;',
    ['inner', 'local', 'outer']],
  ['typed array holes and rest',
    'export const [first = fallback, , {id: renamed}, ...tail]: Items = items;',
    ['first', 'renamed', 'tail']],
  ['quoted and computed property aliases',
    'export const {"request-id": requestId, [key]: selected = fallback} = protocol;',
    ['requestId', 'selected']],
  ['multiple declarations and private bindings',
    'const {hidden} = protocol; export const {a: publicA} = protocol, [publicB] = items;',
    ['publicA', 'publicB']],
]) {
  test(`TS binding-pattern exports retain local names: ${name}`, () => {
    assert.deepEqual(typescriptInterface(source).exports, expected);
  });
}

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

test('actual TypeScript config aliases retain authored helpers and JSON input identity', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-if-config-'));
  t.after(() => rmSync(root, {recursive: true}));
  mkdirSync(join(root, 'sdk'));
  mkdirSync(join(root, 'outside'));
  writeFileSync(join(root, 'tsconfig.json'), JSON.stringify({compilerOptions: {
    moduleResolution: 'Bundler', resolveJsonModule: true, baseUrl: '.', paths: {'@/*': ['outside/*']}}}));
  writeFileSync(join(root, 'sdk/entry.ts'), 'export {decide} from "@/owner";');
  writeFileSync(join(root, 'outside/owner.ts'), 'import schema from "./schema.json"; export const decide = () => schema;');
  writeFileSync(join(root, 'outside/schema.json'), '{"field":"existing"}');
  const result = typescriptInterfaceInputs(root, ['sdk/entry.ts']);
  assert.deepEqual(result.modules.map(value => value.module), ['outside/owner.ts', 'sdk/entry.ts']);
  assert.equal(result.assets[0].module, 'outside/schema.json');
  assert.match(result.assets[0].sha256, /^[a-f0-9]{64}$/u);
  assert.equal(result.configs[0].module, 'tsconfig.json');
  assert.deepEqual(result.external, []);
  writeFileSync(join(root, 'sdk/entry.ts'), 'export {decide} from "@/owner.test";');
  writeFileSync(join(root, 'outside/owner.test.ts'), 'export const decide = () => "success";');
  assert.throws(() => typescriptInterfaceInputs(root, ['sdk/entry.ts']), /Test authority in TypeScript interface/u);
  writeFileSync(join(root, 'sdk/entry.ts'), 'export {decide} from "@/missing";');
  assert.throws(() => typescriptInterfaceInputs(root, ['sdk/entry.ts']), /Unresolved TypeScript configured alias/u);
});
