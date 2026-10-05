// Fixed diagnostic assembly over the same installed plan and managed worker.
// One copied before-Compute observation synchronizes the real cancellation;
// neither IPC nor the Program supplies executable code or completion evidence.
import {serveManagedStrategy} from '../../adapters/host-node/managed-strategy-worker.mjs';
import {prepareExampleText} from '../../adapters/connectors/duckdb/node/examples/physical-strategy.mjs';
import {bindProcessStore} from '../../adapters/store-local/process-binding.mjs';
import {installProcessCompletionObserver} from '../../adapters/host-node/process-completion-observer.mjs';
import {installCompletionObserver, completionObserver} from '../../adapters/host-common/completion-observer.mjs';

serveManagedStrategy(async (input, _signal, context) => {
  if (!context.resourceLimits || input.controlStore !== true) {
    throw new Error('CancellationDiagnosticRequiresExistingDelegationAndStore');
  }
  const plan = await prepareExampleText(input, context.resourceLimits);
  return {resourceLimits: plan.resourceLimits, usage: plan.usage,
    taskIdentities: () => JSON.parse(JSON.stringify(plan.taskIdentities())),
    async open(signal, context) {
      const binding = bindProcessStore(context);
      const completion = await installProcessCompletionObserver(binding,
        {maxCompletions: 4, maxInputs: 2, maxColumns: input.dataProfile.columns},
        plan.completionTask);
      const observer = installCompletionObserver(completionObserver(completion),
        async observation => {
          if (observation.task !== 2) return;
          // Reaching task 2 requires the real task-1 completion acknowledgement
          // to have returned. The parent cancels this ordinary execute request
          // here, before the standard driver starts task-2 Compute.
          await context.callHost(JSON.parse(JSON.stringify({
            command: 'benchmark-before-compute', observation,
            usage: plan.usage(),
          }, (_, value) => typeof value === 'bigint' ? value.toString() : value)));
        });
      const opened = await plan.open(signal, binding);
      return {...opened, observer};
    }};
}, {maxBytes: 1000000, maxNodes: 100000, maxDepth: 64});
