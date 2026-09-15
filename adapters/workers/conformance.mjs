// Test-only preparation and observations. Product Host does not import fixtures.
import {instantiate} from '../../_build/workers/modules/fixture.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {bindWorkersHost} from './host.mjs';
import {runAsyncCase} from './async-conformance.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {withScopedStrategy} from './invocation.mjs';
import {installStrategyContributions} from '../connectors-workers/strategy.generated.mjs';

// Exercise actual Local admission with cancellation at Host await boundaries.
export async function cancellationCase(waiting = false) {
  const moon = instantiate(0);
  const scenario = checked(moon.prepareWorkersScenario(['{"id":3}'],false,100,'id > 2'));
  const setup = moon.workersScenarioHost(scenario), host = bindWorkersHost(moon);
  const abort = new AbortController();
  const before = host.usage(setup);
  let consumed = 0, prepared = 0, finished = 0, resume;
  const consume = () => { consumed++; };
  let pending;
  if (waiting) {
    const wait = new Promise(resolve => { resume = resolve; });
    const entries = installStrategyContributions(moon,setup,checked,{});
    const first = entries[0];
    pending = withScopedStrategy(setup,runtimeCore(moon),[
      {...first, beforeNext: async () => { prepared++; await wait; },
        finish: async () => { finished++; await first.finish?.(); }},
      {registration:{}, beforeNext: () => { prepared++; },
        run: () => { throw new Error('Unexpected dispatch'); }, finish: () => { finished++; }},
    ],consume,abort.signal);
  } else pending = host.withCapturedStrategy(setup,consume,abort.signal);
  abort.abort('cancel before dispatch');
  resume?.();
  let failed = false, cleanupPending = false;
  try { await pending; } catch (error) {
    failed = true;
    cleanupPending = !!error.cleanupHandle?.status().pending;
  } finally { moon.closeWorkersScenario(scenario); }
  return {before,after:host.usage(setup),consumed,prepared,finished,failed,cleanupPending};
}

export async function runCase({rows, nullable = false, maxRows = 100, cancel = false, hashSeed = 0, consumeFailure = false, computeFilter = 'id > 2'}) {
  const fixture = instantiate(hashSeed);
  const host = bindWorkersHost(fixture);
  const scenario = checked(fixture.prepareWorkersScenario(rows.map(row => JSON.stringify(row)), nullable, maxRows, computeFilter));
  const setup = fixture.workersScenarioHost(scenario);
  const abort = new AbortController();
  if (cancel) abort.abort(new Error('test cancellation'));
  let saved;
  try {
    const result = await host.withCapturedStrategy(setup, async report => {
      saved = report;
      await Promise.resolve();
      if (consumeFailure) return Promise.reject();
      const outputs = [1, 2, 3].map(task => {
        const output = report.output(task);
        if (!output) throw new Error('Missing checked output');
        return {task, rows:fixture.workersOutputRows(output), cid:fixture.workersOutputIdentity(output)};
      });
      return {outputs, usage:report.usage(), explanation:report.explain()};
    }, abort.signal);
    let released = false;
    try { saved.output(1); } catch (error) { released = error.code === 'ReleasedStrategy'; }
    return {status:'completed', ...result, released, finalUsage:host.usage(setup)};
  } catch (error) {
    let released = !saved;
    if (saved) {
      try { saved.output(1); } catch (failure) { released = failure.code === 'ReleasedStrategy'; }
    }
    const runtimeFailure = error.errors?.[0]?.cause;
    const diagnostic = runtimeFailure?.code === 'MoonBitHostFailure'
      ? fixture.workersFailureText(runtimeFailure.cause) : null;
    return {status:'failed', diagnostic, arithmetic:fixture.workersArithmeticFailure(scenario), cleanupPending:!!error.cleanupHandle?.status().pending,
      released, finalUsage:host.usage(setup)};
  } finally { fixture.closeWorkersScenario(scenario); }
}

export default {
  async fetch(request) {
    const input = await request.json();
    if (input.action === 'cancel-before-dispatch') {
      const value = await cancellationCase(input.waiting);
      return new Response(JSON.stringify(value,(_,item) => typeof item === 'bigint' ? String(item) : item));
    }
    if (input.action === 'invalid-program') {
      return Response.json(checked(instantiate(0).workersRejectInvalidProgram()));
    }
    if (input.action === 'foreign-dispatch') {
      return Response.json(checked(instantiate(0).workersForeignDispatch()));
    }
    // Promise.all interleaves two distinct owned Runs in the same isolate.
    const result = input.action === 'async-probe' ? await runAsyncCase(input)
      : Array.isArray(input) ? await Promise.all(input.map(item =>
        item.action === 'async-probe' ? runAsyncCase(item) : runCase(item))) : await runCase(input);
    // Test transport preserves exact Int64 ledger values; never round to Number.
    return new Response(JSON.stringify(result, (_, value) =>
      typeof value === 'bigint' ? value.toString() : value), {
      headers: {'content-type':'application/json'},
    });
  },
};
