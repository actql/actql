import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {test} from 'node:test';
import {interfaceAttributes, javascriptInterface} from './interface-inventory.mjs';
import {installedInterfaceCorrespondence} from './installed-interface-correspondence.mjs';
import {checkInterfaceOwners} from './check-interface-owners.mjs';

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

test('an Owner reference cannot conceal a changed operation, stale hash or omitted attribute', t => {
  const {options, declaration} = fixture(t);
  declaration.contracts[0].operations.pop();
  assert.throws(() => installedInterfaceCorrespondence(options), /Missing operation contract/u);
  declaration.contracts[0].operations.push('read'); declaration.sha256 = '0'.repeat(64);
  assert.throws(() => installedInterfaceCorrespondence(options), /Unreviewed interface implementation/u);
  declaration.sha256 = createHash('sha256').update(readFileSync(join(options.directory, 'entry.mjs'))).digest('hex');
  delete declaration.contracts[0].attributes.failure;
  assert.throws(() => installedInterfaceCorrespondence(options), /Incomplete interface attributes/u);
});

test('foreign compiled Source is refused before parsing or self-reported verification', t => {
  const {options} = fixture(t);
  options.artifacts = [{module: 'runtime.js', sourceSha: '0'.repeat(40), verification: true}];
  assert.throws(() => installedInterfaceCorrespondence(options), /Foreign installed interface artifact source/u);
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
