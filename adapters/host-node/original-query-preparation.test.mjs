import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareOriginalSourceQuery} from './original-query-preparation.mjs';
import {openAcquiredEffectComputation} from './acquired-effect-computation.mjs';
const ok = value => ({$tag: 1, _0: value});

for (const effectful of [false, true]) {
  test(`Source preparation keeps the original ${effectful ? 'Effect' : 'pure'} query context`, () => {
    const owner = {}, original = {}, request = {}, acquisition = {}, requirement = {};
    const events = [];
    const contracts = Object.freeze({}); // Forwarding identity, not an issuance fixture.
    const prefix = effectful ? 'clientProgramEffect' : 'clientProgram';
    const moon = {
      [prefix + 'PrepareQueryAcquisitionAtQueryTime'](...args) {
        assert.strictEqual(this, moon);
        assert.strictEqual(args[0], owner);
        assert.deepEqual(args.slice(1, 3), [1, 0]);
        assert.strictEqual(args[3], original);
        assert.strictEqual(args[4], request);
        events.push('acquisition'); return ok(acquisition);
      },
      [prefix + 'PrepareLocalQueryRequirementAtQueryTime'](...args) {
        assert.strictEqual(this, moon);
        assert.strictEqual(args[0], owner);
        assert.strictEqual(args[3], original);
        assert.strictEqual(args[4], request);
        assert.strictEqual(args[5], contracts);
        assert.deepEqual(args.slice(6), ['v', 'f', 'o']);
        events.push('requirement'); return ok(requirement);
      },
    };
    const prepared = prepareOriginalSourceQuery({moon,
      ...(effectful ? {preparedEffect: owner} : {preparedProgram: owner}),
      stage: 1, input: 0, registry: contracts, values: 'v', fragment: 'f', ordered: 'o',
      queryTimePreparation: original, requestIdentity: request});
    assert.strictEqual(prepared.acquisition, acquisition);
    assert.strictEqual(prepared.requirement, requirement);
    assert.deepEqual(events, ['acquisition', 'requirement']);
  });
}

test('Source preparation forwards the installed original without a query-time owner', () => {
  const owner = {}, acquisition = {}, requirement = {}, events = [];
  const contracts = Object.freeze({}); // Only the forwarding seam is mocked.
  const moon = {
    clientProgramPrepareQueryAcquisition(...args) {
      assert.strictEqual(args[0], owner);
      assert.deepEqual(args.slice(1), [0, 0]); events.push('acquisition'); return ok(acquisition);
    },
    clientProgramPrepareLocalQueryRequirement(...args) {
      assert.strictEqual(args[3], contracts);
      assert.deepEqual(args, [owner, 0, 0, contracts, 'v', undefined, undefined]);
      events.push('requirement'); return ok(requirement);
    },
  };
  const value = prepareOriginalSourceQuery({moon, preparedProgram: owner,
    stage: 0, input: 0, registry: contracts, values: 'v'});
  assert.strictEqual(value.requirement, requirement);
  assert.deepEqual(events, ['acquisition', 'requirement']);
});

test('Source preparation never falls back after an unavailable or rejected original', () => {
  let legacy = 0, requirements = 0;
  const moon = {
    clientProgramEffectPrepareQueryAcquisition() { legacy++; },
    clientProgramEffectPrepareLocalQueryRequirement() { legacy++; },
  };
  const options = {moon, preparedEffect: {}, stage: 0, input: 0, queryTimePreparation: {}};
  assert.throws(() => prepareOriginalSourceQuery(options), /OriginalQueryTimeUnavailable/);
  assert.throws(() => prepareOriginalSourceQuery({...options, requestIdentity: {}}),
    /OriginalQueryTimeUnavailable/);
  const originalFailure = new Error('UnboundRequest');
  moon.clientProgramEffectPrepareQueryAcquisitionAtQueryTime = () => { throw originalFailure; };
  moon.clientProgramEffectPrepareLocalQueryRequirementAtQueryTime = () => { requirements++; };
  assert.throws(() => prepareOriginalSourceQuery({...options, requestIdentity: {}}),
    error => error === originalFailure);
  assert.equal(legacy, 0);
  assert.equal(requirements, 0);
});

for (const matches of [false, true]) {
  test(`Actual acquired Effect caller checks the same Run before Source preparation (${matches})`, async () => {
    const owner = {}, prepared = {}, queryTimePreparation = {}, requestIdentity = {};
    const stop = new Error('OriginalSourcePreparationReached');
    let custody, prepares = 0, opens = 0, checkedRun = 0;
    const moon = {
      clientProgramEffectAcquisitionCount: () => 1,
      clientProgramEffectRunQueryTimeMatches(...args) {
        assert.strictEqual(args[0], owner);
        assert.strictEqual(args[1], queryTimePreparation);
        assert.strictEqual(args[2], requestIdentity);
        checkedRun++; return matches;
      },
      clientProgramOpenLocalEffectHostAtQueryTime() { assert.fail('No captured source yet'); },
      clientProgramEffectPrepareQueryAcquisitionAtQueryTime: () => ok({}),
      clientProgramEffectPrepareLocalQueryRequirementAtQueryTime: () => ok({}),
      clientProgramQueryRequirementSourceRef: () => 'original-source',
    };
    await assert.rejects(openAcquiredEffectComputation({moon, owner,
      acquired: {prepared, queryTimePreparation, requestIdentity},
      retainComputationOwner(value) { custody = value; },
      sourceProfile: {
        admitsSource: ref => ref === 'original-source',
        prepare(options) {
          prepares++;
          assert.strictEqual(options.preparedEffect, prepared);
          assert.strictEqual(options.queryTimePreparation, queryTimePreparation);
          assert.strictEqual(options.requestIdentity, requestIdentity);
          assert.equal(custody.cleanupPending(), true);
          throw stop;
        },
        open() { opens++; },
      },
    }), error => matches ? error === stop : error.message === 'OriginalQueryTimeUnavailable');
    assert.equal(checkedRun, 1);
    assert.equal(prepares, matches ? 1 : 0);
    assert.equal(opens, 0);
    await custody.close();
    assert.equal(await custody.cleanup(), true);
  });
}
