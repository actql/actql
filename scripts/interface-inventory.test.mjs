import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {moonOperations, moonApiInterface} from './moon-interface-inventory.mjs';
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
  const declaration = module => {
    const operations = module.operations.filter(value => !module.privateOperations?.includes(value.name));
    return {module: module.module, sha256: module.sha256, role: 'physical-io', owner: 'existing-owner',
      exports: module.exports, operations, contracts: [{
        operations: ['<module>', ...operations.map(value => value.name)], exports: module.exports,
        attributes: Object.fromEntries(interfaceAttributes.map(key => [key, [ref]]))}]};
  };
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

test('private helper additions and refactors remain with the existing module owner', t => {
  const {root, put, declaration} = fixture(t);
  put('entry.mjs', 'export function read() {}');
  const declarations = javascriptClosure(root, ['entry.mjs']).map(declaration);
  put('entry.mjs', 'function decideUnknown() {return true;} export function read() {return decideUnknown();}');
  const modules = javascriptClosure(root, ['entry.mjs']);
  assert.equal(assertInterfaceCoverage({root, modules, declarations}), 1);
});

test('private declarations and local arrows can change names parameters and existence', t => {
  const {root, put, declaration} = fixture(t);
  const original = 'function local(value) {return value;} const use = value => local(value); export function read(value) {return use(value);}';
  put('entry.mjs', original);
  const declarations = javascriptClosure(root, ['entry.mjs']).map(declaration);
  assert.deepEqual(declarations[0].operations.map(value => value.name), ['read']);
  for (const source of [
    'function renamed(value, extra) {return value;} const use = (value, extra) => renamed(value, extra); export function read(value) {return use(value);}',
    'export function read(value) {return value;}',
    'function unused(first, second) {} export function read(value) {return value;}',
  ]) {
    put('entry.mjs', source);
    assert.equal(assertInterfaceCoverage({root, modules: javascriptClosure(root, ['entry.mjs']), declarations}), 1);
  }
});

test('exported aliased returned and observed function signatures stay strict', t => {
  const {root, put, declaration} = fixture(t);
  for (const source of [
    'export function read(value) {return value;}',
    'const read = value => value; export {read};',
    'function control(value) {return value;} export function read() {return control;}',
    'export function read() {return function control(value) {return value;};}',
    'function control(value) {return value;} export function read() {return control.length;}',
    'export class Host {read(value) {return value;}}',
    'export const host = {read(value) {return value;}};',
  ]) {
    put('entry.mjs', source);
    const declarations = javascriptClosure(root, ['entry.mjs']).map(declaration);
    put('entry.mjs', source.replace('(value)', '(value, extra)').replace('value =>', '(value, extra) =>'));
    assert.throws(() => assertInterfaceCoverage({root, modules: javascriptClosure(root, ['entry.mjs']), declarations}),
      /Unregistered interface operation/u, source);
  }
});

test('a private function becoming escaped or an escaped function disappearing requires review', t => {
  const {root, put, declaration} = fixture(t);
  const privateSource = 'function control(value) {return value;} export function read(value) {return control(value);}';
  put('entry.mjs', privateSource);
  const privateDeclaration = javascriptClosure(root, ['entry.mjs']).map(declaration);
  const escaped = 'function control(value) {return value;} export function read(value) {return control;}';
  put('entry.mjs', escaped);
  const modules = javascriptClosure(root, ['entry.mjs']);
  assert.throws(() => assertInterfaceCoverage({root, modules, declarations: privateDeclaration}), /Unregistered interface operation/u);
  const escapedDeclaration = modules.map(declaration);
  put('entry.mjs', privateSource);
  assert.throws(() => assertInterfaceCoverage({root, modules: javascriptClosure(root, ['entry.mjs']), declarations: escapedDeclaration}), /Unregistered interface operation/u);
});

test('generated binding helper changes retain exact operation and generated-byte proof', t => {
  const {root, put, declaration, ref} = fixture(t);
  put('entry.mjs', 'function inner(value) {return value._0;} export function read(value) {return inner(value);}');
  const modules = javascriptClosure(root, ['entry.mjs']);
  const declared = declaration(modules[0]);declared.role = 'generated-binding';
  declared.operations = modules[0].operations;
  declared.contracts[0].operations = ['<module>', ...modules[0].operations.map(value => value.name)];
  const proof = {module:'entry.mjs',sha256:modules[0].sha256,generator:ref,freshness:ref};
  assert.equal(assertInterfaceCoverage({root, modules, declarations:[declared], generated:[proof]}),1);
  put('entry.mjs', 'function inner(value, extra) {return value._0;} export function read(value) {return inner(value);}');
  assert.throws(() => assertInterfaceCoverage({root, modules:javascriptClosure(root,['entry.mjs']), declarations:[declared],generated:[proof]}), /Unregistered interface operation/u);
});

test('direct eval retains lexical function contracts without a syntactic reference', t => {
  const {root, put, declaration} = fixture(t);
  const source = "function hidden(value) {return value;} export function read() {return eval('hidden');}";
  put('entry.mjs', source);
  const modules = javascriptClosure(root, ['entry.mjs']);
  assert.deepEqual(modules[0].privateOperations, []);
  const declarations = modules.map(declaration);
  put('entry.mjs', source.replace('hidden(value)', 'hidden(value, extra)'));
  assert.throws(() => assertInterfaceCoverage({root, modules:javascriptClosure(root,['entry.mjs']), declarations}), /Unregistered interface operation/u);
});

test('new export fails even when its helper was already registered', t => {
  const {root, put, declaration} = fixture(t);
  put('entry.mjs', 'function read() {} read();');
  const declarations = javascriptClosure(root, ['entry.mjs']).map(declaration);
  put('entry.mjs', 'export function read() {} read();');
  const modules = javascriptClosure(root, ['entry.mjs']);
  assert.throws(() => assertInterfaceCoverage({root, modules, declarations}),
    /Unregistered interface export/u);
});

test('handwritten implementation snapshots accept comments and internal refactors without claiming behavior', t => {
  const {root, put, declaration} = fixture(t);
  put('entry.mjs', 'export function outcome(value) {return value;}');
  const declarations = javascriptClosure(root, ['entry.mjs']).map(declaration);
  const snapshot = declarations[0].sha256;
  put('entry.mjs', '// Presentation and implementation locals are not interface ownership.\nexport function outcome(value) {const answer = value; return answer;}');
  const modules = javascriptClosure(root, ['entry.mjs']);
  assert.notEqual(modules[0].sha256, snapshot);
  assert.equal(assertInterfaceCoverage({root, modules, declarations}), 1);
  assert.equal(declarations[0].sha256, snapshot, 'the checker does not rewrite the review snapshot');
});

test('Moon source operation correspondence ignores only optional outer parameter commas', t => {
  const {root, declaration} = fixture(t);
  const source = 'pub fn consume(value : (Int, Bool), max_bytes : Int,) -> Int { 0 }';
  const module = text => ({module:'src/owner.mbt', sha256:createHash('sha256').update(text).digest('hex'),
    exports:[], operations:moonOperations(text)});
  const original = module(source), declarations = [declaration(original)];
  assert.equal(assertInterfaceCoverage({root, modules:[module(source.replace('Int,) ->', 'Int) ->'))], declarations}),1);
  // Normalize both sides, including a reviewed header without the comma.
  const reverse = [declaration(module(source.replace('Int,) ->','Int) ->')))];
  assert.equal(assertInterfaceCoverage({root, modules:[original], declarations:reverse}),1);
  for (const changed of [source.replace('max_bytes : Int','max_bytes : String'),
    source.replace('max_bytes : Int','different_role : Int'),
    source.replace('max_bytes : Int,','max_bytes : Int, extra : Int,'),
    source.replace('(Int, Bool)','(Int)'),source.replace(') -> Int',') -> Bool')]) {
    assert.throws(() => assertInterfaceCoverage({root, modules:[module(changed)], declarations}),
      /Unregistered interface operation/u);
  }
  const nested = 'pub fn consume(value : (Int,), max_bytes : Int,) -> Int { 0 }';
  assert.throws(() => assertInterfaceCoverage({root, modules:[module(nested.replace('(Int,)','(Int)'))],
    declarations:[declaration(module(nested))]}), /Unregistered interface operation/u);
  const api = text => ({module:'src/pkg.generated.mbti',sha256:createHash('sha256').update(text).digest('hex'),
    ...moonApiInterface(text)});
  const originalApi = api('pub fn consume(Int,) -> Int');
  assert.throws(() => assertInterfaceCoverage({root, modules:[api('pub fn consume(Int) -> Int')],
    declarations:[declaration(originalApi)]}), /Unregistered interface export/u);
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

test('executable interface evidence uses stable case IDs without freezing display names', t => {
  const {root, put, declaration} = fixture(t);
  put('entry.mjs', 'export function read() {}');
  const modules = javascriptClosure(root, ['entry.mjs']);
  const decl = declaration(modules[0]);
  const source = 'test "original presentation" {\n  // resource-case-id: retained_input_recovery\n  assert_true(true)\n}\n';
  const check = text => {
    put('recovery_wbtest.mbt', text);
    assertInterfaceCoverage({root, modules, declarations: [decl]});
  };
  decl.contracts[0].attributes.verification = [{path: 'recovery_wbtest.mbt', case_id: 'retained_input_recovery'}];
  check(source);
  check(source.replace('original presentation', 'new presentation'));
  check('  #| /* raw data, not a comment\n' + source);
  check(source + '\n/*\n' + source + '*/\n');
  for (const text of [
    source.replace('resource-case-id:', 'removed-case-id:'),
    '// resource-case-id: retained_input_recovery\n',
    '/*\n' + source + '*/\n',
    source + source.replace('original presentation', 'duplicate executable case'),
    source.replace('test "original presentation"', 'fn disabled_recovery()'),
  ]) assert.throws(() => check(text), /Missing interface reference/u);
  for (const ref of [
    {path: 'owner.md', case_id: 'retained_input_recovery'},
    {path: 'recovery_wbtest.mbt', case_id: 'invalid-id'},
    {path: 'recovery_wbtest.mbt', case_id: 'retained_input_recovery', anchor: 'test'},
  ]) {
    decl.contracts[0].attributes.verification = [ref];
    assert.throws(() => assertInterfaceCoverage({root, modules, declarations: [decl]}), /Invalid interface reference/u);
  }
});

test('JavaScript verification references bind a test entry while display labels and helper names can change', t => {
  const {root, put, declaration} = fixture(t);
  put('entry.mjs', 'export function read() {}');
  const modules = javascriptClosure(root, ['entry.mjs']);
  const decl = declaration(modules[0]);
  decl.contracts[0].attributes.verification = [{path:'recovery.test.mjs',anchor:'old display label'}];
  const source = "import test from 'node:test'; function helper() {} test('old display label', () => helper());";
  for (const text of [source, source.replace('old display label','new display label'),
    source.replaceAll('helper','renamedHelper'),
    "import {test as check} from 'node:test'; check('new label', () => {});",
    "import * as nodeTest from 'node:test'; nodeTest.test('new label', () => {});"]) {
    put('recovery.test.mjs', text);
    assertInterfaceCoverage({root, modules, declarations:[decl]});
  }
});

test('JavaScript verification references reject comments strings helpers shadowed bindings and literal skips', t => {
  const {root, put, declaration} = fixture(t);
  put('entry.mjs', 'export function read() {}');
  const modules = javascriptClosure(root, ['entry.mjs']);
  const decl = declaration(modules[0]);
  decl.contracts[0].attributes.verification = [{path:'recovery.test.mjs',anchor:'old display label'}];
  for (const text of [
    "// old display label\n// test('old display label', () => {});",
    "const source = \"old display label test('old display label', () => {})\";",
    "import test from 'node:test'; function helper() {test('old display label', () => {});}",
    "import test from 'node:test'; {const test = () => {};test('old display label', () => {});}",
    "import test from 'node:test'; for(const test of [()=>{}])test('old display label',()=>{});",
    "const test = () => {};test('old display label', () => {});",
    "import test from 'node:test'; test.skip('old display label', () => {});",
    "import test from 'node:test'; test('old display label', {skip:true}, () => {});",
    "import test from 'node:test'; test('old display label', {todo:true}, () => {});",
    "import test from 'node:test'; test('old display label');",
    "import test from 'node:test'; const label='old display label';test(label);",
  ]) {
    put('recovery.test.mjs', text);
    assert.throws(() => assertInterfaceCoverage({root, modules, declarations:[decl]}), /Missing interface reference/u);
  }
});

test('JavaScript verification entries preserve exact nonverification anchors and local file boundaries', t => {
  const {root, put, declaration} = fixture(t);
  put('entry.mjs', 'export function read() {}');
  const modules = javascriptClosure(root, ['entry.mjs']);
  const decl = declaration(modules[0]);
  const ref = {path:'recovery.test.mjs',anchor:'old display label'};
  put(ref.path,"import test from 'node:test'; test('new label', () => {});");
  decl.contracts[0].attributes.verification = [ref];
  assertInterfaceCoverage({root, modules, declarations:[decl]});
  decl.contracts[0].attributes.failure = [ref];
  assert.throws(() => assertInterfaceCoverage({root, modules, declarations:[decl]}), /Missing interface reference/u);
  decl.contracts[0].attributes.failure = {notApplicable:'No failure claim in this fixture'};
  for (const path of ['missing.test.mjs','../foreign.test.mjs','/foreign.test.mjs']) {
    decl.contracts[0].attributes.verification = [{...ref,path}];
    assert.throws(() => assertInterfaceCoverage({root, modules, declarations:[decl]}));
  }
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
  // A changed generated body is still a machine identity failure, even if
  // its exports/operations and the handwritten review snapshot are unchanged.
  put('shim.generated.mjs', '// Changed generated bytes\nexport function read(value) { return value["$tag"] === 1 ? value._0 : null; }');
  const changed = javascriptClosure(root, ['shim.generated.mjs']);
  assert.throws(() => assertInterfaceCoverage({root, modules:changed, declarations:[decl], generated:[proof]}),
    /Unverified generated binding/u);
  proof.sha256 = '0'.repeat(64);
  assert.throws(() => assertInterfaceCoverage({root, modules, declarations: [decl], generated: [proof]}),
    /Unverified generated binding/u);
});

test('syntax parser distinguishes actual field reads from comments and string data', () => {
  assert.deepEqual(javascriptInterface('export const text = "$tag _0"; // x._0').compilerFields, []);
  assert.deepEqual(javascriptInterface('const {$tag, _0: value} = input;').compilerFields, ['$tag', '_0']);
  assert.deepEqual(javascriptInterface("const {['$tag']: tag} = input;").compilerFields, ['$tag']);
});

test('closed literal and dynamic compiler field spellings do not bypass the representation gate', () => {
  for (const source of ["value['_0']", 'const {_0: value} = input;', 'const value = {_0: input};',
    'value[`$tag`]', "value['_' + 0]", "Object.getOwnPropertyDescriptor(value, '$tag')?.value",
    'value[`_${index}`]', "Reflect.get(value, '_' + index)"]) {
    assert(javascriptInterface(source).compilerFields.length, `Missing compiler field policy: ${source}`);
  }
  assert.deepEqual(javascriptInterface('const value = {"column": "_0", text: "$tag"};').compilerFields, []);
  assert.deepEqual(javascriptInterface("value['_' + 'column']; value[`_column`]").compilerFields, []);
});

test('namespace reexports and class methods retain their actual public names', () => {
  const before = javascriptInterface('export * as First from "./member.mjs"; export class Host { read() {} }');
  const after = javascriptInterface('export * as Second from "./member.mjs"; export class Host { write() {} }');
  assert.notDeepEqual(before.exports, after.exports);
  assert.notDeepEqual(before.operations, after.operations);
});

test('CommonJS actual and computed export targets preserve members or explicitly refuse unknown syntax', t => {
  assert.deepEqual(javascriptInterface("module['exports'] = Object.freeze({read(){}});").exports, ['commonjs:read']);
  assert.deepEqual(javascriptInterface('Object.assign(exports, {read(){}, write(){}});').exports,
    ['commonjs:read', 'commonjs:write']);
  const {root, put, declaration} = fixture(t);
  put('entry.cjs', 'module.exports = unreviewed();');
  const modules = javascriptClosure(root, ['entry.cjs']);
  assert.throws(() => assertInterfaceCoverage({root, modules, declarations: modules.map(declaration)}),
    /Unresolved interface syntax/u);
});

test('real stdlib wheel and source readers execute the original and normal correspondence controls', () => {
  const result = spawnSync('python3', ['-B', '-m', 'unittest', 'discover', '-s', 'scripts',
    '-p', 'test_python_interface_inventory.py', '-v'], {encoding: 'utf8', timeout: 30000});
  assert.equal(result.status, 0, result.stderr);
  const count = /Ran (\d+) tests/u.exec(result.stderr);
  assert(count && Number(count[1]) >= 13, result.stderr);
  assert.match(result.stderr, /^OK$/mu);
  process.stdout.write(result.stderr);
});
