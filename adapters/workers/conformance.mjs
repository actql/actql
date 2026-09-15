// Test-only preparation and observations. Product Host does not import fixtures.
import {instantiate} from '../../_build/workers/modules/fixture.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {bindWorkersHost} from './host.mjs';
import {runAsyncCase} from './async-conformance.mjs';

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
