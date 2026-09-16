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
    assert.equal(result.report.status, 'host-tasks-completed');
    assert.equal(result.process().exited, true);
    assert.equal(result.completion(config.finalTask)?.retained, true);
    const descriptor = result.completion(config.finalTask).descriptor;
    assert.equal(descriptor.rows_cid, expected.rowsCid);
    assert.equal(descriptor.rows, expected.rows);
    assert.equal(result.report.completed.length, config.finalTask);
    assert(result.report.completed.every(task => task.outputRepresentation === 'retained-file'));
    report = {comparator: 'retained-actql', scope: 'managed-host-cycle-diagnostic',
      caseId: fixture.id, executionMs: elapsed, expectedRowsCid: expected.rowsCid,
      selection, selectionHash: hash(JSON.stringify(selection)),
      rows: expected.rows, programHash: hash(config.input.programText),
      parameterHash: hash(config.input.parameterText), environmentCid: config.input.environmentCid,
      sourceDefinitionHash: hash(fixture.createSourceSql),
      controlMemory: memoryReport, controlTransport: result.process().transport,
      usage: usage(host.usage()), storage: result.storageUsage(), tasks: result.report.completed,
      includes: ['Host-preparation', 'child-start', 'acquisition', 'validation', 'Compute',
        'required-identities', 'independent-holding', 'child-exit'],
      excludes: ['build', 'source-setup', 'independent-oracle', 'fresh-reader'],
    };
  } finally {
    memory.stop();
    if (result) {
      const cleanupStarted = performance.now();
      await result.close();
      assert.equal(result.cleanupHandle.status().pending, false);
      assert.equal(result.completion(config.finalTask).retained, false);
      cleanupMs = performance.now() - cleanupStarted;
    }
  }
  return Object.freeze({...report, cleanupMs, status: 'completed'});
}
