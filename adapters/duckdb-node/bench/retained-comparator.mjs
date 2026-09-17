// Installed retained leg. Source creation and builds happen before this call.
// This alone is not a paired four-comparator experiment or a warm latency sample.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {managedCaseConfiguration} from '../../../benchmarks/retained-results/managed-configuration.mjs';
import {sampleControllerMemory} from '../../../benchmarks/retained-results/controller-memory.mjs';
import {createManagedExampleHost} from '../examples/managed-host.mjs';

const hash = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
const usage = value => Object.fromEntries(Object.entries(value).map(([key, v]) =>
  [key, typeof v === 'bigint' ? v.toString() : v]));

function warmTaskMilliseconds(task) {
  const resident = task.phases?.workMilliseconds;
  if (Number.isFinite(resident) && resident >= 0) return resident;
  const inputs = task.phases?.inputs;
  const query = task.phases?.queryAndReceiveMilliseconds;
  assert(Array.isArray(inputs) && inputs.every(input =>
    Number.isFinite(input.milliseconds) && input.milliseconds >= 0));
  assert(Number.isFinite(query) && query >= 0);
  return inputs.reduce((sum, input) => sum + input.milliseconds, 0) + query;
}

// Exported for failure-path tests; never creates a successful timing sample.
export async function closeRetainedSample(result, finalTask) {
  const started = performance.now();
  await result.close();
  assert.equal(result.cleanupHandle.status().pending, false);
  // Failed runs may not have published this task at all.
  const completion = result.completion(finalTask);
  if (completion) assert.equal(completion.retained, false);
  return performance.now() - started;
}

export async function runRetainedComparator(fixture, contracts, database, directory, options = {}) {
  assert(options && typeof options === 'object' && !Array.isArray(options), 'InvalidComparatorOptions');
  assert(Object.keys(options).every(key => ['resident', 'nativeMilliseconds'].includes(key)),
    'UnknownComparatorOption');
  // Snapshot selection inputs before any await. These are estimates, never
  // measurements or permission to override a reservation/capacity refusal.
  const selection = Object.freeze({resident: options.resident ?? false,
    nativeMilliseconds: options.nativeMilliseconds ?? '1'});
  assert.equal(typeof selection.resident, 'boolean', 'InvalidResidentSelection');
  assert(typeof selection.nativeMilliseconds === 'string' &&
    /^(0|[1-9][0-9]*)$/.test(selection.nativeMilliseconds) &&
    BigInt(selection.nativeMilliseconds) <= 2147483647n, 'InvalidNativeEstimate');
  const config = managedCaseConfiguration(fixture, contracts, database, directory);
  const input = Object.freeze({...config.input, ...selection});
  const expected = fixture.identity(); // Independent oracle, not timed product work.
  const memory = sampleControllerMemory();
  let result, memoryReport, elapsed, cleanupMs, report;
  try {
    const started = performance.now();
    const host = await createManagedExampleHost(config.limits);
    try {
      result = await host.run(input, {run: fixture.id, childLimits: config.childLimits},
        AbortSignal.timeout(config.timeoutMs));
      elapsed = performance.now() - started;
    } finally { memoryReport = memory.stop(); }
    assert.equal(memoryReport.status, 'observed');
    assert.equal(result.report.status, 'host-tasks-completed', JSON.stringify(result.report));
    assert.equal(result.process().exited, true);
    assert.equal(result.completion(config.finalTask)?.retained, true);
    const descriptor = result.completion(config.finalTask).descriptor;
    assert.equal(descriptor.rows_cid, expected.rowsCid);
    assert.equal(descriptor.rows, expected.rows);
    assert.equal(result.report.completed.length, config.finalTask);
    assert(result.report.completed.every(task => task.outputRepresentation === 'retained-file'));
    const descriptors = result.report.completed.map(({task}) => {
      const value = result.completion(task)?.descriptor;
      assert(value, 'MissingComparatorCompletionDescriptor');
      return value;
    });
    const warmMs = result.report.completed.reduce((sum, task) =>
      sum + warmTaskMilliseconds(task), 0);
    const semanticKeys = ['nativeSemanticRows', 'nativeSemanticCells',
      'nativeSemanticBytes', 'jsMaterializedCells'];
    const acquisition = result.report.acquisition_diagnostics;
    assert(acquisition && semanticKeys.every(key =>
      Number.isSafeInteger(acquisition[key]) && acquisition[key] >= 0));
    const compute = result.report.completed.map(task => task.phases);
    assert(compute.every(value => value && semanticKeys.every(key =>
      Number.isSafeInteger(value[key]) && value[key] >= 0)));
    const sum = key => acquisition[key] + compute.reduce((total, value) =>
      total + value[key], 0);
    const receiptBytes = result.report.acquisition_evidence.receipts.reduce(
      (total, receipt) => total + receipt.received_bytes,
      0,
    );
    const outputBytes = descriptors.reduce((total, value) =>
      total + value.bytes, 0);
    const inputs = result.report.completed.flatMap(task =>
      task.phases.inputs ?? []);
    const accounting = Object.freeze({
      nativeSemanticRows: sum('nativeSemanticRows'),
      nativeSemanticCells: sum('nativeSemanticCells'),
      nativeSemanticBytes: sum('nativeSemanticBytes'),
      jsMaterializedCells: sum('jsMaterializedCells'),
      identityPasses: 2 + descriptors.length,
      identityPreimageBytes: receiptBytes + outputBytes,
      retainedStoreBytes:
        result.report.acquisition_evidence.receipts[1].received_bytes +
        outputBytes,
      logicalCidPasses: inputs.reduce((total, value) =>
        total + (value.logicalCidPasses ?? 0), 0),
      physicalIntegrityPasses: inputs.reduce((total, value) =>
        total + (value.physicalIntegrityPasses ?? 0), 0),
      nativeFileReads: inputs.reduce((total, value) =>
        total + (value.nativeFileReads ?? 0), 0),
      domains: Object.freeze({
        nativeSemanticBytes:
          'JSON transport actually supplied to bounded semantic admission',
        retainedStoreBytes:
          'canonical row-array bytes written to retained holdings',
        identity:
          'canonical row-array preimages actually hashed',
      }),
    });
    report = {comparator: 'retained-actql', scope: 'managed-host-cycle-diagnostic',
      caseId: fixture.id, executionMs: elapsed, expectedRowsCid: expected.rowsCid,
      warmMs,
      selection, selectionHash: hash(JSON.stringify(selection)),
      rows: expected.rows, programHash: hash(config.input.programText),
      parameterHash: hash(config.input.parameterText), environmentCid: config.input.environmentCid,
      sourceDefinitionHash: hash(fixture.createSourceSql),
      acquisitionEvidence: result.report.acquisition_evidence,
      accounting,
      completionDescriptors: descriptors,
      controlMemory: memoryReport, controlTransport: result.process().transport,
      usage: usage(host.usage()), storage: result.storageUsage(), tasks: result.report.completed,
      explanation: result.report.explanation,
      includes: ['Host-preparation', 'child-start', 'acquisition', 'validation', 'Compute',
        'required-identities', 'independent-holding', 'child-exit'],
      excludes: ['build', 'source-setup', 'independent-oracle', 'fresh-reader'],
    };
  } finally {
    memory.stop();
    if (result) {
      cleanupMs = await closeRetainedSample(result, config.finalTask);
    }
  }
  return Object.freeze({...report, cleanupMs, status: 'completed'});
}
