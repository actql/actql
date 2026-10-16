import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {assertInterfaceCoverage, interfaceAttributes, javascriptClosure,
  javascriptInterface, packageEntrances} from './interface-inventory.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-if-coverage-'));
  t.after(() => rmSync(root, {recursive: true}));
  function put(path, body) {
    mkdirSync(join(root, path, '..'), {recursive: true});
    writeFileSync(join(root, path), body);
  }
  put('owner.md', 'Existing owner contract and real boundary verification');
  const ref = {path: 'owner.md', anchor: 'Existing owner contract'};
  const declaration = module => ({module: module.module, sha256: module.sha256, role: 'physical-io', owner: 'existing-owner',
    exports: module.exports, operations: module.operations, contracts: [{
      operations: ['<module>', ...module.operations.map(value => value.name)], exports: module.exports,
      attributes: Object.fromEntries(interfaceAttributes.map(key => [key, [ref]]))}]});
  return {root, put, declaration, ref};
}

test('all export conditions, public types and CLI bins define entrances', () => {
  assert.deepEqual(packageEntrances({exports: {'.': {node: './node.mjs', default: './web.mjs',
    types: './index.d.ts'}}, bin: {actql: 'bin/cli.mjs'}}).map(path => path.split('/').at(-1)),
  ['cli.mjs', 'index.d.ts', 'node.mjs', 'web.mjs']);
  assert.throws(() => packageEntrances({exports: '../other.mjs'}), /Nonlocal distribution entrance/u);
});

test('actual resolver retains outside-directory neutral helpers and private operations', t => {
  const {root, put, declaration} = fixture(t);
  put('sdk/entry.mjs', "export {read} from '../outside/helper.mjs';");
  put('outside/helper.mjs', 'function validate(value) {return value;} export function read(value) {return validate(value);}');
  const modules = javascriptClosure(root, ['sdk/entry.mjs']);
  assert.deepEqual(modules.map(value => value.module), ['outside/helper.mjs', 'sdk/entry.mjs']);
  assert.deepEqual(modules[0].operations.map(value => value.name), ['read', 'validate']);
  assert.equal(assertInterfaceCoverage({root, modules, declarations: modules.map(declaration)}), 2);
});

test('outside-directory test authority fails the intended policy assertion', t => {
  const {root, put} = fixture(t);
  put('sdk/entry.mjs', "export {decide} from '../packages/other/owner.test.mjs';");
  put('packages/other/owner.test.mjs', 'export const decide = () => true;');
  assert.throws(() => javascriptClosure(root, ['sdk/entry.mjs']), /Test authority in distributed interface/u);
});

test('new outside-directory product module cannot inherit the entry classification', t => {
  const {root, put, declaration} = fixture(t);
  put('sdk/entry.mjs', 'export function read() {}');
  const registered = javascriptClosure(root, ['sdk/entry.mjs']).map(declaration);
  put('sdk/entry.mjs', "import '../different/new-host.mjs'; export function read() {}");
  put('different/new-host.mjs', 'function authorize() {return true;} authorize();');
  assert.throws(() => assertInterfaceCoverage({root, modules: javascriptClosure(root, ['sdk/entry.mjs']),
    declarations: registered}), /Unregistered distributed interface: different\/new-host.mjs/u);
});

test('new helper inside an already classified module fails operation coverage', t => {
  const {root, put, declaration} = fixture(t);
  put('entry.mjs', 'export function read() {}');
  const declarations = javascriptClosure(root, ['entry.mjs']).map(declaration);
  put('entry.mjs', 'function decideUnknown() {return true;} export function read() {return decideUnknown();}');
  const modules = javascriptClosure(root, ['entry.mjs']);
  declarations[0].sha256 = modules[0].sha256;
  assert.throws(() => assertInterfaceCoverage({root, modules, declarations}),
    /Unregistered interface operation/u);
});

test('new export fails even when its helper was already registered', t => {
  const {root, put, declaration} = fixture(t);
  put('entry.mjs', 'function read() {} read();');
  const declarations = javascriptClosure(root, ['entry.mjs']).map(declaration);
  put('entry.mjs', 'export function read() {} read();');
  const modules = javascriptClosure(root, ['entry.mjs']);
  declarations[0].sha256 = modules[0].sha256;
  assert.throws(() => assertInterfaceCoverage({root, modules, declarations}),
    /Unregistered interface export/u);
});

test('new decision hidden inside an existing function requires a fresh owner review', t => {
  const {root, put, declaration} = fixture(t);
  put('entry.mjs', 'export function outcome(value) {return value;}');
  const declarations = javascriptClosure(root, ['entry.mjs']).map(declaration);
  put('entry.mjs', 'export function outcome(value) {return value === "Unknown" ? "Success" : value;}');
  assert.throws(() => assertInterfaceCoverage({root, modules: javascriptClosure(root, ['entry.mjs']), declarations}),
    /Unreviewed interface implementation/u);
});

test('module attribute references cannot stand in for missing operation contracts', t => {
  const {root, put, declaration} = fixture(t);
  put('entry.mjs', 'export function first() {} export function second() {}');
  const modules = javascriptClosure(root, ['entry.mjs']);
  const declarations = modules.map(declaration);
  declarations[0].contracts[0].operations = ['<module>', 'first'];
  assert.throws(() => assertInterfaceCoverage({root, modules, declarations}), /Missing operation contract/u);
});

test('references require all ten attributes and existing owner anchors', t => {
  const {root, put, declaration} = fixture(t);
  put('entry.mjs', 'export function read() {}');
  const modules = javascriptClosure(root, ['entry.mjs']);
  const decl = declaration(modules[0]);
  delete decl.contracts[0].attributes.failure;
  assert.throws(() => assertInterfaceCoverage({root, modules, declarations: [decl]}), /Incomplete interface attributes/u);
  decl.contracts[0].attributes.failure = [{path: 'owner.md', anchor: 'Imagined semantic guarantee'}];
  assert.throws(() => assertInterfaceCoverage({root, modules, declarations: [decl]}), /Missing interface reference/u);
});

test('compiler internals require owner-verified generated bytes, not a filename or comment', t => {
  const {root, put, declaration, ref} = fixture(t);
  put('shim.generated.mjs', '// Generated\nexport function read(value) { return value["$tag"] === 1 ? value._0 : null; }');
  const modules = javascriptClosure(root, ['shim.generated.mjs']);
  const decl = declaration(modules[0]);
  assert.throws(() => assertInterfaceCoverage({root, modules, declarations: [decl]}),
    /Compiler representation outside generated binding/u);
  decl.role = 'generated-binding';
  assert.throws(() => assertInterfaceCoverage({root, modules, declarations: [decl]}), /Unverified generated binding/u);
  const proof = {module: modules[0].module, sha256: modules[0].sha256, generator: ref, freshness: ref};
  assert.equal(assertInterfaceCoverage({root, modules, declarations: [decl], generated: [proof]}), 1);
  proof.sha256 = '0'.repeat(64);
  assert.throws(() => assertInterfaceCoverage({root, modules, declarations: [decl], generated: [proof]}),
    /Unverified generated binding/u);
});

test('syntax parser distinguishes actual field reads from comments and string data', () => {
  assert.deepEqual(javascriptInterface('export const text = "$tag _0"; // x._0').compilerFields, []);
  assert.deepEqual(javascriptInterface('const {$tag, _0: value} = input;').compilerFields, ['$tag', '_0']);
  assert.deepEqual(javascriptInterface("const {['$tag']: tag} = input;").compilerFields, ['$tag']);
});

test('namespace reexports and class methods retain their actual public names', () => {
  const before = javascriptInterface('export * as First from "./member.mjs"; export class Host { read() {} }');
  const after = javascriptInterface('export * as Second from "./member.mjs"; export class Host { write() {} }');
  assert.notDeepEqual(before.exports, after.exports);
  assert.notDeepEqual(before.operations, after.operations);
});

test('real stdlib wheel and source readers verify seven independent Python controls', () => {
  const result = spawnSync('python3', ['-B', '-m', 'unittest', 'discover', '-s', 'scripts',
    '-p', 'test_python_interface_inventory.py', '-v'], {encoding: 'utf8', timeout: 30000});
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stderr, /Ran 7 tests/u);
});
