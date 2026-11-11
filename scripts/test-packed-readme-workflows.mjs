// Required functional consumers of one exact normal artifact. No producer,
// repository runtime import, source overlay or performance campaign.
import assert from 'node:assert/strict';
import {mkdir, writeFile, copyFile, symlink, unlink, readlink, readFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {isAbsolute, join, resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutState} from './packed-client-packages.mjs';
import {prepareHealthPackages, mockWorkflowMetrics, execute} from './health-monitor-adapters.mjs';
import {verifyNodeBenchmarkPackages, nodeBenchmarkFailure} from './benchmark-node-operations.mjs';

export const packedReadmeCases = Object.freeze([
  Object.freeze({template: 'churn-risk-mock', variant: 'readme'}),
  Object.freeze({template: 'deal-review-mock', variant: 'readme'}),
  Object.freeze({template: 'deal-review-mock', variant: 'two-models'}),
]);
// The genuine mixed-Model/Whole fixture is a separate required regression,
// rather than a fourth README label or a manual-only performance selection.
export const packedCompositionCases = Object.freeze([
  Object.freeze({template: 'deal-review-mock', variant: 'two-models-whole'}),
]);

// The existing phase and its complete oracles, independently invocable for the
// SAME completed original Result. This helper installs nothing and submits no
// replacement Run. Its caller owns software/fixture correspondence and alias cleanup.
export async function runCollectionPhase({collection, command, record, capturePid}) {
  assert(['budget', 'capture', 'saved'].includes(record.phase));
  if (record.phase === 'saved') assert(Number.isSafeInteger(capturePid) && capturePid > 0);
  const members = ['scripts/fixtures/packed-result-collection.mjs'];
  const {phase} = record;
  const args = [join(collection, members[0]), phase, join(collection, 'original.json')];
  Object.assign(record, {command: process.execPath, args, cwd: collection,
    startedAt: new Date().toISOString(), status: 'running'});
  delete record.unexecutedReason;
  let observed;
  try {
    observed = await command(process.execPath, args,
      {cwd: collection, name: `collection-${phase}`, timeout: 120_000});
    const actual = JSON.parse(observed.stdout.trim()); record.actual = actual;
    assert.equal(actual.phase, phase); assert.equal(actual.pid, observed.pid);
    if (phase === 'saved') assert.notEqual(actual.pid, capturePid);
    assert.equal(actual.sourceFreeMaxWork, 30000000);
    const memory = phase === 'budget' ? 32768 : 1073741824;
    assert.deepEqual(actual.requestMemory, {retainedBytes: memory, executionBytes: memory});
    assert(actual.complete); assert.equal(actual.firstClose, 'returned');
    assert.deepEqual(actual.aliveScopedFD, {before: 0, after: 0});
    assert.equal(actual.submits, phase === 'capture' ? 5 : phase === 'budget' ? 1 : 0);
    if (phase === 'budget') {
      assert.equal(actual.budgetRefusal?.verified, true);
      assert.equal(actual.budgetDisposition, 'pre_send_capture');
      assert.equal(actual.budgetInputPublished, false);
      assert.equal(actual.budgetPublicOutcome, undefined); assert.equal(actual.budgetPublicAttempt, undefined);
      assert.equal(actual.budgetRefusal.phase, 'request_snapshot');
      assert.equal(actual.budgetRefusal.outcome, 'pre_send_capture');
      assert.equal(actual.budgetRefusal.classification, 'resource_limit');
      assert.equal(actual.budgetRefusal.dimension, 'retention');
      const amounts = ['requiredRetentionBytes', 'requiredExecutionBytes',
        'availableRetentionBytes', 'availableExecutionBytes'].map(name => {
        const text = actual.budgetRefusal[name];
        assert(typeof text === 'string' && /^(?:0|[1-9][0-9]{0,18})$/u.test(text));
        const amount = BigInt(text); assert(amount <= 9223372036854775807n); return amount;
      });
      assert(amounts[0] > amounts[2] && amounts[2] <= BigInt(memory) && amounts[3] <= BigInt(memory));
      assert.deepEqual(actual.budgetInput, {utf8Bytes: 40017, utf16Units: 40017,
        arrayElements: 20000, original: 'budget-input-before-submit.json'});
      assert.deepEqual(actual.cases, [{inputUtf8Bytes: 40017, expectedRefusal: 'request_snapshot', complete: true}]);
    } else if (phase === 'capture') {
      assert.deepEqual(actual.cases.map(value => value.count), [9999, 10000, 10001, 100000]);
      assert.deepEqual(actual.fullStream, {rows: 100000, complete: true});
      assert.deepEqual(actual.controls, {tighterRows: true, collectionBytes: true,
        wireBytes: true, rowWireBytes: true, rowBytes: true, originalChargeBeforeValidation: true,
        boundedBatches: true, batchBytes: true, earlyBreak: true, readerCancellation: true});
      assert.deepEqual(actual.oversizedRow, {rows: 1, arrayElements: 20000,
        expectedRefusal: 'ResultRowRetainedLimit', complete: true});
      assert.equal(actual.originalProgramsRemovedAfterFirstClose, 5);
    } else assert.deepEqual(actual.cases, [{count: 100000, complete: true}]);
    record.completed = true; record.status = 'passed';
  } catch (error) {
    observed ??= error?.commandResult;
    record.status = 'failed'; record.error = nodeBenchmarkFailure(error);
    // A timed-out close may never produce stdout or a final observation. Only
    // consume this actual child/phase's pre-close receipt; do not infer ACK.
    try {
      const partial = JSON.parse(await readFile(join(collection, `${phase}.pending.json`), 'utf8'));
      assert.equal(partial.phase, phase);
      assert(Number.isSafeInteger(observed?.pid) && observed.pid > 0);
      assert.equal(partial.pid, observed.pid);
      record.partialObservation = partial;
    } catch (diagnosticError) {
      record.partialObservationUnavailable = nodeBenchmarkFailure(diagnosticError);
    }
    throw error;
  } finally {
    Object.assign(record, {pid: observed?.pid ?? null, wallNs: observed?.wallNs ?? null,
      exitCode: observed?.code ?? null, signal: observed?.signal ?? null,
      endedAt: new Date().toISOString()});
  }
}

// Fixture handoff/cleanup evidence only; the actual Saved read keeps all public
// current, authentication and byte validation in the installed owners.
export async function completedCollectionCapture(collection, capturePid) {
  try {
    const captured = JSON.parse(await readFile(join(collection, 'capture.observation.json'), 'utf8'));
    const original = JSON.parse(await readFile(join(collection, 'original.json'), 'utf8'));
    assert.equal(captured.pid, capturePid); assert.equal(captured.phase, 'capture');
    assert.equal(captured.firstClose, 'returned'); assert.deepEqual(captured.aliveScopedFD, {before: 0, after: 0});
    assert.deepEqual(captured.cleanup, []);
    const result = captured.cases.find(value => value.count === 100000 && value.complete === true);
    assert(result); assert.equal(original.count, 100000);
    assert.deepEqual(original.ref, result.ref); assert.equal(original.resultName, result.resultName);
    return true;
  } catch {return false;}
}

async function runCollectionConsumer({prepared, root, repository, command, report, cleanup}) {
  const collection = join(root, 'collection'); await mkdir(collection);
  const members = ['scripts/fixtures/packed-result-collection.mjs',
    'scripts/fixtures/record-approval/scoped-fds.fixture.mjs'];
  for (const path of members) {
    await mkdir(dirname(join(collection, path)), {recursive: true});
    await copyFile(join(repository, path), join(collection, path));
  }
  await writeFile(join(collection, 'package.json'), '{"private":true,"type":"module"}\n');
  const software = join(prepared.consumer, 'node_modules'), alias = join(collection, 'node_modules');
  await symlink(software, alias, 'dir');
  try {
    const failures = [];
    let capturePid;
    for (const record of report.collection) {
      if (record.phase === 'saved' && !await completedCollectionCapture(collection, capturePid)) {
        record.unexecutedReason = 'Requires completed original 100000 Result, matching handoff and FIRST close';
        continue;
      }
      try {await runCollectionPhase({collection, command, record, capturePid});}
      catch (error) {failures.push(error);}
      if (record.phase === 'capture') capturePid = record.pid;
    }
    if (failures.length === 1) throw failures[0];
    if (failures.length) throw new AggregateError(failures, 'CollectionPhasesFailed', {cause: failures[0]});
  } finally {
    try {assert.equal(await readlink(alias), software); await unlink(alias);}
    catch (error) {cleanup.push(error);}
  }
}

async function runReadmeCases({prepared, root, repository, command, report, failures, cases = report.cases}) {
  for (const record of cases) {
    // A shared software failure invalidates the remaining inputs. A failed
    // consumer does not mask the other fresh, independent project variants.
    await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
    const {template, variant} = record;
    record.status = 'running'; delete record.unexecutedReason;
    try {
      await mockWorkflowMetrics({prepared, root, repository, command,
        counts: {coldSamples: 1}, template, variant,
        async onMetric(metric) {
          record.metric = metric;
          await writeFile(join(root, `${template}-${variant}.json`), JSON.stringify(metric, null, 2) + '\n');
        }});
      assert.equal(record.metric.samples.length, 1);
      assert(record.metric.samples[0].completed && record.metric.samples[0].verified);
      record.completed = true; record.status = 'passed';
    } catch (error) {
      failures.push(error); record.status = 'failed'; record.error = nodeBenchmarkFailure(error);
    }
  }
}

export async function runPackedReadmeWorkflows(root) {
  assert(isAbsolute(root), 'Require a fresh absolute consumer output directory');
  const retained = process.env.ACTQL_PACKED_CLIENT_PACKAGES;
  assert(typeof retained === 'string' && isAbsolute(retained),
    'Require the same-run normal Client artifact; no packing fallback');
  assert(!process.env.NODE_PATH && !process.env.NODE_OPTIONS &&
    !process.env.ACTQL_LOCAL_SOURCE_PROFILE && !process.env.ACTQL_LOCAL_EFFECT_PROFILE,
  'Packed README consumers refuse ambient runtime overlays');
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const before = checkoutState(repository);
  assert(before.clean, 'Require clean fixed Source');
  if (process.env.GITHUB_SHA) assert.equal(before.revision, process.env.GITHUB_SHA);
  const source = {sha: before.revision, dirty: false,
    tree: execFileSync('git', ['rev-parse', 'HEAD^{tree}'], {cwd: repository, encoding: 'utf8'}).trim()};
  await mkdir(root);
  const raw = join(root, 'raw'); await mkdir(raw);
  const report = {source, node: process.version, platform: process.platform,
    architecture: process.arch, requiredCases: packedReadmeCases, requiredCompositions: packedCompositionCases,
    collection: ['budget', 'capture', 'saved'].map(phase => ({phase, completed: false, status: 'unexecuted',
      unexecutedReason: phase === 'saved' ? 'Requires completed original 100000 Result, matching handoff and FIRST close' : 'Requires verified normal packages'})),
    cases: packedReadmeCases.map(selected => ({...selected, completed: false, status: 'unexecuted',
      unexecutedReason: 'Requires verified unchanged normal packages'})),
    compositions: packedCompositionCases.map(selected => ({...selected, completed: false, status: 'unexecuted',
      unexecutedReason: 'Requires verified unchanged normal packages and matching composition fixture'})),
    complete: false, performanceAcceptance: false,
    qualification: 'Same normal artifact, fresh state per variant; functional once each, not a latency verdict'};
  const command = (cmd, args, options) => execute(cmd, args, {...options, raw});
  let prepared;
  const failures = [], cleanup = [];
  try {
    prepared = await prepareHealthPackages({repository, root, source, retained, command, normalLifecycle: true});
    report.manifest = prepared.manifest;
    try {
      await runCollectionConsumer({prepared, root, repository, command, report, cleanup});
    } catch (error) {failures.push(error);}
    await runReadmeCases({prepared, root, repository, command, report, failures});
    await runReadmeCases({prepared, root, repository, command, report, failures, cases: report.compositions});
    report.complete = failures.length === 0 && report.collection.every(row => row.completed) &&
      report.cases.every(row => row.completed) && report.compositions.every(row => row.completed);
  } catch (error) {failures.push(error);}
  finally {
    if (prepared) try {
      await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
    } catch (error) {cleanup.push(error);}
    try {assert.deepEqual(checkoutState(repository), before);} catch (error) {cleanup.push(error);}
    report.failures = failures.map(nodeBenchmarkFailure);
    if (failures.length) report.failure = report.failures[0];
    report.cleanup = cleanup.map(nodeBenchmarkFailure);
    if (cleanup.length) report.complete = false;
    await writeFile(join(root, 'summary.json'), JSON.stringify(report, null, 2) + '\n');
  }
  if (failures.length && (failures.length > 1 || cleanup.length)) throw new AggregateError([...failures, ...cleanup],
    'PackedReadmeConsumersFailed', {cause: failures[0]});
  if (failures.length) throw failures[0];
  if (cleanup.length) throw new AggregateError(cleanup, 'PackedReadmeCleanupUnconfirmed');
  assert(report.complete, 'Unexecuted or incomplete required consumers cannot establish normal acceptance');
  return report;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 3, 'usage: test-packed-readme-workflows.mjs ABSOLUTE_FRESH_OUTPUT');
  await runPackedReadmeWorkflows(process.argv[2]);
}
