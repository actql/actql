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
const [baselinePath, outputPath, condition, ...extra] = process.argv.slice(2);
assert(baselinePath && outputPath && !extra.length &&
  (condition === undefined || ['--matched-first-use', '--retained-continuation', '--retained-text-1000'].includes(condition)),
  'ExpectedNativePreparationBaselineAndOutput');
const continuation = condition === '--retained-continuation';
const retainedText = condition === '--retained-text-1000';
const matchedFirstUse = condition !== undefined;
const destination = resolve(outputPath);
assert(destination !== root && !destination.startsWith(root + sep), 'NativeComparisonOutputInsideCheckout');
const beforeBinary = resolve(baselinePath);
const baselineRevision = continuation ? 'fe0b68242d9e240494e85ecb0438f74f55855c88'
  : 'f8c6876389430490cdfd09c3e576d77c6d227d06';
const beforeDigest = continuation ? '2152155cc13ae8003df3c8b46a13ae45edf4a567554d579a440332475dd18f80'
  : '18c389007dcdd78638895b9b3d6a88c36783a342c8a1667ffe8a8c849a5a9830';
assert.equal(await sha256File(beforeBinary), beforeDigest, 'NativeAsciiBaselineChanged');
const afterBinary = join(root, '_build/native/release/build/cmd/native_retained_case_probe/native_retained_case_probe.exe');
const afterDigest = await sha256File(afterBinary);
assert.notEqual(afterDigest, beforeDigest, 'NativeAsciiChangeNotBuilt');
const git = async args => (await exec('git', args, {cwd: root})).stdout.trim();
const revision = await git(['rev-parse', 'HEAD']);
// These fixed experiments use archived builds, not a guessed current-HEAD
// build. A later documentation/controller revision cannot retag the binary.
const compiledSourceRevision = continuation ? '09b003893564cd01d4ff36ae4a6b2302839bd852'
  : 'fe0b68242d9e240494e85ecb0438f74f55855c88';
assert.equal(await git(['diff', '--name-only', compiledSourceRevision, revision, '--', 'src']), '',
  'NativePreparationCompiledSourceChanged');
assert.equal(afterDigest, continuation
  ? 'c60bcc58aa831f91167fe06246ae3c13e7e5e538e05d21a34ada84165a4c2543'
  : '2152155cc13ae8003df3c8b46a13ae45edf4a567554d579a440332475dd18f80',
  'NativePreparationCompiledBinaryChanged');
const sourceChanges = (await git(['diff', '--name-only', baselineRevision, revision, '--', 'src'])).split('\n').filter(Boolean);
assert.deepEqual(sourceChanges.sort(), continuation
  ? ['src/canonical_json/cursor_admission_wbtest.mbt', 'src/canonical_json/encode.mbt']
  : ['src/sha256/incremental_wbtest.mbt', 'src/sha256/sha256.mbt']);
const unchanged = async () => {
  assert.equal(await git(['rev-parse', 'HEAD']), revision);
  assert.equal(await git(['status', '--porcelain']), '', 'NativeComparisonRequiresCleanCheckout');
  assert.equal(await sha256File(beforeBinary), beforeDigest);
  assert.equal(await sha256File(afterBinary), afterDigest);
};
await unchanged();
const fixture = retainedText ? retainedCase(workloads[2], 'text-1024', 1000)
  : retainedCase(workloads[0], 'narrow', 100);
const directory = await mkdtemp(join(tmpdir(), 'actql-native-ascii-word-'));
const database = join(directory, 'source.duckdb');
const label = continuation ? 'canonical-continuation-rewrap' : 'native-ascii-word-loop';
const pairs = [];
const warmups = [];
const basis = {revision, compiledSourceRevision, baselineRevision, beforeDigest, afterDigest, sourceChanges,
  change: continuation ? 'Retain a container continuation without rewrapping it per child; exact advance schedule unchanged'
    : 'Four checked ASCII units per word without the inner loop',
  caseId: fixture.id, limits: fixture.limits,
  method: '21 predeclared alternating pairs; fresh Native processes; one immutable source; OS-cache coldness uncontrolled',
  firstUseCondition: matchedFirstUse
    ? 'One fully admitted unmeasured launch per binary before all 21 pairs. Its full cost and observations are retained separately. Both binary images have prior use; this does not establish OS-cache coldness or explain the original external delay.'
    : 'No explicit prelaunch; preserve all first-use observations',
  host: 'native', providedAcquisition: ['native'],
  computeConditions: retainedText
    ? 'Same explicit resident experiment on both binaries: fresh 1000 ms, resident default 1 ms; Local is ineligible under the unchanged cumulative text contract and receives no estimate. These are fixed control inputs, not calibrated costs.'
    : 'Same existing explicit resident experiment on both binaries: Local/fresh 1000 ms, resident default 1 ms. These are fixed control inputs, not new measured estimates or an invented planner reason.',
  fixtureScope: retainedText
    ? 'Existing retainedCase domain at 1000 text rows; outside the registered 27-case acceptance matrix. Diagnose retained/identity scaling without adding a matrix acceptance claim.'
    : 'Existing 100-row low-selectivity fixture',
  scopes: {cycle: 'application files, full binary hash, process exit and product/Owner admission; common source preparation reported separately',
    executionMs: 'probe entry through final result identity; includes preparation, not only task execution',
    applicationPreparationMs: 'actual application-start to library-start clock interval',
    computeAndIdentityMs: 'actual strategy-execute to execution-end clock interval',
    warmMs: 'sequential task intervals; not added to enclosing intervals',
    observer: 'existing physical phase observer on both legs; overhead retained in raw events'},
  originalEquivalentGate: 'Separate current-SHA calibrated release-pair acceptance; this controller does not issue that certificate'};
let sourceContentSha256, sourcePreparationMilliseconds;
const save = extra => writeFile(destination, JSON.stringify({...basis, sourceContentSha256,
  sourcePreparationMilliseconds, warmups, pairs, ...extra}, null, 2));
const executeLeg = async (leg, identity) => {
  await unchanged();
  const child = join(directory, leg + '-' + identity); await mkdir(child);
  const start = performance.now();
  const prepared = await prepareNativeDirectProduct({root, fixture, database, directory: child,
    residentPolicy: true, ...(retainedText ? {} : {localRates: ['1000', '1000', '1000']}),
    nativeRates: ['1000', '1000', '1000'],
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
  return {product, admissionMilliseconds: end - admissionStart,
    sample: {status: 'completed', processCycleMs: end - start,
      executionMs: product.executionMs, cleanupMs: product.cleanupMs,
      coldMs: end - start - product.cleanupMs, warmMs: product.warmMs,
      applicationPreparationMs: product.preparation.applicationMs,
      computeAndIdentityMs: product.preparation.computeAndIdentityMs}};
};
try {
  const sourceStart = performance.now();
  await exec(process.execPath, [join(root, 'adapters/connectors/duckdb/node/bench/create-retained-source.mjs'),
    database, fixture.workload, fixture.layout, String(fixture.rows)], {cwd: root, timeout: fixture.limits.timeoutMs});
  sourcePreparationMilliseconds = performance.now() - sourceStart;
  sourceContentSha256 = await sha256File(database);
  await save({status: 'measuring'});
  if (matchedFirstUse) {
    for (const leg of ['before', 'after']) {
      warmups.push({leg, observation: await executeLeg(leg, 'prelaunch')});
      await save({status: 'prelaunching'});
    }
  }
  for (let index = 0; index < 21; index++) {
    const legs = {};
    for (const leg of index % 2 ? ['after', 'before'] : ['before', 'after']) {
      legs[leg] = await executeLeg(leg, String(index));
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
