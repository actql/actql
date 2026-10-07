import assert from 'node:assert/strict';

const resourceKeys = [
  'heldBytes', 'reservedTransferBytes',
  'reservedRetentionBytes', 'reservedExecutionBytes',
];

function assertReclaimed(usage) {
  for (const key of resourceKeys) assert.equal(usage[key], 0n, key);
}

function assertHostFailure(action) {
  assert.throws(action, error => error?.code === 'MoonBitHostFailure');
}

// The pack harness supplies the single linked external runtime, its generated
// installer, and these unchanged common Host exports from the packed package.
// No private scheduler, output constructor, or settlement callback is supplied.
export async function verifyExternalComputeFixture({
  moon,
  installStrategyContributions,
  bindLocalJsHost,
  withScopedStrategy,
  runtimeCore,
  checked,
}) {
  const core = runtimeCore(moon);
  const host = bindLocalJsHost(moon, installStrategyContributions);
  const scenarios = new Set();
  const results = [];
  const prepare = () => {
    const scenario = checked(moon.prepareScenario());
    scenarios.add(scenario);
    const setup = moon.subsetHost(scenario);
    assert.deepEqual(moon.strategyHostModules(setup), ['external_numeric']);
    return {scenario, setup};
  };
  const entries = setup => {
    const installed = installStrategyContributions(moon, setup, checked, {});
    assert.equal(installed.length, 1);
    assert.equal(installed[0].registration,
      moon.strategyModule_external_numeric_Registration(setup));
    return installed;
  };
  const close = ({scenario, setup}) => {
    moon.closeScenario(scenario);
    scenarios.delete(scenario);
    assertReclaimed(core.usage(setup));
  };

  try {
    for (const scope of ['bound-host', 'explicit-scoped-strategy']) {
      const owned = prepare();
      let savedReport;
      let savedOutputs;
      const consume = report => {
        savedReport = report;
        assert.equal(report.status, 'host-tasks-completed');
        assert.equal(report.completed.length, 3);
        assert.deepEqual(report.completed.map(item => item.task), [1, 2, 3]);
        assert.deepEqual(report.completed.map(item => item.realization),
          ['external-numeric', 'external-numeric', 'external-numeric']);
        savedOutputs = [1, 2, 3].map(task => report.output(task));
        for (const output of savedOutputs) {
          assert.ok(output != null);
          assert.equal(moon.outputAvailable(output), true);
        }
        const output = savedOutputs[2];
        assert.equal(moon.outputRows(output), 1);
        const rows = [{id: moon.outputValue(output)}];
        assert.deepEqual(rows, [{id: 3}]);
        return rows;
      };
      const rows = scope === 'bound-host'
        ? await host.withCapturedStrategy(owned.setup, consume)
        : await withScopedStrategy(
          owned.setup, core, entries(owned.setup), consume,
        );
      assert.deepEqual(rows, [{id: 3}]);
      assert.throws(() => savedReport.output(3),
        error => error?.code === 'ReleasedStrategy');
      for (const output of savedOutputs) {
        assert.equal(moon.outputAvailable(output), false);
      }
      assert.equal(await savedReport.cleanup(), true);
      assert.equal(savedReport.cleanupPending(), false);
      assertReclaimed(savedReport.usage());
      close(owned);
      results.push({case: scope, computeTasks: 3, rows, reclaimed: true});
    }

    // A real task prepared by A must not enter B's exact typed channel. Refusal
    // must leave A's unconsumed task usable once and reject its later replay.
    {
      const a = prepare();
      const b = prepare();
      assert.notEqual(
        moon.strategyModule_external_numeric_Registration(a.setup),
        moon.strategyModule_external_numeric_Registration(b.setup),
      );
      const task = core.next(a.setup);
      assert.ok(task != null);
      assert.equal(core.task(task), 1);
      assertHostFailure(() => checked(
        moon.strategyModule_external_numeric_Dispatch(b.setup, task, () => true),
      ));
      assert.equal(core.completed(a.setup, 1), false);
      assert.equal(core.completed(b.setup, 1), false);
      checked(moon.strategyModule_external_numeric_Dispatch(
        a.setup, task, () => true,
      ));
      assert.equal(core.completed(a.setup, 1), true);
      assert.equal(core.completed(b.setup, 1), false);
      const output = core.output(a.setup, 1);
      assert.equal(moon.outputAvailable(output), true);
      const beforeReplay = core.usage(a.setup);
      assertHostFailure(() => checked(
        moon.strategyModule_external_numeric_Dispatch(a.setup, task, () => true),
      ));
      assert.deepEqual(core.usage(a.setup), beforeReplay);
      close(a);
      close(b);
      assert.equal(moon.outputAvailable(output), false);
      results.push({case: 'foreign-host-and-replay', refused: true,
        ownTaskSucceeded: true, reclaimed: true});
    }

    // A denied completion permit reaches the existing common completion owner.
    // Synchronous evaluation can settle, but it cannot publish a task output.
    {
      const owned = prepare();
      const task = core.next(owned.setup);
      assert.ok(task != null);
      let permitChecks = 0;
      assertHostFailure(() => checked(
        moon.strategyModule_external_numeric_Dispatch(owned.setup, task, () => {
          permitChecks++;
          return false;
        }),
      ));
      assert.equal(permitChecks, 1);
      assert.equal(core.completed(owned.setup, 1), false);
      assert.ok(core.output(owned.setup, 1) == null);
      const deniedUsage = core.usage(owned.setup);
      assert.equal(deniedUsage.reservedTransferBytes, 0n);
      assert.equal(deniedUsage.reservedRetentionBytes, 0n);
      assert.equal(deniedUsage.reservedExecutionBytes, 0n);
      close(owned);
      results.push({case: 'denied-completion', refused: true, reclaimed: true});
    }

    // Cancel while the common Host is awaiting beforeNext, before dispatch or
    // the result consumer can run. The contribution's real run is preserved.
    {
      const owned = prepare();
      const abort = new AbortController();
      let entered;
      let resume;
      const waiting = new Promise(resolve => { entered = resolve; });
      const release = new Promise(resolve => { resume = resolve; });
      let dispatched = 0;
      let consumed = 0;
      let finished = 0;
      const original = entries(owned.setup)[0];
      const pending = withScopedStrategy(owned.setup, core, [{
        ...original,
        async beforeNext() { entered(); await release; },
        async run(...args) { dispatched++; return original.run(...args); },
        async finish() { finished++; await original.finish?.(); },
      }], () => { consumed++; }, abort.signal);
      await Promise.race([waiting, pending.then(
        () => assert.fail('Host completed before beforeNext'),
        error => { throw error; },
      )]);
      abort.abort(new Error('cancel-before-dispatch'));
      resume();
      await assert.rejects(pending, error => {
        assert.equal(error instanceof AggregateError, true);
        assert.equal(error.cleanupHandle?.status().pending ?? false, false);
        return true;
      });
      assert.equal(dispatched, 0);
      assert.equal(consumed, 0);
      assert.equal(finished, 1);
      assert.equal(core.completed(owned.setup, 1), false);
      assert.ok(core.output(owned.setup, 1) == null);
      assertReclaimed(core.usage(owned.setup));
      close(owned);
      results.push({case: 'cancel-before-dispatch', dispatched, consumed,
        reclaimed: true});
    }

    return Object.freeze(results);
  } finally {
    for (const scenario of scenarios) moon.closeScenario(scenario);
  }
}
