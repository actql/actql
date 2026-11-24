import assert from 'node:assert/strict';
import test from 'node:test';
import {openSourceFreeEffectComputation} from './local-source-free-effect-publication.mjs';

const ok = <Value,>(value: Value) => ({$tag: 1, _0: value});

// The explicit Common ports observe the exact Run, Prepared, Request and Host
// originals passed by the real selector.
test('Effect computation checks the same managed Run, preparation and Request', () => {
  const managedRun = {}, prepared = {}, identity = {}, owner = {}, result = {};
  const facts = {prepared, identity, owner};
  const calls: string[] = [];
  const moon = {
    clientProgramOpenSourceFreeLocalEffectHost() { assert.fail('No legacy fallback'); },
    clientProgramOpenSourceFreeLocalEffectHostAtQueryTime() { assert.fail('No second invocation'); },
    clientProgramInstalledEffectManagedRunCheck(run: unknown, program: unknown, request: unknown) {
      assert.strictEqual(this, moon);
      assert.strictEqual(run, managedRun);
      assert.strictEqual(program, prepared);
      assert.strictEqual(request, identity);
      calls.push('check');
      return ok(undefined);
    },
    clientProgramInstalledEffectManagedHostOpen(run: unknown, original: unknown, sources: readonly unknown[]) {
      assert.strictEqual(this, moon);
      assert.strictEqual(run, managedRun);
      assert.strictEqual(original, owner);
      assert.deepEqual(sources, []);
      calls.push('open');
      return ok(result);
    },
  };
  assert.strictEqual(openSourceFreeEffectComputation({moon, facts, managedRun}), result);
  assert.deepEqual(calls, ['check', 'open']);
});

test('Effect computation refuses a missing managed Run or either installed original port before opening', () => {
  const managedRun = {}, facts = {prepared: {}, identity: {}, owner: {}};
  const moon = {
    clientProgramOpenSourceFreeLocalEffectHost() { assert.fail('No legacy fallback'); },
    clientProgramOpenSourceFreeLocalEffectHostAtQueryTime() { assert.fail('No second invocation'); },
    clientProgramInstalledEffectManagedRunCheck() { assert.fail('Incomplete installation cannot check a Run'); },
    clientProgramInstalledEffectManagedHostOpen() { assert.fail('Incomplete installation cannot open a Host'); },
  };
  for (const options of [
    {moon, facts},
    {moon: {...moon, clientProgramInstalledEffectManagedRunCheck: undefined}, facts, managedRun},
    {moon: {...moon, clientProgramInstalledEffectManagedHostOpen: undefined}, facts, managedRun},
  ]) {
    assert.throws(() => openSourceFreeEffectComputation(options), /InstalledEffectPlanUnavailable/);
  }
});

test('Effect computation preserves the first Common refusal and the original empty Host return', () => {
  const managedRun = {}, facts = {prepared: {}, identity: {}, owner: {}};
  const refusal = new Error('original invocation refusal');
  const calls: string[] = [];
  let refuse = true;
  const moon = {
    clientProgramInstalledEffectManagedRunCheck(run: unknown, program: unknown, identity: unknown) {
      assert.strictEqual(run, managedRun);
      assert.strictEqual(program, facts.prepared);
      assert.strictEqual(identity, facts.identity);
      calls.push('check');
      return refuse ? {$tag: 0, _0: refusal} : ok(undefined);
    },
    clientProgramInstalledEffectManagedHostOpen(run: unknown, owner: unknown, sources: readonly unknown[]) {
      assert.strictEqual(run, managedRun);
      assert.strictEqual(owner, facts.owner);
      assert.deepEqual(sources, []);
      calls.push('open');
      return ok(undefined);
    },
  };
  assert.throws(() => openSourceFreeEffectComputation({moon, facts, managedRun}),
    error => error instanceof Error && error.cause === refusal);
  assert.deepEqual(calls, ['check']);
  refuse = false;
  assert.equal(openSourceFreeEffectComputation({moon, facts, managedRun}), undefined);
  assert.deepEqual(calls, ['check', 'check', 'open']);
});
