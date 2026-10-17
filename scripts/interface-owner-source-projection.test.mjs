import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {interfaceAttributes} from './interface-inventory.mjs';
import {interfaceOwnerCoverage} from './interface-owner-coverage.mjs';
import {projectOwnerSources, projectOwnerSourceUpdates} from './interface-owner-source-projection.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-owner-update-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const git = args => execFileSync('git', args, {cwd: root, encoding: 'utf8'}).trim();
  git(['init', '--quiet']);
  git(['config', 'user.email', 'fixture@example.invalid']);
  git(['config', 'user.name', 'Independent fixture']);
  const write = (path, text) => {
    mkdirSync(join(root, path, '..'), {recursive: true});
    writeFileSync(join(root, path), text);
  };
  const commit = () => {
    git(['add', '.']);
    git(['commit', '--quiet', '-m', 'test: retain independent source fixture']);
    return git(['rev-parse', 'HEAD']);
  };
  write('owner.md', 'Original read boundary and original runtime representation');
  write('outside/connector.mjs', 'export function read(value) {return value;}');
  const base = commit();
  const options = source => ({source, base, paths: ['outside']});
  const original = projectOwnerSources(root, {...options(base), all: true}).modules[0];
  const declaration = {...original, role: 'physical-io', owner: 'Existing physical Owner',
    responsibilityFacet: 'primary', contracts: [{operations: ['<module>', 'read'], exports: ['read'],
      attributes: Object.fromEntries(interfaceAttributes.map(name =>
        [name, [{path: 'owner.md', anchor: 'Original read boundary'}]]))}]};
  const check = (source, declarations, extra = {}) => interfaceOwnerCoverage({root,
    modules: projectOwnerSources(root, {...options(source), all: true}).modules,
    owners: [{id: 'original', declarations}], ...extra});
  return {root, git, write, commit, base, options, declaration, check};
}

test('body-only candidate reuses Git/AST syntax and preserves every existing semantic field for explicit review', t => {
  const f = fixture(t), original = structuredClone(f.declaration);
  f.write('outside/connector.mjs', 'export function read(value) {return value ?? null;}');
  const source = f.commit();
  // Dirty checkout bytes do not replace the selected immutable Git original.
  f.write('outside/connector.mjs', 'throw new Error("must not execute product");');
  const report = projectOwnerSourceUpdates(f.root, f.options(source), [f.declaration]);
  assert.equal(report.updates.length, 1);
  const update = report.updates[0];
  assert.equal(update.status, 'changed');
  assert.deepEqual(update.mechanicalFields, ['sha256']);
  assert.deepEqual(update.candidate.contracts, original.contracts);
  for (const key of ['role', 'owner', 'responsibilityFacet']) assert.equal(update.candidate[key], original[key]);
  assert.equal(update.reviewRequired.length, 4, 'body changes still require all ten references and behavior review');
  assert.deepEqual(f.declaration, original, 'candidate generation never mutates a declaration');
  assert.throws(() => f.check(source, [original]), /Unreviewed interface implementation/u);
  assert.equal(f.check(source, [update.candidate]).primaryComplete, true,
    'syntax/reference gate is separate from semantic review, not an automatic review receipt');
});

test('safe extraction and a new export report exact membership gaps instead of assigning semantic groups', t => {
  const f = fixture(t);
  f.write('outside/connector.mjs', 'function helper(value) {return value;} export function read(value) {return helper(value);} export const extra = 1;');
  const source = f.commit();
  const {updates: [update]} = projectOwnerSourceUpdates(f.root, f.options(source), [f.declaration]);
  assert.deepEqual(update.difference.operations.added, ['helper']);
  assert.deepEqual(update.difference.exports.added, ['extra']);
  assert.deepEqual(update.candidate.contracts, f.declaration.contracts);
  assert.throws(() => f.check(source, [update.candidate]), /Missing operation contract/u);
  const reviewed = structuredClone(update.candidate);
  reviewed.contracts[0].operations.push('helper');
  reviewed.contracts[0].exports.push('extra');
  assert.equal(f.check(source, [reviewed]).primaryComplete, true);
});

test('new outside-directory modules get syntax candidates without inferred Owner role or ten references', t => {
  const f = fixture(t);
  f.write('outside/new-host.mjs', 'export const prepare = value => value;');
  const source = f.commit();
  const {updates: [update]} = projectOwnerSourceUpdates(f.root, f.options(source), [f.declaration]);
  assert.equal(update.status, 'unregistered');
  for (const key of ['role', 'owner', 'responsibilityFacet', 'contracts']) assert.equal(key in update.candidate, false);
  assert.throws(() => f.check(source, [f.declaration]), /Unregistered distributed interfaces/u);
  assert.throws(() => f.check(source, [f.declaration, update.candidate]), /Unclassified interface responsibility facet/u);
});

test('removed-only and empty diffs are diagnostic candidates, never weakened ordinary projection or admission', t => {
  const f = fixture(t);
  assert.throws(() => projectOwnerSources(f.root, f.options(f.base)), /No owner product sources/u);
  assert.deepEqual(projectOwnerSourceUpdates(f.root, f.options(f.base), [f.declaration]).updates, []);
  rmSync(join(f.root, 'outside/connector.mjs'));
  f.write('outside/control.test.mjs', 'export const authority = true;');
  const source = f.commit();
  const {updates} = projectOwnerSourceUpdates(f.root, f.options(source), [f.declaration]);
  assert.equal(updates.length, 1);
  assert.equal(updates[0].module, 'outside/connector.mjs');
  assert.equal(updates[0].status, 'removed');
  assert.equal(updates[0].candidate, null);
  assert.deepEqual(updates[0].difference.operations.removed, ['read']);
  assert.deepEqual(updates[0].difference.exports.removed, ['read']);
});

test('candidate syntax cannot self-approve raw compiler access, missing primary, or forged generation', t => {
  const f = fixture(t);
  f.write('outside/connector.mjs', 'export function read(value) {return value["_0"];}');
  const source = f.commit();
  const {updates: [update]} = projectOwnerSourceUpdates(f.root, f.options(source), [f.declaration]);
  assert.deepEqual(update.candidate.compilerFields, ['_0']);
  assert.throws(() => f.check(source, [update.candidate]), /Compiler representation outside generated binding/u);
  const forged = {...update.candidate, role: 'generated-binding'};
  assert.throws(() => f.check(source, [forged]), /Unverified generated binding/u);
  assert.throws(() => f.check(source, [forged], {generated: [{module: forged.module,
    sha256: forged.sha256, generator: {path: 'owner.md', anchor: 'Original read boundary'},
    freshness: {path: 'owner.md', anchor: 'Original read boundary'}}]}), /Untrusted generated interface qualification/u);
  const supplemental = {...f.declaration, responsibilityFacet: 'supplemental'};
  assert.throws(() => f.check(f.base, [supplemental]), /Missing primary interface responsibilities/u);
});

test('operation parameter changes and removals remain visible and duplicate facets are not concatenated', t => {
  const f = fixture(t);
  f.write('outside/connector.mjs', 'export function read(original, current) {return current ?? original;}');
  const source = f.commit();
  const {updates: [update]} = projectOwnerSourceUpdates(f.root, f.options(source), [f.declaration]);
  assert.deepEqual(update.difference.operations.changed, ['read']);
  assert.deepEqual(update.candidate.operations[0].parameters, ['original', 'current']);
  assert.throws(() => projectOwnerSourceUpdates(f.root, f.options(source), [f.declaration, f.declaration]),
    /Duplicate owner update declaration/u);
});

test('copied references are not auto-approved or replaced when their original anchor disappears', t => {
  const f = fixture(t);
  f.write('outside/connector.mjs', 'export function read(value) {return value ?? null;}');
  f.write('owner.md', 'A different boundary cannot approve the original contract');
  const source = f.commit();
  const {updates: [update]} = projectOwnerSourceUpdates(f.root, f.options(source), [f.declaration]);
  assert.deepEqual(update.candidate.contracts, f.declaration.contracts);
  assert.throws(() => f.check(source, [update.candidate]), /Missing interface reference:/u);
});
