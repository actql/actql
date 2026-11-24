// Fixed application assembly. IPC never supplies an executable or module name.
// This example exercises the product checker and standard Host in the worker;
// it is not a separate fixture evaluator or an execution-proof constructor.
import {serveManagedStrategy} from '../../../../host-node/managed-strategy-worker.mjs';
import {enableNodeCompileCache} from '../../../../host-node/compile-cache.mjs';
import {prepareExampleText} from './physical-strategy.mjs';
import {bindProcessStore} from '../../../../store-local/process-binding.mjs';
import {installProcessCompletionObserver} from '../../../../host-node/process-completion-observer.mjs';
import {installCompletionObserver, completionObserver} from '../../../../host-common/completion-observer.mjs';

import type {taskStartObserver} from '../../../../host-common/completion-observer.mjs';
import type {ProcessFrameValue} from '../../../../host-node/process-frames.mjs';

type ExampleInput = Extract<ProcessFrameValue, Record<string, ProcessFrameValue>> & {
  dataProfile?: {columns?: number};
};
enableNodeCompileCache();

serveManagedStrategy(async (input: ExampleInput, _signal, context) => {
  if (!context.resourceLimits) throw new Error('ManagedApplicationRequiresResourceDelegation');
  if (input.controlStore !== undefined && typeof input.controlStore !== 'boolean') throw new Error('InvalidControlStore');
  if (input.observePlanner !== undefined && typeof input.observePlanner !== 'boolean') throw new Error('InvalidPlannerObservation');
  if (input.observePlanner === true && input.controlStore !== true) throw new Error('PlannerObservationRequiresCompletionCustody');
  const controlStore = input.controlStore === true;
  if (controlStore && (!input.retainedOutput || input.localImportWorkMilliseconds === undefined)) {
    throw new Error('ControlStoreRequiresRetainedOutputAndLocalImportPolicy');
  }
  const plan = await prepareExampleText(input as ExampleInput & Parameters<typeof prepareExampleText>[0], context.resourceLimits);
  return {resourceLimits: plan.resourceLimits, usage: plan.usage,
    taskIdentities: () => JSON.parse(JSON.stringify(plan.taskIdentities())), async open(signal, context) {
    const binding = controlStore ? bindProcessStore(context) : undefined;
    const completion = binding ? await installProcessCompletionObserver(binding,
      {maxCompletions: 4, maxInputs: 2, maxColumns: input.dataProfile?.columns ?? 10}, plan.completionTask) : undefined;
    const plannerObservations: unknown[] = [];
    // Quantities/explanations only: do not retain output or task handles in
    // benchmark diagnostics. Existing completion custody still owns handoff.
    const observer = completion && input.observePlanner === true ? installCompletionObserver(async (value: Parameters<NonNullable<ReturnType<typeof completionObserver>>>[0]) => {
      await completionObserver(completion)?.(value);
      plannerObservations.push({boundary: 'after-task', task: value.task,
        elapsedMilliseconds: performance.now(), usage: plan.usage()});
    }, (value: Parameters<NonNullable<ReturnType<typeof taskStartObserver>>>[0]) => {
      plannerObservations.push({boundary: 'before-task',
        elapsedMilliseconds: performance.now(), ...value,
        driverUsage: value.usage, usage: plan.usage()});
    }) : completion;
    let opened;
    try { opened = await plan.open(signal, binding); }
    catch (error) {
      if (error instanceof Error && !(error as NodeJS.ErrnoException).code)
        (error as NodeJS.ErrnoException).code = `ManagedExampleOpen:${error.name}`;
      throw error;
    }
    return {...opened, observer, describe: execution => JSON.parse(JSON.stringify(
      {...opened.describe(execution), ...(input.observePlanner === true ? {
        planner_observations: plannerObservations} : {})},
      (_, value) => typeof value === 'bigint' ? value.toString() : value))};
  }};
}, {maxBytes: 1000000, maxNodes: 100000, maxDepth: 64});
