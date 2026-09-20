// Fixed application assembly. IPC never supplies an executable or module name.
// This example exercises the product checker and standard Host in the worker;
// it is not a separate fixture evaluator or an execution-proof constructor.
import {serveManagedStrategy} from '../../../../host-node/managed-strategy-worker.mjs';
import {prepareExampleText} from './physical-strategy.mjs';
import {bindProcessStore} from '../../../../store-local/process-binding.mjs';
import {installProcessCompletionObserver} from '../../../../host-node/process-completion-observer.mjs';

serveManagedStrategy(async (input, _signal, context) => {
  if (!context.resourceLimits) throw new Error('ManagedApplicationRequiresResourceDelegation');
  if (input.controlStore !== undefined && typeof input.controlStore !== 'boolean') throw new Error('InvalidControlStore');
  const controlStore = input.controlStore === true;
  if (controlStore && (!input.retainedOutput || input.localImportWorkMilliseconds === undefined)) {
    throw new Error('ControlStoreRequiresRetainedOutputAndLocalImportPolicy');
  }
  const plan = await prepareExampleText(input, context.resourceLimits);
  return {resourceLimits: plan.resourceLimits, usage: plan.usage, async open(signal, context) {
    const binding = controlStore ? bindProcessStore(context) : undefined;
    const observer = binding ? await installProcessCompletionObserver(binding,
      {maxCompletions: 4, maxInputs: 2, maxColumns: input.dataProfile?.columns ?? 10}, plan.completionTask) : undefined;
    let opened;
    try { opened = await plan.open(signal, binding); }
    catch (error) {
      if (error instanceof Error && !error.code) error.code = `ManagedExampleOpen:${error.name}`;
      throw error;
    }
    return {...opened, observer, describe: execution => JSON.parse(JSON.stringify(
      opened.describe(execution), (_, value) => typeof value === 'bigint' ? value.toString() : value))};
  }};
}, {maxBytes: 1000000, maxNodes: 100000, maxDepth: 64});
