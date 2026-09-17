import {performance} from 'node:perf_hooks';
import {prepareExampleText} from '../examples/physical-strategy.mjs';
import {runCapturedStrategy} from '../../host-node/entry.mjs';
import {managedCaseConfiguration} from
  '../../../benchmarks/retained-results/managed-configuration.mjs';
import {sampleControllerMemory} from
  '../../../benchmarks/retained-results/controller-memory.mjs';

// New-profile diagnostic. It uses the same checked Program, source and limits
// as the registered old-contract case, but selects managed completion through
// explicit Host policy. It does not manufacture a portable Result artifact.
export function managedProfileInput(configured) {
  const {
    retainedOutput,
    localImportWorkMilliseconds: _localImportWorkMilliseconds,
    localExportWorkMilliseconds: _localExportWorkMilliseconds,
    ...common
  } = configured.input;
  return Object.freeze({
    ...common,
    // Acquisition retains the existing CID-bearing observation contract. The
    // separate managed profile applies only to Compute in this experiment.
    acquisitionRetainedOutput: retainedOutput,
    managedOutput: retainedOutput,
  });
}

// Execute one registered case through the managed Compute profile while its
// Acquisition observation remains on the existing CID-bearing contract.
export async function runManagedProfileCase(
  fixture,
  contracts,
  database,
  directory,
) {
  const configured = managedCaseConfiguration(
    fixture,
    contracts,
    database,
    directory,
  );
  const input = managedProfileInput(configured);
  const started = performance.now();
  const memory = sampleControllerMemory();
  let plan;
  let opened;
  let execution;
  let failure;
  let report;
  try {
    plan = await prepareExampleText(input, configured.limits);
    opened = await plan.open(AbortSignal.timeout(configured.timeoutMs));
    execution = await runCapturedStrategy(
      opened.setup,
      opened.configurations,
      AbortSignal.timeout(configured.timeoutMs),
    );
    if (execution.status !== 'host-tasks-completed') {
      failure = execution.failure ?? new Error('ManagedProfileCaseFailed');
      failure.managedProfileDiagnostic = Object.freeze({
        completed: execution.completed,
        explanation: execution.explain(),
      });
      throw failure;
    }
    report = {
      caseId: fixture.id,
      status: 'completed',
      milliseconds: performance.now() - started,
      tasks: execution.completed,
      usageBeforeClose: execution.usage(),
    };
  } catch (error) {
    failure = error;
  } finally {
    const controllerMemory = memory.stop();
    const cleanupErrors = [];
    try { await execution?.close(); }
    catch (error) { cleanupErrors.push(error); }
    try {
      if (execution?.cleanupPending()) await execution.cleanup();
    } catch (error) { cleanupErrors.push(error); }
    try { await opened?.close(); }
    catch (error) { cleanupErrors.push(error); }
    if (cleanupErrors.length && failure) {
      failure.cleanupErrors = Object.freeze(cleanupErrors);
    } else if (cleanupErrors.length) {
      failure = new AggregateError(
        cleanupErrors,
        'ManagedProfileCaseCleanupFailed',
      );
    }
    if (report) report.controllerMemory = controllerMemory;
  }
  if (failure) throw failure;
  const usageAfterClose = plan.usage();
  for (const field of [
    'reserved_transfer_bytes',
    'held_bytes',
    'reserved_retention_bytes',
    'reserved_execution_bytes',
  ]) {
    if (usageAfterClose[field] !== 0n) {
      throw Object.assign(new Error('ManagedProfileCleanupAccounting'), {
        field,
        usageAfterClose,
      });
    }
  }
  if (report.controllerMemory.status !== 'observed' ||
      report.tasks.length !== configured.finalTask) {
    throw Object.assign(new Error('ManagedProfileIncompleteEvidence'), {
      controllerMemory: report.controllerMemory,
      completedTasks: report.tasks.length,
      expectedTasks: configured.finalTask,
    });
  }
  return Object.freeze({...report, usageAfterClose});
}
