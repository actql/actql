import {instantiate as instantiateFixture} from '../../_build/workers/modules/fixture.mjs';
import {numericProbeContribution} from '../reference-compute-node/async-probe.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {withScopedStrategy} from './invocation.mjs';
import {phaseAudit} from './phase-audit.mjs';

export async function runAsyncCase({mode = 'complete'} = {}) {
  const operations = instantiateFixture(7);
  const moon = Object.freeze(Object.fromEntries(Object.entries(operations)
    .filter(([name]) => name.startsWith('asyncStrategy'))
    .map(([name,value]) => ['strategy'+name.slice('asyncStrategy'.length),value])));
  const audit = phaseAudit();
  const scenario = audit.during('checking-lowering-installation', () => checked(operations.prepareAsyncScenario()));
  const setup = operations.asyncScenarioHost(scenario);
  const ordinary = runtimeCore(moon);
  const core = {...ordinary, next(value) {
    return audit.during('planning', () => {
      if (mode === 'planning-io') audit.perform('execute',false,() => {});
      const before = audit.calls.length;
      const task = ordinary.next(value);
      if (audit.calls.length !== before) throw new Error('PlanningPerformedIO');
      return task;
    });
  }};
  const abort = new AbortController();
  const samples = [];
  let waits = 0, stops = 0, published = false;
  const port = {
    async wait(phase) {
      audit.perform('execute',core.usage(setup).reservedExecutionBytes > 0n,() => {});
      waits++;
      samples.push({phase, usage:core.usage(setup), completed:moon.strategyHostTaskCompleted(setup,1)});
      await Promise.resolve();
      if (mode === 'cancel' && phase === 'reserved') abort.abort('cancel pending work');
      if (mode === 'cleanup-failure' && phase === 'reserved') throw new Error('injected transport failure');
      if (mode === 'cancel-computed' && phase === 'computed') abort.abort('cancel uncommitted result');
    },
    async stop() {
      audit.during('cleanup',() => audit.perform('cleanup',
        core.usage(setup).reservedExecutionBytes > 0n,() => {}));
      stops++;
      await Promise.resolve();
      if (mode === 'cleanup-failure' && stops === 1) throw new Error('stop not yet confirmed');
    },
  };
  const entry = numericProbeContribution(moon,operations,setup,checked,port);
  const entries = [{...entry,run: (task,signal) => audit.during('execution',() => entry.run(task,signal))}];
  let result;
  try {
    const outputs = await withScopedStrategy(setup,core,entries,report => {
      published = true;
      return [1,2,3].map(task => operations.workersOutputIdentity(report.output(task)));
    },abort.signal);
    result = {status:'completed',outputs};
  } catch (error) {
    const beforeRecovery = core.usage(setup);
    const pending = !!error.cleanupHandle?.status().pending;
    if (pending) await error.cleanupHandle.retry();
    result = {status:'failed', pending, beforeRecovery,
      recovered: !error.cleanupHandle?.status().pending};
  } finally { operations.closeAsyncScenario(scenario); }
  return {...result,published,waits,stops,samples,calls:audit.calls,violations:audit.violations,finalUsage:core.usage(setup)};
}
