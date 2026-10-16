import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {createRequire} from 'node:module';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {test} from 'node:test';
import {viteInterfaceInventory} from './vite-interface-inventory.mjs';
import {assertInterfaceCoverage, interfaceAttributes} from './interface-inventory.mjs';

function fixture(t) {
  const directory = mkdtempSync(join(process.cwd(), '_build/interface-vite-control-'));
  t.after(() => rmSync(directory, {recursive: true}));
  const put = (path, body) => {
    mkdirSync(join(directory, path, '..'), {recursive: true});
    writeFileSync(join(directory, path), body);
  };
  put('vite.config.mjs', `export default {root: import.meta.dirname, build: {
    lib: {entry: new URL('./sdk/entry.mjs', import.meta.url).pathname, formats: ['es'], fileName: 'sdk'}}};`);
  put('owner.md', 'Existing pure view owner and independent boundary checks');
  put('sdk/entry.mjs', 'export function read(value) {return value;}');
  const ref = {path: 'owner.md', anchor: 'Existing pure view owner'};
  const declaration = module => ({...module, role: 'observation-presentation', owner: 'existing-view',
    contracts: [{operations: ['<module>', ...module.operations.map(value => value.name)], exports: module.exports,
      attributes: Object.fromEntries(interfaceAttributes.map(name => [name, [ref]]))}]});
  return {directory, put, declaration};
}

test('configured Vite closure retains neutral outside-directory helpers and rejects missing registration', async t => {
  const {directory, put, declaration} = fixture(t);
  const before = await viteInterfaceInventory(directory, ['vite.config.mjs']);
  assert.deepEqual(before.buildInputs.map(value => value.module), ['vite.config.mjs']);
  assert(!before.modules.some(value => value.module === 'vite.config.mjs'));
  const declared = before.modules.map(declaration);
  put('sdk/entry.mjs', 'export {read} from "../outside/neutral.mjs";');
  put('outside/neutral.mjs', 'export function read(value) {return value;}');
  const after = await viteInterfaceInventory(directory, ['vite.config.mjs']);
  assert(after.modules.some(value => value.module === 'outside/neutral.mjs'));
  const current = after.modules.map(module => declared.find(value => value.module === module.module)
    ? declaration(module) : null).filter(Boolean);
  assert.throws(() => assertInterfaceCoverage({root: directory, modules: after.modules, declarations: current}),
    /Unregistered distributed interface: outside\/neutral.mjs/u);
  assert.equal(assertInterfaceCoverage({root: directory, modules: after.modules,
    declarations: after.modules.map(declaration)}), after.modules.length);
});

test('configured Vite closure refuses outside-directory test authority at its policy assertion', async t => {
  const {directory, put} = fixture(t);
  put('sdk/entry.mjs', 'export {read} from "../other/authority.test.mjs";');
  put('other/authority.test.mjs', 'export function read(value) {return value;}');
  await assert.rejects(viteInterfaceInventory(directory, ['vite.config.mjs']),
    /Test authority in Vite interface: other\/authority.test.mjs/u);
});

test('configured Vite dependencies match ordinary manifest working directories without ignoring changed output', async t => {
  const {directory, put} = fixture(t);
  put('library/package.json', '{"type":"module"}');
  put('library/source.mjs', 'export function read(value) {return value + 1;}');
  put('library/vite.config.mjs', `export default {root: import.meta.dirname, build: {
    minify: false, lib: {entry: new URL('./source.mjs', import.meta.url).pathname,
      formats: ['es'], fileName: 'library'}}};`);
  put('sdk/entry.mjs', 'export {read} from "../library/dist/library.js";');
  const vite = join(dirname(createRequire(import.meta.url).resolve('vite/package.json')), 'bin/vite.js');
  execFileSync(process.execPath, [vite, 'build', '--config', 'vite.config.mjs'], {
    cwd: join(directory, 'library'), timeout: 30000, stdio: 'pipe'});
  const configs = ['library/vite.config.mjs', 'vite.config.mjs'];
  await assert.rejects(viteInterfaceInventory(directory, configs), /Mixed configured Vite dependency/u);
  const checked = await viteInterfaceInventory(directory, configs,
    {workingDirectories: {'library/vite.config.mjs': 'library'}});
  assert.equal(checked.consumedCompiled.length, 1);
  assert.equal(checked.consumedCompiled[0].sha256, createHash('sha256')
    .update(readFileSync(join(directory, 'library/dist/library.js'))).digest('hex'));
  put('library/dist/library.js', 'export function read(value) {return value + 2;}');
  await assert.rejects(viteInterfaceInventory(directory, configs,
    {workingDirectories: {'library/vite.config.mjs': 'library'}}), /Mixed configured Vite dependency/u);
});

function foreignFixture(t) {
  const project = fixture(t);
  const foreign = mkdtempSync(join(process.cwd(), '_build/interface-vite-foreign-'));
  t.after(() => rmSync(foreign, {recursive: true}));
  return {...project, foreign};
}

test('configured Vite closure refuses checkout-external test authority before external counting', async t => {
  const {directory, put, foreign} = foreignFixture(t);
  writeFileSync(join(foreign, 'outcome.test.mjs'), 'export function read(value) {return value;}');
  put('sdk/entry.mjs', `export {read} from ${JSON.stringify(join(foreign, 'outcome.test.mjs'))};`);
  await assert.rejects(viteInterfaceInventory(directory, ['vite.config.mjs']),
    /Test authority in Vite interface: .*outcome\.test\.mjs/u);
});

test('configured Vite closure refuses neutral foreign source without installed provenance', async t => {
  const {directory, put, foreign} = foreignFixture(t);
  writeFileSync(join(foreign, 'neutral.mjs'), 'export function read(value) {return value;}');
  put('sdk/entry.mjs', `export {read} from ${JSON.stringify(join(foreign, 'neutral.mjs'))};`);
  await assert.rejects(viteInterfaceInventory(directory, ['vite.config.mjs']), /Unregistered Vite source/u);
});

test('configured Vite closure identifies pinned installed inputs without admitting a foreign namesake', async t => {
  const {directory, put, foreign} = foreignFixture(t);
  const dependency = join(foreign, 'installed');
  mkdirSync(dependency);
  const manifest = {name: 'neutral-dependency', version: '1.0.0', type: 'module', exports: './neutral.mjs'};
  writeFileSync(join(dependency, 'package.json'), JSON.stringify(manifest));
  writeFileSync(join(dependency, 'neutral.mjs'), 'export function read(value) {return value;}');
  mkdirSync(join(directory, 'node_modules'));
  symlinkSync(dependency, join(directory, 'node_modules/neutral-dependency'));
  put('package-lock.json', JSON.stringify({lockfileVersion: 3, packages: {
    'node_modules/neutral-dependency': {version: '1.0.0', resolved: 'https://example.invalid/neutral.tgz',
      integrity: 'sha512-synthetic-lock-pin'}}}));
  put('sdk/entry.mjs', 'export {read} from "neutral-dependency";');
  const admitted = await viteInterfaceInventory(directory, ['vite.config.mjs']);
  assert.equal(admitted.externalModuleCount, 1);
  assert.deepEqual(admitted.externalModules.map(({installation, name, version, member}) =>
    ({installation, name, version, member})), [{installation: 'node_modules/neutral-dependency',
    name: 'neutral-dependency', version: '1.0.0', member: 'neutral.mjs'}]);
  assert.match(admitted.externalModules[0].sha256, /^[a-f0-9]{64}$/u);
  // The lock pin identifies the actual installation, not a package.json name
  // supplied by another authored directory. This is not archive verification.
  writeFileSync(join(foreign, 'package.json'), JSON.stringify(manifest));
  writeFileSync(join(foreign, 'neutral.mjs'), 'export function read(value) {return value;}');
  put('sdk/entry.mjs', `export {read} from ${JSON.stringify(join(foreign, 'neutral.mjs'))};`);
  await assert.rejects(viteInterfaceInventory(directory, ['vite.config.mjs']), /Unregistered Vite source/u);
  put('sdk/entry.mjs', 'export {read} from "neutral-dependency";');
  writeFileSync(join(dependency, 'package.json'), JSON.stringify({...manifest, version: '2.0.0'}));
  await assert.rejects(viteInterfaceInventory(directory, ['vite.config.mjs']), /Mixed installed Vite dependency/u);
});
