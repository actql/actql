import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {artifactPath, duration, projectCampaign, inventoryStorage, analyzeArtifactSelection, compareArtifactSamples, formatArtifactEvidence, collectArtifactEvidence} from './ci-artifacts.mjs';
const sha = value => createHash('sha256').update(value).digest('hex');
const hash = value => sha(JSON.stringify(value));
const source = 'a'.repeat(40);
const row = name => ({name, site: 'src/site.mbt', anchor: {kind: 'wrong'}, original: {rows: [1, 2]}, minimal: {rows: [1]},
  localMinimal: true, killed: true, history: [{attempted: 3, accepted: 1}], finalCandidates: [{rows: []}],
  replay: {js: {id: '1', kind: 'failed'}, wasm: {id: '2', kind: 'failed'}, native: {id: '3', kind: 'failed'}},
  healthy: {js: {id: '4', kind: 'complete'}, wasm: {id: '5', kind: 'complete'}, native: {id: '6', kind: 'complete'}},
  timing: {searchMs: 2, shrinkMs: 3, mutatedReplayMs: {js: 5, wasm: 7, native: 11}, restoredReplayMs: {js: 13, wasm: 17, native: 19}}, executions: [], healthyExecutions: []});
const campaign = () => ({version: 'actql-relation-pipeline-mutations/0.1', mode: 'explore', revision: source, source: {digest: 'b'.repeat(64)}, explorationTarget: 'js', seed: 7, results: [row('one'), row('two')]});
const inventory = {fixed: ['one', 'two'], fresh: ['one', 'two'], targets: ['js', 'wasm', 'native']};
function fakeZip(entries) {
  const values = new Map(Object.entries(entries).map(([path, body]) => [path, Buffer.isBuffer(body) ? body : Buffer.from(typeof body === 'string' ? body : JSON.stringify(body))]));
  return {entries: [...values].map(([path, data]) => ({path, bytes: data.length, compressedBytes: Math.ceil(data.length / 2)})), compressedBytes: 999,
    async digest(path) { if (!values.has(path)) throw Error('missing'); return sha(values.get(path)); },
    async json(path) { if (!values.has(path)) throw Error('missing'); return JSON.parse(values.get(path)); }, async close() {}};
}
function selected(attempt = 1, conclusion = 'success') {
  return {archive: 'fixture.zip', provenance: {repository: 'actql/actql', runId: 10, attempt, workflow: 'CI', workflowPath: '.github/workflows/ci.yml',
    event: 'pull_request', headSha: 'c'.repeat(40), executionSha: source, status: 'completed', conclusion,
    runner: {region: 'fixture'}, cacheState: 'unknown', artifact: {id: 20 + attempt, name: 'fixture', sha256: 'd'.repeat(64), compressedBytes: 999}},
    reports: {fixed: 'relation-pipeline/fixed.json', fresh: 'relation-pipeline/fresh.json'}, expectedInventory: inventory};
}
const select = samples => ({version: 'actql-ci-artifact-selection/0.1', samples});
const withFixture = async samples => analyzeArtifactSelection(select(samples), 'actql/actql', async () => fakeZip({'relation-pipeline/fixed.json': {...campaign(), mode: 'fixed'}, 'relation-pipeline/fresh.json': campaign()}));

test('hand-authored phase sums keep targets and fixed/fresh boundaries', () => {
  const fresh = projectCampaign(campaign(), 'fresh', inventory);
  assert.equal(fresh.phases.length, 16);
  assert.equal(fresh.aggregates.find(x => x.phase === 'search').actionMilliseconds, 4);
  assert.equal(fresh.aggregates.find(x => x.phase === 'mutated' && x.target === 'native').actionMilliseconds, 22);
  assert.equal(fresh.aggregates.find(x => x.phase === 'healthy' && x.target === 'wasm').actionMilliseconds, 34);
  assert.equal(projectCampaign(campaign(), 'fixed', inventory).phases.length, 12);
  assert.equal(fresh.mutations[0].attemptedCandidateCount, 3);
});
test('missing, negative, string and non-finite duration never become zero', () => {
  for (const value of [undefined, null, -1, NaN, Infinity, '5']) assert.equal(duration(value).milliseconds, null);
  assert.equal(duration(0).milliseconds, 0);
  const data = campaign(); delete data.results[0].timing.shrinkMs;
  const projected = projectCampaign(data, 'fresh', inventory);
  const total = projected.aggregates.find(x => x.phase === 'shrink');
  assert.equal(total.actionMilliseconds, null); assert.equal(total.knownActionMilliseconds, 3);
});
test('incomplete inventory and target substitution make aggregate unknown', () => {
  const data = campaign(); data.results.pop();
  assert.equal(projectCampaign(data, 'fresh', inventory).aggregates[0].actionMilliseconds, null);
  const other = campaign(); delete other.results[0].healthy.wasm; other.results[0].healthy.gpu = {};
  const result = projectCampaign(other, 'fresh', inventory);
  assert.equal(result.targetComplete, false);
  assert.equal(result.aggregates.find(x => x.phase === 'healthy' && x.target === 'wasm').actionMilliseconds, null);
  assert.equal(projectCampaign(campaign(), 'fresh', {}).inventoryComplete, false);
});
test('unsafe retained references are rejected without filesystem access', () => {
  assert.equal(artifactPath('.artifacts/relation-pipeline/receipt.json'), 'relation-pipeline/receipt.json');
  for (const path of ['../outside', '/outside', 'a/../b', 'C:/out', 'a\\b', 'a//b', 'a/./b', 'a\0b']) assert.throws(() => artifactPath(path));
});
test('shared referenced binaries and duplicate content stay protected', async () => {
  const zip = fakeZip({'binaries/one.exe': 'same', 'binaries/two.exe': 'same', 'output.log': 'log'});
  const report = await inventoryStorage(zip, [
    {from: 'receipt-a', path: 'binaries/one.exe', digest: sha('same'), kind: 'executable'},
    {from: 'receipt-b', path: null, originalPath: '_build/shared.exe', digest: sha('same'), kind: 'executable'},
    {from: 'receipt-c', path: 'absent.exe', digest: sha('none'), kind: 'executable'},
    {from: 'receipt-d', path: '../secret', digest: sha('no'), kind: 'executable'},
  ]);
  assert.equal(report.logicalFileBytes, 11); assert.equal(report.compressedArtifactBytes, 999);
  assert.equal(report.identicalContentExtraLogicalBytes, 4); assert.equal(report.recoverableDiskBytes, null);
  assert.equal(report.categories.executable.referencedBytes, 8);
  assert.deepEqual(report.files[0].referencedBy, ['receipt-a', 'receipt-b']);
  assert.equal(report.files[2].protection, 'unknown-protected');
  assert.deepEqual(report.deletionCandidates, []);
  assert.deepEqual(report.references.unresolved.map(x => x.reason), ['missing-reference', 'unsafe-reference']);
});
test('failed/cancelled runs retain complete individual phases without green promotion', async () => {
  for (const conclusion of ['failure', 'cancelled']) {
    const report = await withFixture([selected(1, conclusion)]);
    assert.equal(report.samples[0].reportedRunSuccessful, false);
    assert.equal(report.samples[0].campaigns[0].aggregates[0].actionMilliseconds, 10);
    assert.match(formatArtifactEvidence(report), new RegExp(`completed/${conclusion}`));
    assert.equal(report.samples[0].unmeasured.buildCount, null);
  }
});
test('repeated attempt identities stay separate; repeated selection is rejected', async () => {
  const report = await withFixture([selected(1), selected(2)]);
  assert.equal(report.samples.length, 2);
  assert.ok(report.comparisons[0].differences.includes('attempt'));
  assert.deepEqual(report.comparisons[0].sampleCounts, {left: 1, right: 1});
  await assert.rejects(withFixture([selected(1), selected(1)]), /Duplicate/);
});
test('source and region differences are visible and n=1 never produces speedup', async () => {
  const one = selected(), two = selected(2); two.provenance.runner.region = 'another'; two.provenance.executionSha = 'e'.repeat(40);
  const report = await withFixture([one, selected(2)]);
  report.samples[1].provenance = two.provenance;
  const comparison = compareArtifactSamples(report.samples)[0];
  assert.ok(comparison.differences.includes('runner'));
  assert.ok(comparison.differences.includes('executionSha'));
  assert.equal(comparison.stableSpeedupEstimate, null); assert.equal(comparison.causalPerformanceClaim, false);
});
test('receipt resolution verifies immutable canonical data and deduplicates references', async () => {
  const receipt = {target: 'js', command: ['moon', 'test', '--target', 'js'], compiler: 'fixture', exit: 0,
    sourcePath: '.artifacts/sources/s.json', sourceDigest: hash({a: 'b'}), fixturePath: '.artifacts/fixture.mbt', fixtureDigest: sha('fixture'),
    inputPath: '.artifacts/input.json', inputDigest: sha('{}'), logPath: '.artifacts/log.log', logDigest: sha('log'),
    artifacts: {}, cases: [{testCase: {rows: []}}]};
  const execution = {path: '.artifacts/receipt.json', digest: hash(receipt), receipt};
  const data = campaign(); data.results[0].executions = [execution, execution];
  const sample = selected(); sample.reports = {fresh: 'report.json'};
  const report = await analyzeArtifactSelection(select([sample]), 'actql/actql', async () => fakeZip({
    'report.json': data, 'receipt.json': receipt, 'sources/s.json': {sources: {a: 'b'}}, 'fixture.mbt': 'fixture', 'input.json': '{}', 'log.log': 'log'}));
  assert.equal(report.samples[0].receipts.uniqueReceipts, 1);
  assert.equal(report.samples[0].receipts.duplicateOccurrences, 1);
  assert.equal(report.samples[0].receipts.caseObservations, 1);
  assert.equal(report.samples[0].receipts.errors.length, 0);
  assert.equal(report.samples[0].storage.references.unresolved.length, 0);
  assert.equal(report.complete, false); // This fixture verifies one receipt, not all phase coverage.
  execution.digest = '0'.repeat(64);
  const bad = await analyzeArtifactSelection(select([sample]), 'actql/actql', async () => fakeZip({'report.json': data, 'receipt.json': receipt}));
  assert.equal(bad.complete, false); assert.equal(bad.samples[0].receipts.errors[0].reason, 'receipt-digest-mismatch');
});
test('wrong execution SHA and incomplete provenance fail closed', async () => {
  const sample = selected(); sample.provenance.executionSha = 'f'.repeat(40);
  await assert.rejects(withFixture([sample]), /execution SHA/);
  delete sample.provenance.artifact.sha256;
  await assert.rejects(withFixture([sample]), /provenance/);
});
test('capacity phases are separate from enclosing durations and eight-mutant campaigns', () => {
  const capacity = {revision: source, mutations: [{...row('capacity-one'), timings: {}, durationMs: 1000}],
    timings: {js: 1, wasm: 2, native: 3, boundaries: {'-1': {js: 4, wasm: 5, native: 6}, '0': {js: 7, wasm: 8, native: 9}, '1': {js: 10, wasm: 11, native: 12}}}, executions: []};
  const report = projectCampaign(capacity, 'capacity', {capacity: ['capacity-one'], targets: inventory.targets});
  assert.equal(report.campaign, 'capacity'); assert.equal(report.mutations[0].enclosingDuration.milliseconds, 1000);
  assert.equal(report.aggregates.find(x => x.phase === 'boundary' && x.target === 'js').actionMilliseconds, 21);
  assert.equal(report.aggregates.find(x => x.phase === 'normal' && x.target === 'js').actionMilliseconds, 1);
});


test('empty selections, wrong report mode and malformed schema cannot claim evidence', async () => {
  const sample = selected(); sample.reports = {};
  await assert.rejects(withFixture([sample]), /No recognized/);
  sample.reports = {fixed: 'report.json'};
  await assert.rejects(analyzeArtifactSelection(select([sample]), 'actql/actql', async () => fakeZip({'report.json': campaign()})), /schema or mode/);
});
test('aggregate overflow and absent phases block comparison', async () => {
  const data = campaign(); data.results.forEach(x => x.timing.searchMs = 1e308);
  assert.equal(projectCampaign(data, 'fresh', inventory).aggregates[0].actionMilliseconds, null);
  const report = await withFixture([selected(), selected(2)]);
  report.samples[1].campaigns[0].phases[0].milliseconds = null;
  report.samples[1].storage.references.unresolved.push({reason: 'missing-reference'});
  const comparison = compareArtifactSamples(report.samples)[0];
  assert.ok(comparison.differences.includes('incomplete-phase-timing'));
  assert.ok(comparison.differences.includes('unresolved-custody-references'));
});
test('selection manifest is bounded before content reading', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'ci-artifact-selection-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const path = join(directory, 'large.json');
  await writeFile(path, Buffer.alloc(4 * 1024 * 1024 + 1));
  await assert.rejects(collectArtifactEvidence({artifacts: path, repository: 'actql/actql'}), /bounded regular file/);
  await assert.rejects(collectArtifactEvidence({artifacts: directory, repository: 'actql/actql'}), /bounded regular file/);
});
test('duplicate embedded receipts and archive substitutions are validated per occurrence', async () => {
  const receipt = {target: 'js', command: ['moon'], compiler: 'fixture', exit: 0, cases: [{}]};
  const first = {path: 'receipt.json', digest: hash(receipt), receipt, capacityArchives: {x: 'original.exe'}};
  for (const second of [{...first, receipt: {...receipt, command: ['other']}}, {...first, capacityArchives: {x: 'substitute.exe'}}]) {
    const data = campaign(); data.results[0].executions = [first, second];
    const sample = selected(); sample.reports = {fresh: 'report.json'};
    const report = await analyzeArtifactSelection(select([sample]), 'actql/actql', async () => fakeZip({'report.json': data, 'receipt.json': receipt}));
    assert.equal(report.complete, false);
    assert.equal(report.samples[0].receipts.errors.length, 1);
  }
});


function completeFixture() {
  const receipt = {target: 'js', command: ['moon', '--target', 'js'], compiler: 'fixture', exit: 0, cases: [{}],
    sourcePath: 'sources.json', sourceDigest: hash({a: 'b'}), fixturePath: 'fixture.mbt', fixtureDigest: sha('fixture'),
    inputPath: 'input.json', inputDigest: sha('{}'), logPath: 'log.log', logDigest: sha('log'), artifacts: {}};
  const data = campaign(); data.results = [row('one')];
  data.results[0].replay = {js: {kind: 'failed'}}; data.results[0].healthy = {js: {kind: 'complete'}};
  data.results[0].timing.mutatedReplayMs = {js: 5}; data.results[0].timing.restoredReplayMs = {js: 13};
  const executions = ['search', 'shrink', 'minimal', 'restored'].map(phase => ({path: `one-${phase}-js.json`, digest: hash(receipt), receipt}));
  data.results[0].executions = executions.slice(0, 3); data.results[0].healthyExecutions = executions.slice(3);
  const sample = selected(); sample.reports = {fresh: 'report.json'}; sample.expectedInventory = {fresh: ['one'], targets: ['js']};
  const entries = () => ({
    'report.json': data, ...Object.fromEntries(executions.map(e => [e.path, e.receipt])), 'sources.json': {sources: {a: 'b'}},
    'fixture.mbt': 'fixture', 'input.json': '{}', 'log.log': 'log'});
  const check = () => analyzeArtifactSelection(select([sample]), 'actql/actql', async () => fakeZip(entries()));
  return {data, sample, executions, entries, check};

}

test('complete selected evidence requires each phase receipt and all completeness dimensions', async () => {
  const {data, sample, executions, check} = completeFixture();
  assert.equal((await check()).complete, true);
  data.results[0].executions.splice(1, 1);
  let report = await check();
  assert.equal(report.complete, false); assert.equal(report.samples[0].selectedEvidenceComplete, false);
  assert.equal(report.samples[0].campaigns[0].phases.find(p => p.phase === 'shrink').receiptCoverage.state, 'unverified-or-unavailable');
  data.results[0].executions = executions.slice(0, 3);
  sample.expectedInventory.fresh.push('missing'); assert.equal((await check()).complete, false); sample.expectedInventory.fresh.pop();
  delete data.results[0].healthy.js; assert.equal((await check()).complete, false); data.results[0].healthy.js = {kind: 'complete'};
  delete data.results[0].timing.searchMs; assert.equal((await check()).complete, false);
});
test('optional wall-clock evidence must match the selected immutable attempt identity', async () => {
  const sample = selected(), selection = select([sample]);
  selection.timingEvidence = {repository: 'actql/actql', runs: [{id: 10, attempts: [{number: 1, headSha: 'f'.repeat(40)}]}]};
  await assert.rejects(analyzeArtifactSelection(selection, 'actql/actql', async () => fakeZip({
    'relation-pipeline/fixed.json': {...campaign(), mode: 'fixed'}, 'relation-pipeline/fresh.json': campaign()})), /Timing attempt identity/);
});

function emptyReceipt(execution) {
  execution.receipt = {...execution.receipt, cases: []};
  execution.digest = hash(execution.receipt);
}

test('each required phase receipt needs observations even when the other phases are nonempty', async () => {
  for (const emptyIndexes of [[0, 1, 2, 3], [0], [1], [2], [3]]) {
    const {executions, check} = completeFixture();
    const valid = await check();
    assert.equal(valid.complete, true);
    assert.equal(valid.samples[0].selectedEvidenceComplete, true);
    assert.equal(valid.samples[0].receipts.caseObservations, 4);
    for (const index of emptyIndexes) emptyReceipt(executions[index]);
    const report = await check(), sample = report.samples[0];
    assert.equal(report.complete, false);
    assert.equal(sample.selectedEvidenceComplete, false);
    assert.equal(sample.receipts.caseObservations, 4 - emptyIndexes.length);
    assert.deepEqual(sample.receipts.errors, emptyIndexes.map(index => ({
      path: executions[index].path, reason: 'empty-receipt-cases',
    })));
    for (const [index, phase] of sample.campaigns[0].phases.entries()) {
      assert.equal(phase.receiptCoverage.state, emptyIndexes.includes(index) ?
        'unverified-or-unavailable' : 'verified-retained-receipts');
    }
  }
});

test('a nonempty receipt in the same phase cannot mask an empty receipt', async () => {
  const {data, executions, check} = completeFixture();
  const extra = {...executions[0], path: 'one-search-extra-js.json'};
  data.results[0].executions.push(extra); executions.push(extra);
  assert.equal((await check()).complete, true);
  emptyReceipt(extra);
  const report = await check(), sample = report.samples[0];
  assert.equal(sample.receipts.caseObservations, 4);
  assert.equal(report.complete, false);
  assert.equal(sample.selectedEvidenceComplete, false);
  assert.deepEqual(sample.receipts.errors, [{path: extra.path, reason: 'empty-receipt-cases'}]);
  assert.deepEqual(sample.campaigns[0].phases[0].receiptCoverage,
    {verifiedCount: 1, state: 'unverified-or-unavailable'});
});

// Independent stored-ZIP fixture for exercising the real offline CLI and its
// archive/receipt hashes, rather than only the in-memory projection boundary.
function storedZip(entries) {
  const locals = [], centrals = [];
  let offset = 0;
  for (const [path, value] of Object.entries(entries)) {
    const name = Buffer.from(path), data = Buffer.from(typeof value === 'string' ? value : JSON.stringify(value));
    let crc = 0xffffffff;
    for (const byte of data) {
      crc ^= byte;
      for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
    crc = (crc ^ 0xffffffff) >>> 0;
    const local = Buffer.alloc(30), central = Buffer.alloc(46);
    local.writeUInt32LE(0x04034b50); local.writeUInt16LE(20, 4);
    local.writeUInt32LE(crc, 14); local.writeUInt32LE(data.length, 18); local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(name.length, 26);
    central.writeUInt32LE(0x02014b50); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6);
    central.writeUInt32LE(crc, 16); central.writeUInt32LE(data.length, 20); central.writeUInt32LE(data.length, 24);
    central.writeUInt16LE(name.length, 28); central.writeUInt32LE(offset, 42);
    locals.push(local, name, data); centrals.push(central, name);
    offset += local.length + name.length + data.length;
  }
  const directory = Buffer.concat(centrals), end = Buffer.alloc(22), count = Object.keys(entries).length;
  end.writeUInt32LE(0x06054b50); end.writeUInt16LE(count, 8); end.writeUInt16LE(count, 10);
  end.writeUInt32LE(directory.length, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, directory, end]);
}

test('offline CLI exits nonzero for all-empty or one-empty phase receipts with recomputed hashes', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'ci-artifact-empty-cases-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const script = fileURLToPath(new URL('./ci-evidence.mjs', import.meta.url));
  for (const emptyIndexes of [[], [0, 1, 2, 3], [1]]) {
    const {sample, executions, entries} = completeFixture();
    for (const index of emptyIndexes) emptyReceipt(executions[index]);
    const archive = storedZip(entries());
    sample.provenance.artifact.sha256 = sha(archive);
    sample.provenance.artifact.compressedBytes = archive.length;
    const manifest = join(directory, 'selection.json');
    await writeFile(join(directory, sample.archive), archive);
    await writeFile(manifest, JSON.stringify(select([sample])));
    const result = spawnSync(process.execPath, [script, 'actql/actql', '--artifacts', manifest, '--json'], {encoding: 'utf8'});
    assert.equal(result.error, undefined); assert.equal(result.stderr, '');
    assert.equal(result.status, emptyIndexes.length ? 1 : 0);
    const report = JSON.parse(result.stdout), evidence = report.samples[0];
    assert.equal(report.complete, emptyIndexes.length === 0);
    assert.equal(evidence.selectedEvidenceComplete, emptyIndexes.length === 0);
    assert.equal(evidence.receipts.caseObservations, 4 - emptyIndexes.length);
    assert.deepEqual(evidence.receipts.errors, emptyIndexes.map(index => ({
      path: executions[index].path, reason: 'empty-receipt-cases',
    })));
  }
});
