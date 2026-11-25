import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {assertInterfaceCoverage, interfaceAttributes} from './interface-inventory.mjs';
import {typescriptInterface, typescriptInterfaceClosure, typescriptInterfaceInputs} from './typescript-interface-inventory.mjs';

for (const [name, source] of [
  ['import type query', 'export type View = import("../outside/owner.js").Host;'],
  ['triple slash reference', '/// <reference path="../outside/owner.d.ts" />\nexport interface View {}'],
  ['external module reference', 'import Host = require("../outside/owner.cjs"); export {Host};'],
] as const) {
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

test('installed declarations follow relative siblings and leave bare dependency packages external', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-if-installed-types-'));
  t.after(() => rmSync(root, {recursive: true}));
  const installed = join(root, 'node_modules/@actql/sdk');
  const peer = join(root, 'node_modules/@actql/client-wire');
  mkdirSync(join(installed, 'internal'), {recursive: true});
  mkdirSync(peer);
  writeFileSync(join(installed, 'package.json'), '{"name":"@actql/sdk","type":"module"}');
  writeFileSync(join(peer, 'package.json'), '{"name":"@actql/client-wire","types":"./index.d.ts"}');
  writeFileSync(join(peer, 'index.d.ts'), 'export interface Wire {}');
  const member = 'internal/transport.d.mts', sibling = join(installed, 'host-port.d.mts');
  writeFileSync(join(installed, member),
    'export type Port = import("../host-port.d.mts").Host | import("@actql/client-wire").Wire;');
  writeFileSync(sibling, 'export interface Host { open(): void; }');
  const checked = typescriptInterfaceInputs(installed, [member]);
  assert.deepEqual(checked.modules.map(value => value.module), ['host-port.d.mts', member]);
  assert.deepEqual(checked.external.map(value => value.specifier), ['@actql/client-wire']);

  rmSync(sibling);
  assert.throws(() => typescriptInterfaceInputs(installed, [member]),
    /Unresolved TypeScript interface dependency: internal\/transport.d.mts:\.\.\/host-port.d.mts/u);
  symlinkSync(join(peer, 'index.d.ts'), sibling);
  assert.throws(() => typescriptInterfaceInputs(installed, [member]), /Escaped TypeScript interface/u);
});

test('a selected emitted declaration follows the public edge without admitting private runtime imports', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-if-published-types-'));
  t.after(() => rmSync(root, {recursive: true}));
  writeFileSync(join(root, 'index.d.ts'), 'export {connect} from "./host-port.mjs";');
  writeFileSync(join(root, 'host-port.mts'), 'export {connect} from "./runtime.mjs";');
  writeFileSync(join(root, 'runtime.mts'), 'export function connect() {}');
  writeFileSync(join(root, 'host-port.d.mts'), 'export declare function connect(): void;');
  const entrances = ['index.d.ts', 'host-port.d.mts'];
  const source = typescriptInterfaceInputs(root, entrances);
  assert.deepEqual(source.modules.map(value => value.module),
    ['host-port.d.mts', 'host-port.mts', 'index.d.ts', 'runtime.mts']);
  const published = typescriptInterfaceInputs(root, entrances, ['host-port.d.mts']);
  assert.deepEqual(published.modules.map(value => value.module), ['host-port.d.mts', 'index.d.ts']);
  assert.throws(() => typescriptInterfaceInputs(root, entrances, ['runtime.d.mts']), /Unknown public TypeScript declaration/u);
  rmSync(join(root, 'host-port.d.mts'));
  assert.throws(() => typescriptInterfaceInputs(root, entrances, ['host-port.d.mts']), /ENOENT/u);
});

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
] as const) {
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
    "Reflect.get(value, '_' + index)"] as const) {
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


test('authored TypeScript fixture forms refuse direct and resolved interface authority', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-if-fixture-'));
  t.after(() => rmSync(root, {recursive: true}));
  writeFileSync(join(root, 'tsconfig.json'), JSON.stringify({compilerOptions: {
    moduleResolution: 'Bundler', allowJs: true}}));
  writeFileSync(join(root, 'entry.ts'), 'export {value} from "./owner.mjs";');
  writeFileSync(join(root, 'owner.mts'), 'export const value = 1;');
  assert.deepEqual(typescriptInterfaceInputs(root, ['entry.ts']).modules.map(value => value.module),
    ['entry.ts', 'owner.mts']);
  for (const [filename, specifier] of [
    ['esm.fixture.mts', './esm.fixture.mjs'],
    ['common-fixture.cts', './common-fixture.cjs'],
    ['plain.fixture.ts', './plain.fixture.js'],
    ['component-fixture.tsx', './component-fixture.jsx'],
    ['original.fixture.mjs', './original.fixture.mjs'],
  ] as const) {
    writeFileSync(join(root, filename), 'export const value = 1;');
    assert.throws(() => typescriptInterfaceInputs(root, [filename]), /Test authority in TypeScript interface/u);
    writeFileSync(join(root, 'entry.ts'), `export {value} from "${specifier}";`);
    assert.throws(() => typescriptInterfaceInputs(root, ['entry.ts']), /Test authority in TypeScript interface/u);
  }
});


test('TS erased expression wrappers retain only actual literal dependency and field syntax', () => {
  const syntax = typescriptInterface(`
    const a = import("./owner.mjs" as string);
    const b = import(("./owner.mjs" satisfies string)!);
    const c = require(<string>"./owner.mjs");
    const field = value[("_" + 0) as string];
  `);
  assert.deepEqual(syntax.imports, ['./owner.mjs']);
  assert.deepEqual(syntax.compilerFields, ['_0']);
  assert.equal(syntax.unresolvedSyntax, undefined);
  const dynamic = typescriptInterface('const a = import(selected as "./owner.mjs");');
  assert.deepEqual(dynamic.imports, []);
  assert.equal(dynamic.unresolvedSyntax?.length, 1, 'asserted types do not supply runtime import values');
  assert.deepEqual(typescriptInterface('value[selected as "_0"]').compilerFields, []);
});

test('actual TS closure resolves type-wrapped literal imports and still refuses fixture authority', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-if-wrapped-'));
  t.after(() => rmSync(root, {recursive: true}));
  writeFileSync(join(root, 'tsconfig.json'), JSON.stringify({compilerOptions: {moduleResolution: 'Bundler'}}));
  writeFileSync(join(root, 'owner.mts'), 'export const value = 1;');
  writeFileSync(join(root, 'entry.mts'), 'export const read = () => import("./owner.mjs" as string);');
  assert.deepEqual(typescriptInterfaceInputs(root, ['entry.mts']).modules.map(value => value.module),
    ['entry.mts', 'owner.mts']);
  writeFileSync(join(root, 'owner.fixture.mts'), 'export const value = 1;');
  writeFileSync(join(root, 'entry.mts'), 'export const read = () => import("./owner.fixture.mjs" as string);');
  assert.throws(() => typescriptInterfaceInputs(root, ['entry.mts']), /Test authority in TypeScript interface/u);
});


test('TS erased dynamic compiler fields retain the original bounded representation policy', () => {
  for (const source of [
    'value[("_" + selected) as string]',
    'value[("_" + selected)!]',
    'value[<string>("_" + selected)]',
    'Reflect.get(value, (`_${selected}` satisfies string))',
    'Object.getOwnPropertyDescriptor(value, (`_${selected}` as string))',
  ]) {
    assert.deepEqual(typescriptInterface(source).compilerFields, ['_<dynamic>'], source);
  }
  for (const source of ['value[selected as "_0"]', 'Reflect.get(value, selected satisfies "_0")',
    'value[("column_" + selected) as string]']) {
    assert.deepEqual(typescriptInterface(source).compilerFields, [], source);
  }
});

test('TS wrapped dynamic field access still requires actual generated-binding proof', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-if-dynamic-'));
  t.after(() => rmSync(root, {recursive: true}));
  writeFileSync(join(root, 'owner.md'), 'Existing generator and freshness boundary');
  const ref = {path: 'owner.md', anchor: 'Existing generator and freshness boundary'};
  for (const expression of ['input[("_" + selected) as string]',
    'Reflect.get(input, (`_${selected}` satisfies string))']) {
    const source = `export const value = ${expression};`;
    const module = {module: 'entry.mts', sha256: createHash('sha256').update(source).digest('hex'),
      ...typescriptInterface(source, 'entry.mts')};
    const declaration = {module: module.module, role: 'physical-io', owner: 'original-generator',
      exports: module.exports, operations: module.operations, contracts: [{
        operations: ['<module>', ...module.operations.map(value => value.name)], exports: module.exports,
        attributes: Object.fromEntries(interfaceAttributes.map(key => [key, [ref]])),
      }]};
    assert.throws(() => assertInterfaceCoverage({root, modules: [module], declarations: [declaration]}),
      /Compiler representation outside generated binding/u);
    declaration.role = 'generated-binding';
    assert.throws(() => assertInterfaceCoverage({root, modules: [module], declarations: [declaration]}),
      /Unverified generated binding/u);
    const proof = {module: module.module, sha256: module.sha256, generator: ref, freshness: ref};
    assert.equal(assertInterfaceCoverage({root, modules: [module], declarations: [declaration],
      generated: [proof]}), 1);
    assert.throws(() => assertInterfaceCoverage({root, modules: [module], declarations: [declaration],
      generated: [{...proof, sha256: '0'.repeat(64)}]}), /Unverified generated binding/u);
  }
});
