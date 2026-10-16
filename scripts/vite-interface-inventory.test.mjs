import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, rmSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
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
