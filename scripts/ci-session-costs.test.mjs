import assert from 'node:assert/strict';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {storedZip} from './fixtures/ci-artifact-zip.mjs';
import {costFixture} from '../proofs/ci-evidence/costs-fixture.mjs';
import {encode} from '../proofs/bounded-session/action-inputs.mjs';
import {hash} from '../proofs/ci-evidence/inputs.mjs';
import {canonicalReceipt} from '../proofs/ci-evidence/receipts.mjs';
import {analyzeArtifactSelection, formatArtifactEvidence} from './ci-artifacts.mjs';

const bytes = value => Buffer.from(`${encode(value)}\n`);
function fixture(reused = false) {
  // Independently specified phase/job intervals, not a physical campaign or API authentication.
  const f = costFixture(reused, true), {state, receipts} = f;
  const entries = {'context.json': bytes(state), 'collection-costs.json': f.collectionBytes,
    'acquisition-plan.json': bytes(f.acquisition), 'comparison-plan.json': bytes(f.comparison)};
  entries['checked.json'] = bytes({...f.certificate, version: 'actql-verification-family-certificate/0.1',
    mode: 'scoped-execution', catalogDigest: hash(encode(f.catalog)),
    acquisitionDigest: hash(entries['acquisition-plan.json']), comparisonDigest: hash(entries['comparison-plan.json']),
    receiptDigests: receipts.map(r => ({actionId: r.action.id, digest: hash(canonicalReceipt(r))}))});
  for (const receipt of receipts) entries[`receipts/${receipt.action.id}.json`] = canonicalReceipt(receipt);
  if (f.isolatedExecution) entries['isolated-execution.json'] = bytes(f.isolatedExecution);
  const provenance = {repository: 'actql/actql', runId: 30, attempt: 1, workflow: 'CI',
    workflowPath: '.github/workflows/ci.yml', event: 'pull_request', headSha: state.origin.runHeadRevision,
    executionSha: state.origin.testedRevision, status: 'completed', conclusion: 'success',
    artifact: {id: 1, name: 'session-actions', sha256: 'e'.repeat(64), compressedBytes: 999}};
  const job = (id, name, seconds) => ({id, name, identityMatches: true, headSha: provenance.headSha,
    status: 'completed', conclusion: 'success', endpoint: '/selected/jobs', runnerName: 'fixture-runner',
    runnerLabels: ['linux', 'x64'], createdAt: '2026-10-06T00:00:00Z', startedAt: '2026-10-06T00:00:01Z',
    completedAt: `2026-10-06T00:00:${String(seconds + 1).padStart(2, '0')}Z`, steps: [{number: 1,
      name: 'observed execution', status: 'completed', conclusion: 'success', startedAt: '2026-10-06T00:00:01Z',
      completedAt: `2026-10-06T00:00:${String(seconds + 1).padStart(2, '0')}Z`} ]});
  const attempt = {number: 1, available: true, headSha: provenance.headSha, workflow: 'CI',
    workflowId: 2, workflowPath: provenance.workflowPath, event: provenance.event, pullRequests: [{number: 1, baseSha: 'a'.repeat(40)}],
    status: 'completed', conclusion: 'success', evidenceComplete: true, jobsAvailable: true,
    endpoint: '/selected/attempt', jobs: [job(4, 'session-evidence', 10), job(5, 'check', 4), job(6, 'other', 6)]};
  const selection = {version: 'actql-ci-artifact-selection/0.1', samples: [{archive: 'controlled.zip', provenance,
    reports: {session: 'checked.json'}}], timingEvidence: {repository: provenance.repository,
    observedAt: '2026-10-06T00:00:20Z', runs: [{id: 30, attempts: [attempt]}]}};
  const open = async () => ({compressedBytes: 999, entries: Object.keys(entries).map(path => ({path})),
    read: async path => {assert(entries[path], `Missing original ${path}`); return entries[path];},
    json: async path => JSON.parse(entries[path]), close: async () => {}});
  return {entries, selection, attempt, open};
}
const analyze = f => analyzeArtifactSelection(f.selection, 'actql/actql', f.open);

test('the existing offline consumer joins all 30 bound costs to distinct enclosing owner jobs', async () => {
  for (const reused of [false, true]) {
    const report = await analyze(fixture(reused)), value = report.samples[0].sessionCosts;
    assert.equal(report.complete, true); assert.equal(value.cost.actions.length, 30);
    assert.equal(value.runner.selectedJobMilliseconds, 14000);
    assert.equal(value.runner.attemptRunnerMilliseconds, 20000);
    assert.equal(value.runner.observedJobWallSpan.seconds, 10); // Parallel wall time is not 20 seconds.
    assert.equal(value.runner.nestedPhasesAdded, false);
    const mutation = value.cost.actions.find(a => a.actionId === 'mutations-js');
    assert.equal(mutation.currentMilliseconds, reused ? null : 17);
    assert.equal(mutation.originMilliseconds, 17);
    assert.equal(value.netRunnerSavingsMilliseconds, null); assert.equal(value.reuseAuthorized, false);
    assert.match(formatArtifactEvidence(report), /whole attempt runner total 20000 ms/u);
  }
});

test('missing, zero-step and incomplete runner observations are unknown, never zero-cost savings', async () => {
  for (const alter of [
    f => delete f.selection.timingEvidence,
    f => f.attempt.jobs.splice(1, 1),
    f => {f.attempt.jobs[0].steps = [];},
    f => {f.attempt.jobs[0].status = 'in_progress';},
    f => {f.attempt.jobs[1].conclusion = 'failure';},
  ]) {
    const f = fixture(true); alter(f);
    const report = await analyze(f), value = report.samples[0].sessionCosts;
    assert.equal(report.complete, false); assert.equal(value.runner.selectedJobMilliseconds, null);
    assert.equal(value.netRunnerSavingsMilliseconds, null);
  }
});

test('actual bindings reject wrong run, attempt, producer, catalog, receipt and current reused execution', async () => {
  for (const alter of [
    f => {const c = JSON.parse(f.entries['context.json']); c.origin.runId++; f.entries['context.json'] = bytes(c);},
    f => {const c = JSON.parse(f.entries['context.json']); c.context.runAttempt++; f.entries['context.json'] = bytes(c);},
    f => {const c = JSON.parse(f.entries['checked.json']); c.catalogDigest = 'f'.repeat(64); f.entries['checked.json'] = bytes(c);},
    f => {f.entries['collection-costs.json'] = bytes({});},
    f => {delete f.entries['receipts/events-connection-wasm.json'];},
    f => {f.attempt.jobs[0].name = 'another';},
    f => {f.attempt.jobs.push({...f.attempt.jobs[1], id: 7});},
    f => {f.entries['isolated-execution.json'] = bytes({});},
  ]) { const f = fixture(true); alter(f); await assert.rejects(analyze(f)); }
});

test('Session cost selection cannot hide pipeline reports in a different source archive', async () => {
  for (const reports of [{session: ''}, {session: 'another.json'}, {session: 'checked.json', fixed: 'fixed.json'}]) {
    const f = fixture(); f.selection.samples[0].reports = reports;
    await assert.rejects(analyze(f), /complete separate source archive/u);
  }
});

test('the real stored-ZIP CLI consumes reused costs and keeps unavailable timing incomplete', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'session-cost-zip-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  for (const timed of [true, false]) {
    const f = fixture(true), archive = storedZip(f.entries), sample = f.selection.samples[0];
    sample.provenance.artifact.sha256 = hash(archive); sample.provenance.artifact.compressedBytes = archive.length;
    if (!timed) delete f.selection.timingEvidence;
    const manifest = join(directory, 'selection.json');
    await writeFile(join(directory, sample.archive), archive);
    await writeFile(manifest, JSON.stringify(f.selection));
    const result = spawnSync(process.execPath, [fileURLToPath(new URL('./ci-evidence.mjs', import.meta.url)),
      'actql/actql', '--artifacts', manifest, '--json'], {encoding: 'utf8', timeout: 10000, maxBuffer: 4 * 1024 * 1024});
    assert.equal(result.error, undefined); assert.equal(result.stderr, ''); assert.equal(result.status, timed ? 0 : 1);
    const report = JSON.parse(result.stdout), value = report.samples[0].sessionCosts;
    assert.equal(report.complete, timed); assert.equal(value.runner.selectedJobMilliseconds, timed ? 14000 : null);
    assert.equal(value.cost.actions.find(a => a.actionId === 'mutations-js').currentMilliseconds, null);
    assert.equal(value.netRunnerSavingsMilliseconds, null);
  }
});
