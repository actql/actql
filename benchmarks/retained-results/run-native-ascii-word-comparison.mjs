// One fixed Native resident case. This is not the registered historical baseline
// or qualification of a measured cost profile for an older binary.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {readFile, writeFile, mkdir, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve, join, sep} from 'node:path';
import {performance} from 'node:perf_hooks';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {retainedCase, workloads} from './fixtures.mjs';
import {prepareNativeDirectProduct, executeNativeDirectProduct, admitNativeDirectProduct} from './native-direct-product.mjs';
import {assessPairedTiming} from './paired-assessment.mjs';
import {sha256File} from './release-artifacts.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const exec = promisify(execFile);
const [baselinePath, outputPath, ...extra] = process.argv.slice(2);
assert(baselinePath && outputPath && !extra.length, 'ExpectedNativeAsciiBaselineAndOutput');
const destination = resolve(outputPath);
assert(destination !== root && !destination.startsWith(root + sep), 'NativeComparisonOutputInsideCheckout');
const beforeBinary = resolve(baselinePath);
const baselineRevision = 'f8c6876389430490cdfd09c3e576d77c6d227d06';
const beforeDigest = '18c389007dcdd78638895b9b3d6a88c36783a342c8a1667ffe8a8c849a5a9830';
assert.equal(await sha256File(beforeBinary), beforeDigest, 'NativeAsciiBaselineChanged');
const afterBinary = join(root, '_build/native/release/build/cmd/native_retained_case_probe/native_retained_case_probe.exe');
const afterDigest = await sha256File(afterBinary);
assert.notEqual(afterDigest, beforeDigest, 'NativeAsciiChangeNotBuilt');
const git = async args => (await exec('git', args, {cwd: root})).stdout.trim();
const revision = await git(['rev-parse', 'HEAD']);
const sourceChanges = (await git(['diff', '--name-only', baselineRevision, revision, '--', 'src'])).split('\n').filter(Boolean);
assert.deepEqual(sourceChanges.sort(), ['src/sha256/incremental_wbtest.mbt', 'src/sha256/sha256.mbt']);
const unchanged = async () => {
  assert.equal(await git(['rev-parse', 'HEAD']), revision);
  assert.equal(await git(['status', '--porcelain']), '', 'NativeComparisonRequiresCleanCheckout');
  assert.equal(await sha256File(beforeBinary), beforeDigest);
  assert.equal(await sha256File(afterBinary), afterDigest);
};
await unchanged();
const fixture = retainedCase(workloads[0], 'narrow', 100);
const directory = await mkdtemp(join(tmpdir(), 'actql-native-ascii-word-'));
const database = join(directory, 'source.duckdb');
const label = 'native-ascii-word-loop';
const pairs = [];
const basis = {revision, baselineRevision, beforeDigest, afterDigest, sourceChanges,
  caseId: fixture.id, limits: fixture.limits,
  method: '21 predeclared alternating pairs; fresh Native processes; one immutable source; OS-cache coldness uncontrolled',
  host: 'native', providedAcquisition: ['native'],
  computeConditions: 'Same existing explicit resident experiment on both binaries: Local/fresh 1000 ms, resident default 1 ms. These are fixed control inputs, not new measured estimates or an invented planner reason.',
  scopes: {cycle: 'application files, full binary hash, process exit and product/Owner admission; common source preparation reported separately',
    executionMs: 'probe entry through final result identity; includes preparation, not only task execution',
    applicationPreparationMs: 'actual application-start to library-start clock interval',
    computeAndIdentityMs: 'actual strategy-execute to execution-end clock interval',
    warmMs: 'sequential task intervals; not added to enclosing intervals',
    observer: 'existing physical phase observer on both legs; overhead retained in raw events'},
  originalEquivalentGate: 'Separate current-SHA calibrated release-pair acceptance; this controller does not issue that certificate'};
let sourceContentSha256, sourcePreparationMilliseconds;
const save = extra => writeFile(destination, JSON.stringify({...basis, sourceContentSha256,
  sourcePreparationMilliseconds, pairs, ...extra}, null, 2));
try {
  const sourceStart = performance.now();
  await exec(process.execPath, [join(root, 'adapters/connectors/duckdb/node/bench/create-retained-source.mjs'),
    database, fixture.workload, fixture.layout, String(fixture.rows)], {cwd: root, timeout: fixture.limits.timeoutMs});
  sourcePreparationMilliseconds = performance.now() - sourceStart;
  sourceContentSha256 = await sha256File(database);
  await save({status: 'measuring'});
  for (let index = 0; index < 21; index++) {
    const legs = {};
    for (const leg of index % 2 ? ['after', 'before'] : ['before', 'after']) {
      await unchanged();
      const child = join(directory, leg + '-' + index); await mkdir(child);
      const start = performance.now();
      const prepared = await prepareNativeDirectProduct({root, fixture, database, directory: child,
        residentPolicy: true, localRates: ['1000', '1000', '1000'], nativeRates: ['1000', '1000', '1000'],
        phaseObserver: true});
      const invocation = {...prepared, binary: leg === 'before' ? beforeBinary : afterBinary};
      assert.equal(await sha256File(invocation.binary), leg === 'before' ? beforeDigest : afterDigest);
      const execution = await executeNativeDirectProduct(invocation, {root, timeoutMs: fixture.limits.timeoutMs});
      const admissionStart = performance.now();
      const product = admitNativeDirectProduct(fixture, invocation, execution);
      const end = performance.now();
      assert.deepEqual(product.ownerCorrespondence.observations.choices.map(value => value.resident), [true, true, true]);
      assert.equal(await sha256File(database), sourceContentSha256, 'NativeComparisonSourceChanged');
      await unchanged();
      legs[leg] = {product, admissionMilliseconds: end - admissionStart,
        sample: {status: 'completed', processCycleMs: end - start,
          executionMs: product.executionMs, cleanupMs: product.cleanupMs,
          coldMs: end - start - product.cleanupMs, warmMs: product.warmMs,
          applicationPreparationMs: product.preparation.applicationMs,
          computeAndIdentityMs: product.preparation.computeAndIdentityMs}};
    }
    for (const field of ['taskHoldings', 'taskUsages', 'acquisitionChoice', 'acquisitionEvidenceMetadata']) {
      assert.deepEqual(legs.before.product[field], legs.after.product[field], 'NativeAsciiObligationChanged:' + field);
    }
    for (const field of ['owners', 'candidates', 'choices', 'explanations', 'acquisitionChoices', 'plannerObserverWork']) {
      assert.deepEqual(legs.before.product.ownerCorrespondence.observations[field],
        legs.after.product.ownerCorrespondence.observations[field], 'NativeAsciiOwnerChanged:' + field);
    }
    assert.deepEqual(legs.before.product.record.usage, legs.after.product.record.usage);
    pairs.push({index, caseId: fixture.id,
      order: index % 2 ? ['retained-actql', label] : [label, 'retained-actql'],
      samples: {[label]: legs.before.sample, 'retained-actql': legs.after.sample}, legs});
    await save({status: 'measuring'});
  }
  const fields = ['processCycleMs', 'executionMs', 'coldMs', 'warmMs', 'cleanupMs', 'applicationPreparationMs', 'computeAndIdentityMs'];
  const timing = Object.fromEntries(fields.map(field => [field, assessPairedTiming(pairs,
    {comparator: label, field, mode: 'difference', threshold: 0, minimumPairs: 21})]));
  const observedCycleReduction = timing.processCycleMs.status === 'pass' && timing.processCycleMs.upper < 0;
  const qualification = 'Observed timing only; assess first-use/environmental effects separately before attributing a runtime speedup';
  await save({status: 'completed', timing, observedCycleReduction, qualification});
  console.log(JSON.stringify({revision, destination, timing, observedCycleReduction, qualification}));
} catch (error) {
  await save({status: 'failed', error: {name: error.name, message: error.message, code: error.code}});
  throw error;
} finally {await rm(directory, {recursive: true, force: true});}
