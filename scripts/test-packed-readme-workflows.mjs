// Required functional consumers of one exact normal artifact. No producer,
// repository runtime import, source overlay or performance campaign.
import assert from 'node:assert/strict';
import {mkdir, writeFile, copyFile, symlink, unlink, readlink, readFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {isAbsolute, join, resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutState} from './packed-client-packages.mjs';
import {prepareHealthPackages, mockWorkflowMetrics, execute} from './health-monitor-adapters.mjs';
import {packedEffectControlCases, runMockEffectControls} from './packed-mock-effect-controls.mjs';
import {verifyNodeBenchmarkPackages, nodeBenchmarkFailure} from './benchmark-node-operations.mjs';

export const packedReadmeCases = Object.freeze([
  Object.freeze({template: 'churn-risk-mock', variant: 'readme'}),
  Object.freeze({template: 'deal-review-mock', variant: 'readme'}),
  Object.freeze({template: 'deal-review-mock', variant: 'two-models'}),
]);
// Genuine completed Unit/Model compositions are separate required regressions,
// not extra README labels or manual-only performance selections.
export const packedCompositionCases = Object.freeze([
  Object.freeze({template: 'deal-review-mock', variant: 'two-models-whole'}),
  Object.freeze({template: 'deal-review-mock', variant: 'two-models-joined-inputs'}),
  Object.freeze({template: 'deal-review-mock', variant: 'two-models-joined-whole'}),
]);

// The existing phase and its complete oracles, independently invocable for the
// SAME completed original Result. This helper installs nothing and submits no
// replacement Run. Its caller owns software/fixture correspondence and alias cleanup.
export async function runCollectionPhase({collection, command, record, capturePid}) {
  assert(['budget', 'memory-recovery', 'work-recovery', 'accepted-memory-recovery', 'capture', 'saved'].includes(record.phase));
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
    assert.equal(actual.sourceFreeMaxWork, phase === 'work-recovery' ? 100000 : 30000000);
    const memory = phase === 'budget' ? 32768 : phase === 'memory-recovery' ? 268435456
      : phase === 'accepted-memory-recovery' ? 536870912 : 1073741824;
    assert.deepEqual(actual.requestMemory, {retainedBytes: memory, executionBytes: memory});
    assert(actual.complete); assert.equal(actual.firstClose, 'returned');
    assert.deepEqual(actual.aliveScopedFD, {before: 0, after: 0});
    assert.equal(actual.submits, phase === 'capture' ? 5 : phase === 'budget' ? 1 : phase.endsWith('-recovery') ? 3 : 0);
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
    } else if (phase.endsWith('-recovery')) {
      assert.deepEqual(actual.resourceRecovery, {complete: true, rows: [{n: 7}], submits: 1});
      assert.equal(actual.previousSavedCreated, true);
      assert.deepEqual(actual.previousSaved, {complete: true, rows: [{n: 41}], submits: 0});
      assert.equal(actual.cleanup?.length, 0);
      if (phase === 'memory-recovery') {
        assert.equal(actual.memoryRefusal?.verified, true);
        assert.equal(actual.memoryRefusal.phase, 'request_snapshot');
        assert.equal(actual.memoryRefusal.classification, 'resource_limit');
        assert.equal(actual.memoryRefusal.outcome, 'pre_send_capture');
        const amounts = ['requiredRetentionBytes', 'requiredExecutionBytes',
          'availableRetentionBytes', 'availableExecutionBytes'].map(key => {
          const text = actual.memoryRefusal[key];
          assert(typeof text === 'string' && /^(?:0|[1-9][0-9]{0,18})$/u.test(text));
          const value = BigInt(text); assert(value <= 9223372036854775807n); return value;
        });
        assert(amounts[2] <= BigInt(memory) && amounts[3] <= BigInt(memory));
        assert(actual.memoryRefusal.dimension === 'retention' ? amounts[0] > amounts[2]
          : actual.memoryRefusal.dimension === 'execution' && amounts[0] <= amounts[2] && amounts[1] > amounts[3]);
        assert.deepEqual(actual.cases, [{expectedRefusal: 'request_snapshot', complete: true}]);
      } else if (phase === 'accepted-memory-recovery') {
        assert.equal(actual.firstCloseCalls, 1);
        assert.equal(actual.originalRefRecordedBeforeWait, true);
        assert(actual.acceptedComputeRef !== null && typeof actual.acceptedComputeRef === 'object');
        assert.equal(actual.acceptedComputeTerminal?.physical_stop, 'confirmed');
        assert.deepEqual(actual.capacityObservations, []);
        if (actual.acceptedComputeTerminal.status === 'succeeded') {
          assert.equal(actual.acceptedComputeTerminal.result_available, true);
          assert.deepEqual(actual.workObservations, []);
          assert.equal(actual.acceptedMemoryRefusal, undefined);
          assert.deepEqual(actual.cases, [{count: 100000, disposition: 'succeeded', rows: 100000, complete: true}]);
        } else {
          assert.equal(actual.acceptedComputeTerminal.status, 'failed');
          assert.equal(actual.acceptedComputeTerminal.result_available, false);
          const data = actual.acceptedMemoryRefusal;
          assert.equal(data?.verified, true);
          assert.deepEqual(Object.keys(data).sort(), ['budget', 'code', 'dimension', 'kind', 'phase', 'publicBudget', 'task', 'verified']);
          assert.equal(data.code, 'MoonBitHostFailure');
          assert.equal(data.phase, 'local_managed_advance');
          assert.equal(data.kind, 'resource');
          assert(Number.isSafeInteger(data.task) && data.task >= 0 && data.task <= 2147483647);
          assert(['retained_bytes', 'execution_bytes'].includes(data.dimension));
          assert.equal(actual.workObservations.length, 1);
          const original = actual.workObservations[0];
          assert.deepEqual(original.ref, actual.acceptedComputeRef);
          assert.equal(original.code, 'CapturedRunExecutionFailed');
          assert.equal(original.primaryCode, 'MoonBitHostFailure');
          const {verified, publicBudget, ...diagnostic} = data;
          assert.deepEqual(original.primaryDiagnostic, diagnostic);
          assert.deepEqual(actual.cases, [{count: 100000, disposition: 'resource_refused', complete: true}]);
        }
      } else {
        const data = actual.workRefusal;
        assert.equal(data.verified, true); assert.equal(data.code, 'MoonBitHostFailure');
        assert.equal(data.phase, 'local_managed_advance');
        assert(Number.isSafeInteger(data.task) && data.task >= 0 && data.task <= 2147483647);
        if (data.kind === 'control_work') {
          assert.deepEqual(Object.keys(data).sort(), ['code', 'controlWorkLimit', 'kind', 'phase', 'publicBudget', 'task', 'verified']);
          assert.equal(data.controlWorkLimit, actual.sourceFreeMaxWork);
        } else {
          assert.equal(data.kind, 'value_capture_work');
          assert.deepEqual(Object.keys(data).sort(), ['budget', 'code', 'kind', 'phase', 'publicBudget', 'step', 'task', 'verified', 'workLimit']);
          assert(Number.isSafeInteger(data.step) && data.step >= 0 && data.step <= 2147483647);
          assert.equal(data.workLimit, actual.sourceFreeMaxWork);
        }
        assert.deepEqual(actual.cases, [{expectedRefusal: data.kind, complete: true}]);
      }
      if (phase === 'work-recovery' || phase === 'accepted-memory-recovery' && actual.acceptedComputeTerminal.status === 'failed') {
        const original = phase === 'work-recovery' ? actual.workRefusal : actual.acceptedMemoryRefusal;
        const publicBudget = original.publicBudget;
        assert.equal(publicBudget?.phase, 'local_managed_advance');
        assert.equal(publicBudget.dimension, original.kind === 'resource' ? original.dimension : original.kind);
        const setting = original.kind === 'resource'
          ? `installation.requestMemory.${original.dimension === 'retained_bytes' ? 'retainedBytes' : 'executionBytes'}`
          : 'installation.sourceFreeMaxWork';
        assert.equal(publicBudget.setting, setting);
        assert.equal(publicBudget.policy, String(original.kind === 'resource' ? memory : actual.sourceFreeMaxWork));
        assert.equal(typeof publicBudget.message, 'string');
        assert(publicBudget.message.includes(`phase=local_managed_advance; dimension=${publicBudget.dimension};`));
        assert(publicBudget.message.includes(`setting=${setting}.`));
        assert.deepEqual(publicBudget.quantities, original.budget ?? 'unavailable');
        assert.deepEqual(actual.publicBudgetReread, {sameHost: true, originalFailedRun: true,
          sameMessage: true, sameRevision: true, newSubmissions: 0});
      }
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
    // A killed child may never enter finally and write its pending receipt.
    // Retain only its own bounded last progress, separately from final outcome
    // and close evidence. Neither a completed span nor progress grants a pass.
    try {
      const text = await readFile(join(collection, `${phase}.progress.json`), 'utf8');
      assert(text.length <= 131072);
      const progress = JSON.parse(text);
      assert.equal(progress.phase, phase);
      assert(Number.isSafeInteger(observed?.pid) && observed.pid > 0);
      assert.equal(progress.pid, observed.pid);
      assert(['start', 'end', 'complete'].includes(progress.event));
      assert(Number.isSafeInteger(progress.elapsedNs) && progress.elapsedNs >= 0);
      assert(typeof progress.complete === 'boolean');
      assert(Array.isArray(progress.phases) && progress.phases.length <= 64);
      record.progressObservation = progress;
    } catch (diagnosticError) {
      record.progressObservationUnavailable = nodeBenchmarkFailure(diagnosticError);
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

function assertProjectFileJoinOutcome(actual, phase) {
  assert.equal(actual.case, 'project-local-files-same-unit-join');
  assert.equal(actual.phase, phase); assert.equal(actual.complete, true);
  assert.deepEqual(actual.rows, [{left_path: 'left.txt', left_bytes: 3,
    right_path: 'right.txt', right_bytes: 7}]);
  assert.equal(actual.submits, phase === 'capture' ? 1 : 0);
  assert.equal(actual.firstClose, 'returned'); assert.equal(actual.firstCloseCalls, 1);
  assert.deepEqual(actual.aliveScopedFD, {before: 0, after: 0});
  assert.deepEqual(actual.cleanup, []); assert.equal(actual.originalFilesAbsent, true);
  assert(actual.ref && typeof actual.resultName === 'string' && actual.resultName.length);
}

async function runProjectFileJoinConsumer({prepared, root, repository, command, report, cleanup}) {
  const collection = join(root, 'collection'); await mkdir(collection, {recursive: true});
  const application = join(collection, 'project-files'); await mkdir(application);
  for (const path of ['scripts/fixtures/packed-project-file-join.mjs',
    'scripts/fixtures/record-approval/scoped-fds.fixture.mjs']) {
    await mkdir(dirname(join(application, path)), {recursive: true});
    await copyFile(join(repository, path), join(application, path));
  }
  await writeFile(join(application, 'package.json'), '{"private":true,"type":"module"}\n');
  const home = join(application, 'home'); await mkdir(home);
  const env = {...process.env, HOME: home, PATH: [dirname(process.execPath), '/usr/bin', '/bin'].join(':')};
  delete env.ACTQL_PACKED_CLIENT_PACKAGES;
  const software = join(prepared.consumer, 'node_modules'), alias = join(application, 'node_modules');
  const handoff = join(collection, 'project-files-original.json');
  await symlink(software, alias, 'dir');
  try {
    await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
    let captured;
    for (const record of report.projectFiles) {
      if (record.phase === 'saved' && captured === undefined) continue;
      record.status = 'running'; delete record.unexecutedReason;
      let observed;
      try {
        if (record.phase === 'saved') {
          const original = JSON.parse(await readFile(handoff, 'utf8'));
          assert.equal(original.complete, true); assert.deepEqual(original.ref, captured.ref);
          assert.equal(original.resultName, captured.resultName);
        }
        observed = await command(process.execPath, [join(application,
          'scripts/fixtures/packed-project-file-join.mjs'), record.phase, handoff],
        {cwd: application, env, name: `project-files-${record.phase}`, timeout: 30_000});
        assert.equal(observed.code, 0); assert.equal(observed.signal ?? null, null);
        const actual = JSON.parse(observed.stdout.trim().split('\n').at(-1));
        assertProjectFileJoinOutcome(actual, record.phase); assert.equal(actual.pid, observed.pid);
        if (record.phase === 'capture') captured = actual;
        else {
          assert.notEqual(actual.pid, captured.pid);
          assert.deepEqual(actual.ref, captured.ref); assert.equal(actual.resultName, captured.resultName);
        }
        record.observation = actual; record.completed = true; record.status = 'passed';
      } catch (error) {
        observed ??= error?.commandResult;
        record.status = 'failed'; record.error = nodeBenchmarkFailure(error);
        throw error;
      } finally {
        Object.assign(record, {pid: observed?.pid ?? null, exitCode: observed?.code ?? null,
          signal: observed?.signal ?? null, endedAt: new Date().toISOString()});
      }
    }
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
    collection: ['budget', 'memory-recovery', 'work-recovery', 'accepted-memory-recovery', 'capture', 'saved'].map(phase => ({phase, completed: false, status: 'unexecuted',
      unexecutedReason: phase === 'saved' ? 'Requires completed original 100000 Result, matching handoff and FIRST close' : 'Requires verified normal packages'})),
    projectFiles: ['capture', 'saved'].map(phase => ({phase, completed: false, status: 'unexecuted',
      unexecutedReason: phase === 'saved' ? 'Requires original two-file JOIN and FIRST close' : 'Requires verified normal packages'})),
    cases: packedReadmeCases.map(selected => ({...selected, completed: false, status: 'unexecuted',
      unexecutedReason: 'Requires verified unchanged normal packages'})),
    controls: packedEffectControlCases.map(mode => ({mode, completed: false, status: 'unexecuted',
      unexecutedReason: 'Requires verified unchanged normal packages and a fresh original capture'})),
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
    try {
      await runProjectFileJoinConsumer({prepared, root, repository, command, report, cleanup});
    } catch (error) {failures.push(error);}
    await runReadmeCases({prepared, root, repository, command, report, failures});
    await runReadmeCases({prepared, root, repository, command, report, failures, cases: report.compositions});
    await runMockEffectControls({prepared, root, repository, command, records: report.controls, failures});
    report.complete = failures.length === 0 && report.collection.every(row => row.completed) &&
      report.projectFiles.every(row => row.completed) &&
      report.cases.every(row => row.completed) && report.compositions.every(row => row.completed) && report.controls.every(row => row.completed);
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
