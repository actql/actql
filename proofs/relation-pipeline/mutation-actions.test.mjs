import assert from 'node:assert/strict';
import {chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {tmpdir} from 'node:os';
import {gunzipSync} from 'node:zlib';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {parse} from 'yaml';
import test from 'node:test';
import {gitTree, hash} from '../ci-evidence/inputs.mjs';
import {snapshot as actualSnapshot} from './inventory.mjs';
import {checkPlan} from '../ci-evidence/check.mjs';
import {mutationNamesByPart} from './proof-parts.mjs';
import {variants} from './mutation-registry.mjs';
import {fixturePath} from './fixture.mjs';
import {cohort, inputTree, snapshot} from './fixtures/mutation-action-sample.mjs';
import {mutationActions, mutationSourceInputs, mutationActionObservation, mutationActionRecords, archivedMutationActionObservations} from './mutation-actions.mjs';

const digest = value => hash(JSON.stringify(value));
const root = fileURLToPath(new URL('../../', import.meta.url));

test('the source adapter binds the actual committed wide pipeline inventory', () => {
  const result = spawnSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'});
  assert.equal(result.status, 0);
  const source = actualSnapshot(root);
  const inputs = mutationSourceInputs({tree: gitTree(root, result.stdout.trim()), source, root});
  assert(inputs.files.length >= Object.keys(source.sources).length);
  assert(inputs.files.some(entry => entry.path === 'proofs/ci-evidence/Reuse.lean'));
  assert(inputs.unresolved.length > 0);
});

test('the consumer refuses working checker bytes and input modes that differ from its Git identity', t => {
  const directory = mkdtempSync(join(tmpdir(), 'actql-pipeline-action-inputs-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const tree = inputTree(), source = snapshot(tree);
  for (const [path, bytes] of tree.contents) {
    const actual = join(directory, path); mkdirSync(dirname(actual), {recursive: true});
    writeFileSync(actual, bytes); chmodSync(actual, 0o644);
  }
  assert(mutationSourceInputs({tree, source, root: directory}).key);
  const checker = join(directory, 'proofs/ci-evidence/check.mjs');
  writeFileSync(checker, 'different executed checker');
  assert.throws(() => mutationSourceInputs({tree, source, root: directory}), /Working pipeline input bytes differ/);
  writeFileSync(checker, tree.read('proofs/ci-evidence/check.mjs'));
  chmodSync(checker, 0o755);
  assert.throws(() => mutationSourceInputs({tree, source, root: directory}), /Working pipeline input mode differs/);
});

test('the existing final consumer installs the audited Lean pin before executing action admission', () => {
  const workflow = parse(readFileSync(new URL('../../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const steps = workflow.jobs['pipeline-evidence'].steps;
  const install = steps.findIndex(step => step.run?.includes('node proofs/bounded-session/setup-lean.mjs'));
  const audit = steps.findIndex(step => step.run === 'node proofs/relation-pipeline/mutation-action-archive.mjs seal');
  assert(install >= 0 && audit > install, 'Final action checker lacks its prepared Lean runtime');
  const pin = readFileSync(new URL('../bounded-session/lean-toolchain', import.meta.url), 'utf8').trim().split(':v')[1];
  assert(steps[install].run.includes(`.toolchains/lean-${pin}-linux/bin`));
  assert(steps[install].run.includes('"$GITHUB_PATH"'));
});
// Controlled registration/receipt fixtures only. They do not claim MoonBit
// execution, original Actions provenance or a successful full scientific audit.
function reseal(entry) {entry.bytesDigest = hash(`${JSON.stringify(entry.report, null, 2)}\n`);}

test('required obligations independently retain all parts, targets, modes and three phases', () => {
  assert.equal(mutationActions({required: true}).length, 72);
  assert.equal(mutationActions({required: false}).length, 36);
  const c = cohort(), bytes = c.reports.map(entry => JSON.stringify(entry.report));
  const records = mutationActionRecords(c);
  assert.equal(records.actions.length, 72);
  assert.equal(new Set(records.actions.map(entry => entry.action.id)).size, 72);
  assert(records.actions.every(entry => entry.required.minimumUnits === 2 && !entry.application.reused &&
    !entry.application.closed && !entry.application.mainOrigin));
  assert.equal(records.reuseAuthorized, false);
  assert(records.unresolved.length > 0);
  assert.equal(new Set(records.actions.flatMap(entry => entry.receipts.map(ref => ref.path))).size, 160);
  assert.deepEqual(c.reports.map(entry => JSON.stringify(entry.report)), bytes);
  const search = records.actions.filter(entry => entry.action.mode === 'explore' && entry.action.phase === 'mutated' && entry.action.target === 'js');
  assert(search.every(entry => entry.application.units === 6));
});

test('a reviewed non-exploration condition still requires all hosted parts and every target/phase', () => {
  assert.equal(mutationActionRecords(cohort(false)).actions.length, 36);
  assert.throws(() => mutationActions({}), /independent exploration/);
});

for (const [label, change] of Object.entries({
  missingPart: c => c.reports.splice(2), missingExplore: c => c.reports.splice(1, 1),
  duplicatePart: c => {c.reports[2] = c.reports[0];},
  missingReceiptAudit: c => c.auditedReceipts.delete(c.reports[0].report.results[0].executions[0].path),
  wrongReceiptAudit: c => {c.auditedReceipts.get(c.reports[0].report.results[0].executions[0].path).receiptDigest = 'f'.repeat(64);},
  wrongOriginalBytes: c => {c.reports[0].bytesDigest = 'f'.repeat(64);},
  changedSourceKey: c => {c.sourceInputs.key = 'f'.repeat(64);},
  erasedRuntimeBoundary: c => {c.sourceInputs.unresolved = [];},
  missingRestoration: c => {c.reports[0].report.results[0].postRestore.executions.pop(); reseal(c.reports[0]);},
  oldRestorationOwner: c => {c.reports[0].report.restorationOwner.id = c.reports[0].report.workspaces.mutable.id; reseal(c.reports[0]);},
  missingSearch: c => {c.reports[1].report.results[0].executions.shift(); reseal(c.reports[1]);},
  wrongTarget: c => {c.reports[0].report.results[0].executions[1].receipt.target = 'js'; reseal(c.reports[0]);},
})) test(`fresh action admission refuses ${label}`, () => {
  const c = cohort(); change(c); assert.throws(() => mutationActionRecords(c));
});

test('a failed compile/execution cannot be admitted even with a carried audit digest', () => {
  const c = cohort(), original = c.reports[0], e = original.report.results[0].executions[0];
  e.receipt.exit = 1; e.digest = digest(e.receipt); reseal(original);
  c.auditedReceipts.set(e.path, {receiptDigest: e.digest, bytesDigest: hash(JSON.stringify(e.receipt))});
  assert.throws(() => mutationActionRecords(c), /Failed execution/);
});

test('Git bytes, mode and membership remain input dependencies outside the compiled site', () => {
  const tree = inputTree(), source = snapshot(tree), before = mutationSourceInputs({tree, source});
  tree.entries.get('src/query_integration/moon.pkg').mode = '100755';
  assert.notEqual(mutationSourceInputs({tree, source}).key, before.key);
  tree.contents.set('proofs/ci-evidence/Reuse.lean', Buffer.from('changed checker'));
  assert.notEqual(mutationSourceInputs({tree, source}).key, before.key);
  tree.contents.set(variants[0].path, Buffer.from('changed source'));
  assert.throws(() => mutationSourceInputs({tree, source}), /source bytes differ/);
  for (const alteration of ['add', 'delete', 'rename', 'symlink']) {
    const next = inputTree(), original = snapshot(next);
    if (alteration === 'add') {next.entries.set('src/new-file.mbt', {kind: 'blob', mode: '100644'}); next.contents.set('src/new-file.mbt', Buffer.from('new'));}
    if (alteration === 'delete' || alteration === 'rename') next.entries.delete(variants[0].path);
    if (alteration === 'rename') {next.entries.set('src/renamed.mbt', {kind: 'blob', mode: '100644'}); next.contents.set('src/renamed.mbt', Buffer.from('renamed'));}
    if (alteration === 'symlink') next.entries.get(variants[0].path).mode = '120000';
    assert.throws(() => mutationSourceInputs({tree: next, source: original}), /membership differs|nonregular/);
  }
  const next = inputTree(); next.entries.delete('proofs/ci-evidence/Claims.lean');
  assert.throws(() => mutationSourceInputs({tree: next, source: snapshot(next)}), /Missing\/nonregular/);
  assert(!before.files.some(entry => entry.path === fixturePath));
});

test('scientific identity preserves row identity, Unicode, order, NULL, schema, failure, work and stage observations', () => {
  const {reports} = cohort(false), report = reports[0].report;
  const action = mutationActions(report.decision).find(entry => entry.part === report.part.id && entry.target === 'js' && entry.phase === 'mutated');
  const before = mutationActionObservation(report, action).scientificDigest;
  for (const change of [
    o => {o.rows.reverse(); o.rows.push(['different', null]);},
    o => {o.rows[0][0] = 0;}, o => {o.wireRows[0].text = '\u00e9';},
    o => {o.columns.reverse();}, o => {o.schemaColumns.push('new');},
    o => {o.kind = 'complete';}, o => {o.work++;}, o => {o.faults = [];},
    o => {o.stageValues[0].rows[0][1] = '\u00e9';},
  ]) {
    const next = structuredClone(report); change(next.results[0].executions[0].receipt.cases[0].observation);
    assert.notEqual(mutationActionObservation(next, action).scientificDigest, before);
  }
  const row = structuredClone(report); row.results[0].minimal.rows[0].id = 'different-row-identity';
  assert.notEqual(mutationActionObservation(row, action).scientificDigest, before);
  const relabel = structuredClone(report);
  const e = relabel.results[0].executions[0]; e.receipt.cases[0].id = 'another-observation-owner';
  e.receipt.cases[0].observation.id = e.receipt.cases[0].id;
  assert.equal(mutationActionObservation(relabel, action).scientificDigest, before);
  assert.throws(() => mutationActionObservation(report, {...action, phase: 'pristine'}), /Unregistered/);
});

test('the exact archived mutation part projects nine historical observations without current-plan acceptance', () => {
  const bytes = gunzipSync(readFileSync(new URL('../../docs/reviews/evidence/2026-10-06-pipeline-main-37198759659-L-M0-fixed.json.gz', import.meta.url)),
    {maxOutputLength: 4 * 1024 * 1024});
  assert.equal(hash(bytes), '5ce6b98807105317e43a3496e08045ff403afad2081d9e8dfeca61ea146d9e22');
  const report = JSON.parse(bytes), before = JSON.stringify(report);
  const selected = mutationActions(report.decision).filter(action => action.part === 'L-M0a' && action.mode === 'fixed');
  assert.equal(selected.length, 9);
  // Current-plan admission must continue refusing this older plan unchanged.
  for (const action of selected) assert.throws(() => mutationActionObservation(report, action), /Foreign action part/);
  const historical = archivedMutationActionObservations(bytes);
  assert.equal(historical.authority, 'immutable-historical-projection');
  assert.equal(historical.revision, '7c4bcb61b8d7e7c37b4be8eb986e1811842d345b');
  assert.equal(historical.planDigest, '2bf06c72bdcf5f92cc5f24517a8aaab7186aa9570f5c16512d8c103f9d6dc42c');
  const observations = historical.observations;
  assert.equal(observations.length, 9);
  assert(observations.every(entry => entry.action.profile.planDigest === historical.planDigest));
  assert.throws(() => archivedMutationActionObservations(Buffer.from(before)), /historical mutation bytes/);
  const relabeled = structuredClone(report); relabeled.part.planDigest = selected[0].profile.planDigest;
  assert.throws(() => archivedMutationActionObservations(Buffer.from(JSON.stringify(relabeled, null, 2) + '\n')),
    /historical mutation bytes/);
  assert(observations.every(entry => entry.units === 4));
  assert.equal(observations.flatMap(entry => entry.selected.flatMap(row => row.executions)).length, 36);
  assert.equal(new Set(observations.map(entry => entry.scientificDigest)).size, 9);
  assert.equal(JSON.stringify(report), before);
  assert.equal(report.revision, '7c4bcb61b8d7e7c37b4be8eb986e1811842d345b');
});

test('the real pinned Lean checker accepts the complete fresh pipeline plan and rejects missing or substituted obligations', () => {
  const records = mutationActionRecords(cohort());
  const requirements = records.actions.map(entry => entry.required), applications = records.actions.map(entry => entry.application);
  assert.equal(checkPlan(requirements, applications).accepted, true);
  assert.throws(() => checkPlan(requirements, applications.slice(1)), /Lean rejected/);
  const [required] = requirements, [application] = applications;
  for (const changed of [{...application, target: 'native'}, {...application, scope: 'f'.repeat(64)},
    {...application, units: 0}, {...application, reused: true}, {...application, origin: 'b'.repeat(40)}])
    assert.throws(() => checkPlan([required], [changed]), /Lean rejected/);
});
