import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync, mkdirSync, readFileSync, rmSync, unlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {test} from 'node:test';
import {interfaceAttributes, javascriptInterface} from './interface-inventory.mjs';
import {installedInterfaceCorrespondence, assertInstalledDependencyClosure, assertRemoteBrowserDependencyBoundary} from './installed-interface-correspondence.mjs';
import {checkInterfaceOwners} from './check-interface-owners.mjs';
import {typescriptInterface} from './typescript-interface-inventory.mjs';
import {installedInterfaceInventory} from './installed-interface-inventory.mjs';

function fixture(t, sourceText = 'export function read(original) {return original;}') {
  const scratch = mkdtempSync(join(tmpdir(), 'actql-if-correspondence-'));
  t.after(() => rmSync(scratch, {recursive: true}));
  const repository = join(scratch, 'repository'), directory = join(scratch, 'installed');
  mkdirSync(repository); mkdirSync(directory);
  const put = (root, path, bytes) => {
    mkdirSync(dirname(join(root, path)), {recursive: true});
    writeFileSync(join(root, path), bytes);
  };
  put(repository, 'outside/owner.mjs', sourceText);
  put(repository, 'owner.md', 'Original identity, lifetime, Unknown and cleanup boundary');
  put(directory, 'package.json', JSON.stringify({name: '@actql/fixture', exports: './entry.mjs'}));
  put(directory, 'entry.mjs', sourceText);
  const git = args => execFileSync('git', args, {cwd: repository, encoding: 'utf8'}).trim();
  git(['init', '--initial-branch=main']); git(['add', '.']);
  git(['-c', 'user.name=ActQL Test', '-c', 'user.email=test@example.invalid', '-c',
    'commit.gpgsign=false', 'commit', '-m', 'test: original interface input']);
  const source = git(['rev-parse', 'HEAD']);
  const module = {module: 'outside/owner.mjs', sha256: createHash('sha256').update(sourceText).digest('hex'),
    ...javascriptInterface(sourceText)};
  const declaration = {...module, responsibilityFacet: 'primary', role: 'physical-io', owner: 'original test boundary',
    contracts: [{operations: ['<module>', ...module.operations.map(value => value.name)], exports: module.exports,
      attributes: Object.fromEntries(interfaceAttributes.map(name => [name,
        [{path: 'owner.md', anchor: 'Original identity, lifetime, Unknown and cleanup boundary'}]]))}]};
  const options = {repository, directory, source,
    bindings: [{member: 'entry.mjs', source: 'outside/owner.mjs'}],
    owners: [{id: 'original', declarations: [declaration]}]};
  const commit = () => {
    git(['add', '.']);
    git(['-c', 'user.name=ActQL Test', '-c', 'user.email=test@example.invalid', '-c',
      'commit.gpgsign=false', 'commit', '-m', 'test: changed authored input']);
    options.source = git(['rev-parse', 'HEAD']);
  };
  return {options, put, declaration, commit};
}

test('actual installed bytes and all original private/public operations retain their Owner references', t => {
  const {options} = fixture(t);
  const result = installedInterfaceCorrespondence(options);
  assert.equal(result.coverage.covered, 1);
  assert.match(result.qualification, /not release or runtime admission/u);
});

test('normal package import rewriting uses the existing builder transformation', t => {
  const {options, put} = fixture(t,
    'import {Client} from "../../packages/sdk/index.mjs"; export const read = () => Client;');
  options.bindings[0].transform = 'local-node-public-imports';
  put(options.directory, 'entry.mjs', 'import {Client} from "@actql/sdk"; export const read = () => Client;');
  assert.equal(installedInterfaceCorrespondence(options).coverage.covered, 1);
});

test('changed installed bytes fail original-source comparison even when module names still match', t => {
  const {options, put} = fixture(t);
  put(options.directory, 'entry.mjs', 'export function read(original) {return true;}');
  assert.throws(() => installedInterfaceCorrespondence(options), /Changed installed interface bytes/u);
});

test('unregistered authored Python and dormant helpers cannot disappear from actual member discovery', t => {
  const {options, put} = fixture(t);
  put(options.directory, 'outside/decision.py', 'def decide_unknown(value):\n    return True\n');
  assert.throws(() => installedInterfaceCorrespondence(options), /Unbound installed authored interface: outside\/decision.py/u);
});

test('a new bound Python decision reaches the missing-Owner assertion instead of failing fixture setup', t => {
  const {options, put, commit} = fixture(t);
  const text = 'def decide_unknown(value):\n    return True\n';
  put(options.repository, 'outside/decision.py', text);
  put(options.directory, 'outside/decision.py', text);
  commit();
  options.bindings.push({member: 'outside/decision.py', source: 'outside/decision.py'});
  assert.throws(() => installedInterfaceCorrespondence(options), /Unregistered distributed interfaces: outside\/decision.py/u);
});

test('extensionless original Node commands retain operations and export coverage', t => {
  const text = '#!/usr/bin/env node\nexport function read(original) {return original;}';
  const {options, put, commit, declaration} = fixture(t, text);
  put(options.repository, 'outside/command', text); commit();
  options.bindings[0].source = 'outside/command'; declaration.module = 'outside/command';
  assert.equal(installedInterfaceCorrespondence(options).coverage.covered, 1);
});

test('normal source bytes do not grant a missing Owner registration', t => {
  const {options} = fixture(t);
  options.owners = [];
  assert.throws(() => installedInterfaceCorrespondence(options), /Unregistered distributed interfaces/u);
});

test('an Owner reference cannot conceal a missing operation or omitted attribute', t => {
  const {options, declaration} = fixture(t);
  declaration.contracts[0].operations.pop();
  assert.throws(() => installedInterfaceCorrespondence(options), /Missing operation contract/u);
  declaration.contracts[0].operations.push('read');
  delete declaration.contracts[0].attributes.failure;
  assert.throws(() => installedInterfaceCorrespondence(options), /Incomplete interface attributes/u);
});

test('foreign compiled Source is refused before parsing or self-reported verification', t => {
  const {options} = fixture(t);
  options.artifacts = [{module: 'runtime.js', sourceSha: '0'.repeat(40), verification: true}];
  assert.throws(() => installedInterfaceCorrespondence(options), /Foreign installed interface artifact source/u);
});

async function checkedFixture(t) {
  const f = fixture(t);
  f.put(f.options.repository, 'package.json', JSON.stringify({name: '@example/original', exports: './outside/owner.mjs'}));
  f.put(f.options.repository, 'interface-boundaries.json', JSON.stringify([f.declaration]));
  f.commit();
  f.options.checkedSource = await checkInterfaceOwners(f.options.repository);
  return f;
}

test('same original checked source retains its Git byte read without rebuilding the source projection', async t => {
  const {options} = await checkedFixture(t);
  const trace = join(dirname(options.repository), 'git-trace.json');
  const previous = process.env.GIT_TRACE2_EVENT;
  let result;
  try {
    process.env.GIT_TRACE2_EVENT = trace;
    result = installedInterfaceCorrespondence(options);
  } finally {
    if (previous === undefined) delete process.env.GIT_TRACE2_EVENT;
    else process.env.GIT_TRACE2_EVENT = previous;
  }
  assert.equal(result.coverage.covered, 1);
  const commands = readFileSync(trace, 'utf8').trim().split('\n').map(line => JSON.parse(line))
    .filter(event => event.event === 'start').map(event => event.argv);
  assert.deepEqual({
    sourceProjections: commands.filter(args => args.includes('ls-tree')).length,
    originalByteReads: commands.filter(args => args.includes('show') &&
      args.includes(`${options.source}:${options.bindings[0].source}`)).length,
  }, {sourceProjections: 0, originalByteReads: 1});
});

test('installed TypeScript bytes must derive from the tracked original, even with a fresh check of stale emit', async t => {
  const {options, put, commit} = await checkedFixture(t);
  const {repository, directory} = options;
  const runtime = 'outside/owner.mjs';
  put(repository, '.gitignore', `/${runtime}\n`);
  unlinkSync(join(repository, runtime));
  put(repository, 'outside/owner.mts', 'export function read(original: string) { return original; }\n');
  const fromRoot = name => readFileSync(new URL(`../${name}`, import.meta.url));
  for (const file of ['tsconfig.base.json', 'package-lock.json']) put(repository, file, fromRoot(file));
  const config = JSON.stringify({extends: './tsconfig.base.json',
    compilerOptions: {declaration: true}, include: ['outside/**/*.mts']});
  put(repository, 'tsconfig.tooling.json', config);
  commit();
  const exact = 'export function read(original) { return original; }\n';
  put(repository, runtime, exact);
  put(directory, 'entry.mjs', exact);
  options.checkedSource = await checkInterfaceOwners(repository);
  assert.equal(installedInterfaceCorrespondence(options).coverage.covered, 1);
  put(repository, 'tsconfig.tooling.json', config + '\n');
  assert.throws(() => installedInterfaceCorrespondence(options), /Changed TypeScript preparation input: tsconfig.tooling.json/u);
  put(repository, 'tsconfig.tooling.json', config);
  const stale = 'export function read(original) { return original.trim(); }\n';
  put(repository, runtime, stale);
  put(directory, 'entry.mjs', stale);
  options.checkedSource = await checkInterfaceOwners(repository);
  assert.throws(() => installedInterfaceCorrespondence(options), /Changed checked original source interface/u);
});

test('installed CommonJS emit retains its tracked .cts origin and rejects a fresh check of stale bytes', async t => {
  const exact = '"use strict";\nfunction read(original) { return original; }\nmodule.exports = Object.freeze({ read });\n';
  const {options, put, commit, declaration} = fixture(t, exact);
  const {repository, directory} = options, runtime = 'outside/owner.cjs';
  unlinkSync(join(repository, 'outside/owner.mjs'));
  unlinkSync(join(directory, 'entry.mjs'));
  put(repository, '.gitignore', `/${runtime}\n`);
  put(repository, 'outside/owner.cts',
    'function read(original: string) { return original; }\nexport = Object.freeze({ read });\n');
  const fromRoot = name => readFileSync(new URL(`../${name}`, import.meta.url));
  for (const file of ['tsconfig.base.json', 'package-lock.json']) put(repository, file, fromRoot(file));
  put(repository, 'tsconfig.tooling.json', JSON.stringify({extends: './tsconfig.base.json',
    compilerOptions: {declaration: true, moduleDetection: 'legacy'}, include: ['outside/**/*.cts']}));
  put(repository, 'package.json', JSON.stringify({name: '@example/original', exports: './outside/owner.cjs'}));
  put(directory, 'package.json', JSON.stringify({name: '@actql/fixture', exports: './entry.cjs'}));
  declaration.module = runtime;
  put(repository, 'interface-boundaries.json', JSON.stringify([declaration]));
  options.bindings[0] = {member: 'entry.cjs', source: runtime};
  commit();
  put(repository, runtime, exact);
  put(directory, 'entry.cjs', exact);
  options.checkedSource = await checkInterfaceOwners(repository);
  assert.equal(installedInterfaceCorrespondence(options).coverage.covered, 1);
  const stale = exact.replace('return original;', 'return original.trim();');
  put(repository, runtime, stale);
  put(directory, 'entry.cjs', stale);
  options.checkedSource = await checkInterfaceOwners(repository);
  assert.throws(() => installedInterfaceCorrespondence(options), /Changed checked original source interface/u);
});

test('original checked correspondence refuses copied foreign and changed originals', async t => {
  const {options, put, commit} = await checkedFixture(t);
  const foreign = await checkedFixture(t);
  for (const checkedSource of [structuredClone(options.checkedSource), foreign.options.checkedSource]) {
    assert.throws(() => installedInterfaceCorrespondence({...options, checkedSource}), /Untrusted checked interface source/u);
  }
  const changed = 'export function read(original) {return !original;}';
  put(options.repository, 'outside/owner.mjs', changed);
  put(options.directory, 'entry.mjs', changed);
  commit();
  assert.throws(() => installedInterfaceCorrespondence(options), /Changed checked (?:original )?source interface/u);
});

test('original checked correspondence still reads staged bytes and current Owner references', async t => {
  const {options, put} = await checkedFixture(t);
  const original = readFileSync(join(options.directory, 'entry.mjs'), 'utf8');
  // Returned report DATA cannot replace the checker's private original model.
  options.checkedSource.modules[0].sha256 = 'f'.repeat(64);
  assert.equal(installedInterfaceCorrespondence(options).coverage.covered, 1);
  put(options.directory, 'entry.mjs', 'export function read(original) {return !original;}');
  assert.throws(() => installedInterfaceCorrespondence(options), /Changed installed interface bytes/u);
  put(options.directory, 'entry.mjs', original);
  put(options.repository, 'owner.md', 'Missing original semantic reference');
  assert.throws(() => installedInterfaceCorrespondence(options), /Missing interface reference/u);
});

test('a bound module outside the original checked closure cannot acquire a checked model', async t => {
  const {options, put, commit} = await checkedFixture(t);
  const source = 'export const later = 1;';
  put(options.repository, 'outside/later.mjs', source);
  put(options.directory, 'later.mjs', source);
  options.bindings.push({member: 'later.mjs', source: 'outside/later.mjs'});
  commit();
  assert.throws(() => installedInterfaceCorrespondence(options), /Missing checked original interface: outside\/later.mjs/u);
});


test('installed lazy imports retain original checked target discovery rather than suppressing unresolved syntax', async t => {
  const source = "const target = new URL('./runtime-owner.mjs', import.meta.url); export const load = () => import(target.href);";
  const {options, put, commit, declaration} = fixture(t, source);
  const dependencySource = 'export const value = 1;';
  const dependency = {module: 'outside/runtime-owner.mjs', sha256: createHash('sha256').update(dependencySource).digest('hex'),
    ...javascriptInterface(dependencySource)};
  const dependentDeclaration = {...declaration, ...dependency, contracts: [{...declaration.contracts[0],
    operations: ['<module>'], exports: ['value']}]};
  put(options.repository, 'package.json', JSON.stringify({name: '@example/original', exports: './outside/owner.mjs'}));
  put(options.repository, dependency.module, dependencySource);
  put(options.repository, 'interface-boundaries.json', JSON.stringify([declaration, dependentDeclaration]));
  put(options.directory, 'runtime-owner.mjs', dependencySource);
  options.owners[0].declarations.push(dependentDeclaration);
  options.bindings.push({member: 'runtime-owner.mjs', source: dependency.module});
  commit();
  assert.throws(() => installedInterfaceCorrespondence(options), /Unresolved interface syntax/u);
  const checkedSource = await checkInterfaceOwners(options.repository);
  assert.equal(installedInterfaceCorrespondence({...options, checkedSource}).coverage.covered, 2);
  assert.throws(() => installedInterfaceCorrespondence({...options, checkedSource: structuredClone(checkedSource)}),
    /Untrusted checked interface source/u);
});


test('actual installed resolver accepts neutral extraction and refuses a missing dependency at its policy assertion', async t => {
  const {options, put} = fixture(t);
  put(options.directory, 'entry.mjs', "export {value} from './neutral.mjs';");
  put(options.directory, 'neutral.mjs', 'export const value = 1;');
  const input = {directory: options.directory, modules: [{module: 'entry.mjs'}]};
  assert.equal((await assertInstalledDependencyClosure(input)).modules, 2);
  unlinkSync(join(options.directory, 'neutral.mjs'));
  await assert.rejects(assertInstalledDependencyClosure(input), /Unresolved installed interface dependency/u);
});

test('actual installed resolver rejects foreign source and test authority before claiming member coverage', async t => {
  const {options, put} = fixture(t);
  const input = {directory: options.directory, modules: [{module: 'entry.mjs'}]};
  put(options.directory, 'control.mjs', 'export const value = 1;');
  put(options.directory, 'entry.mjs', "export {value} from './control.mjs';");
  assert.equal((await assertInstalledDependencyClosure(input)).modules, 2);
  put(options.directory, 'control.test.mjs', 'export const value = 1;');
  put(options.directory, 'entry.mjs', "export {value} from './control.test.mjs';");
  await assert.rejects(assertInstalledDependencyClosure(input), /Test authority in installed interface dependency/u);
  put(dirname(options.directory), 'foreign.mjs', 'export const value = 1;');
  put(options.directory, 'entry.mjs', "export {value} from '../foreign.mjs';");
  await assert.rejects(assertInstalledDependencyClosure(input), /Escaped installed interface dependency/u);
});

test('resolved runtime targets remain actual installed obligations and exact compiled members are not parsed as authored helpers', async t => {
  const {options, put} = fixture(t);
  put(options.directory, 'runtime.js', 'compiler output placeholder: not JavaScript');
  put(options.directory, 'entry.mjs', "export const load = () => import('./runtime.js');");
  const input = {directory: options.directory, modules: [{module: 'entry.mjs'}],
    artifacts: [{module: 'runtime.js'}], runtimeBindings: [{module: 'entry.mjs', targets: ['./runtime.js']}]};
  assert.equal((await assertInstalledDependencyClosure(input)).modules, 1);
  unlinkSync(join(options.directory, 'runtime.js'));
  await assert.rejects(assertInstalledDependencyClosure(input), /Missing installed runtime dependency/u);
});

test('declaration-only TS members retain source/Owner coverage without becoming runtime entries', async t => {
  for (const extension of ['d.ts', 'd.mts', 'd.cts']) {
    const {options, put, commit, declaration} = fixture(t);
    const module = `outside/contract.${extension}`, member = `contract.${extension}`;
    const text = 'export type Format = "sql" | "json"; export const formats: readonly Format[];';
    put(options.repository, module, text);
    put(options.directory, member, text);
    put(options.directory, 'package.json', JSON.stringify({name: '@actql/fixture',
      exports: {'.': {types: `./${member}`, default: './entry.mjs'}}}));
    commit();
    const syntax = typescriptInterface(text, module);
    const owner = {...declaration, module, sha256: createHash('sha256').update(text).digest('hex'), ...syntax,
      contracts: [{...declaration.contracts[0], operations: ['<module>'], exports: ['Format', 'formats']}]};
    options.bindings.push({member, source: module});
    options.owners[0].declarations.push(owner);
    const installed = installedInterfaceInventory(options.directory);
    assert.deepEqual(installed.modules.find(value => value.module === member).exports, ['Format', 'formats']);
    assert.equal(installedInterfaceCorrespondence(options).coverage.primaryCovered, 2);
    assert.equal((await assertInstalledDependencyClosure({directory: options.directory, modules: installed.modules})).modules, 1);
    options.owners[0].declarations.pop();
    assert.throws(() => installedInterfaceCorrespondence(options), /Unregistered distributed interfaces/u);
    options.owners[0].declarations.push(owner);
    put(options.directory, member, text.replace('"json"', '"aql"'));
    assert.throws(() => installedInterfaceCorrespondence(options), /Changed installed interface bytes/u);
  }
});

test('shipped client-wire declaration remains inventoried without an initialized runtime const', async t => {
  const {options, put} = fixture(t);
  const text = readFileSync(new URL('../packages/client-wire/index.d.ts', import.meta.url), 'utf8');
  put(options.directory, 'index.d.ts', text);
  put(options.directory, 'package.json', JSON.stringify({name: '@actql/fixture',
    exports: {'.': {types: './index.d.ts', default: './entry.mjs'}}}));
  const installed = installedInterfaceInventory(options.directory);
  assert(installed.modules.find(value => value.module === 'index.d.ts').exports.includes('clientSourceFormats'));
  assert.equal((await assertInstalledDependencyClosure({directory: options.directory, modules: installed.modules})).modules, 1);
});

test('excluding declarations does not conceal dormant runtime helpers or runtime TypeScript dependencies', async t => {
  const {options, put} = fixture(t);
  put(options.directory, 'contract.d.ts', 'export const value: number;');
  put(options.directory, 'helper.ts', "export const value: number = 7; export {read} from './entry.mjs';");
  let modules = installedInterfaceInventory(options.directory).modules;
  assert.equal((await assertInstalledDependencyClosure({directory: options.directory, modules})).modules, 2);
  put(options.directory, 'helper.ts', "export {value} from './missing.mjs';");
  modules = installedInterfaceInventory(options.directory).modules;
  await assert.rejects(assertInstalledDependencyClosure({directory: options.directory, modules}), /Unresolved installed interface dependency/u);
});

test('a runtime import of a declaration still reaches the real runtime resolver', async t => {
  const {options, put} = fixture(t);
  put(options.directory, 'contract.d.ts', 'export const value: number;');
  put(options.directory, 'entry.mjs', "export {value} from './contract.d.ts';");
  await assert.rejects(assertInstalledDependencyClosure({directory: options.directory,
    modules: installedInterfaceInventory(options.directory).modules}), failure =>
    failure.errors?.some(value => /must be initialized/u.test(value.text)));
  put(options.directory, 'entry.mjs', 'export const load = target => import(target);');
  await assert.rejects(assertInstalledDependencyClosure({directory: options.directory,
    modules: installedInterfaceInventory(options.directory).modules,
    runtimeBindings: [{module: 'entry.mjs', targets: ['./contract.d.ts']}]}), failure =>
    failure.errors?.some(value => /must be initialized/u.test(value.text)));
});

function browserGraph(extra = {}) {
  return {inputs: {
    'node_modules/@actql/sdk/index.mjs': {imports: []},
    'node_modules/@actql/client-wire/index.mjs': {imports: []},
    ...extra,
  }, outputs: {'browser.mjs': {imports: []}}};
}

test('remote browser boundary allows additional pure generated SDK modules', () => {
  assert.doesNotThrow(() => assertRemoteBrowserDependencyBoundary(browserGraph({
    'node_modules/@actql/sdk/internal/checkpoint-answer-construction.generated.mjs': {imports: []},
  })));
});

test('remote browser boundary refuses Local Node Core native and escaped runtime dependencies', () => {
  for (const path of [
    'node_modules/@actql/local-node/index.mjs', 'node_modules/@actql/node/index.mjs',
    'node_modules/@actql/run-host-core/index.mjs', '_build/js/release/build/Core.js',
    'node_modules/@actql/sdk/internal/Core.js',
    'node_modules/@actql/sdk/../local-node/index.mjs',
    'node_modules/@actql/sdk/node_modules/@actql/local-node/index.mjs',
    'node_modules/@actql/sdk/_build/runtime.js', 'node_modules/@actql/sdk/native/runtime.mjs',
    'node_modules/@actql/sdk/internal/engine.wasm', 'node_modules/@actql/sdk/internal/addon.node',
  ]) assert.throws(() => assertRemoteBrowserDependencyBoundary(browserGraph({[path]: {imports: []}})),
    /Remote browser/u, path);
});

test('remote browser boundary refuses external imports and empty or missing entry graphs', () => {
  const external = browserGraph();
  external.inputs['node_modules/@actql/sdk/index.mjs'].imports.push({path: 'node:fs', external: true});
  assert.throws(() => assertRemoteBrowserDependencyBoundary(external), /external input import/u);
  const outputImport = browserGraph();
  outputImport.outputs['browser.mjs'].imports.push({path: 'runtime.mjs', external: true});
  assert.throws(() => assertRemoteBrowserDependencyBoundary(outputImport), /remaining imports/u);
  assert.throws(() => assertRemoteBrowserDependencyBoundary({inputs: {}, outputs: {}}), /nonempty/u);
  const missingEntry = browserGraph(); delete missingEntry.inputs['node_modules/@actql/sdk/index.mjs'];
  assert.throws(() => assertRemoteBrowserDependencyBoundary(missingEntry), /entry is missing/u);
});
