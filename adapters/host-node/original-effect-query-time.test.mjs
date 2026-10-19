import assert from 'node:assert/strict';
import test from 'node:test';
import {openSourceFreeEffectComputation} from './local-values-plan.mjs';

// Actual Host computation selector with explicit Common ports. These counters
// do not issue physical compute capacity or establish a durable Journal commit.
test('Effect computation forwards the same invocation preparation and request', () => {
  const owner = {}, queryTimePreparation = {}, queryTime = {}, identity = {}, result = {};
  const facts = {owner, queryTimePreparation, queryTime, identity};
  let calls = 0;
  const moon = {
    clientProgramOpenSourceFreeLocalEffectHost() { assert.fail('No legacy fallback'); },
    clientProgramOpenSourceFreeLocalEffectHostAtQueryTime(...args) {
      assert.strictEqual(this, moon);
      assert.strictEqual(args[0], owner);
      assert.strictEqual(args[1], queryTimePreparation);
      assert.strictEqual(args[2], identity);
      assert.deepEqual(args.slice(3), ['registry', 'values', 1n, 0n, 0n, 0n, 'fragment', 'ordered']);
      calls++;
      return result;
    },
  };
  assert.strictEqual(openSourceFreeEffectComputation({moon, facts,
    registry: 'registry', values: 'values', fragment: 'fragment', ordered: 'ordered'}), result);
  assert.equal(calls, 1);
});

test('Effect computation refuses missing invocation originals without legacy fallback', () => {
  let calls = 0;
  const moon = {clientProgramOpenSourceFreeLocalEffectHost() { calls++; }};
  for (const facts of [
    {owner: {}, queryTimePreparation: {}},
    {owner: {}, queryTime: {}},
    {owner: {}, queryTimePreparation: {}, queryTime: {}, identity: {}},
  ]) {
    assert.throws(() => openSourceFreeEffectComputation({moon, facts}),
      /OriginalQueryTimeUnavailable/);
  }
  assert.equal(calls, 0);
});

test('Effect computation preserves the absent legacy call and refusal', () => {
  const owner = {};
  let calls = 0;
  const moon = {
    clientProgramOpenSourceFreeLocalEffectHost(...args) {
      assert.strictEqual(this, moon);
      assert.strictEqual(args[0], owner);
      assert.deepEqual(args.slice(1), ['registry', 'values', 1n, 0n, 0n, 0n, undefined, undefined]);
      calls++;
      return undefined;
    },
    clientProgramOpenSourceFreeLocalEffectHostAtQueryTime() { assert.fail('No new invocation'); },
  };
  assert.strictEqual(openSourceFreeEffectComputation({moon, facts: {owner},
    registry: 'registry', values: 'values'}), undefined);
  assert.equal(calls, 1);
});
