import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareOriginalSourceQuery} from './original-query-preparation.mjs';
import {openAcquiredEffectComputation} from './acquired-effect-computation.mjs';
type AcquiredCall = Parameters<typeof openAcquiredEffectComputation>[0];
type Runtime = Parameters<typeof prepareOriginalSourceQuery>[0]['moon'];
type QueryOptions = Parameters<typeof prepareOriginalSourceQuery>[0];
type ComputationCustody = Parameters<AcquiredCall['retainComputationOwner']>[0];
const ok = (value: unknown) => ({$tag: 1, _0: value});

for (const effectful of [false, true]) {
  test(`Source preparation keeps the original ${effectful ? 'Effect' : 'pure'} query context`, () => {
    const owner = {}, original = {}, request = {}, acquisition = {}, requirement = {};
    const events: string[] = [];
    const contracts = Object.freeze({}); // Forwarding identity, not an issuance fixture.
    const prefix = effectful ? 'clientProgramEffect' : 'clientProgram';
    const moon: Runtime = {
      [prefix + 'PrepareQueryAcquisitionAtQueryTime'](...args: unknown[]) {
        assert.strictEqual(this, moon);
        assert.strictEqual(args[0], owner);
        assert.deepEqual(args.slice(1, 3), [1, 0]);
        assert.strictEqual(args[3], original);
        assert.strictEqual(args[4], request);
        events.push('acquisition'); return ok(acquisition);
      },
      [prefix + 'PrepareLocalQueryRequirementAtQueryTime'](...args: unknown[]) {
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
  const owner = {}, acquisition = {}, requirement = {}, events: string[] = [];
  const contracts = Object.freeze({}); // Only the forwarding seam is mocked.
  const moon = {
    clientProgramPrepareQueryAcquisition(...args: unknown[]) {
      assert.strictEqual(args[0], owner);
      assert.deepEqual(args.slice(1), [0, 0]); events.push('acquisition'); return ok(acquisition);
    },
    clientProgramPrepareLocalQueryRequirement(...args: unknown[]) {
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
  const moon: {-readonly [Key in keyof Runtime]: Runtime[Key]} = {
    clientProgramEffectPrepareQueryAcquisition() { legacy++; },
    clientProgramEffectPrepareLocalQueryRequirement() { legacy++; },
  };
  const options = {moon, preparedEffect: {}, stage: 0, input: 0, queryTimePreparation: {}} as QueryOptions;
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
    const managedRun = {}, plan = {}, selection = {}, requirement = {};
    const stop = new Error('OriginalSourcePreparationReached');
    let custody: ComputationCustody | undefined, prepares = 0, opens = 0, checkedRun = 0;
    const moon = {
      clientProgramEffectAcquisitionCount: (actual: unknown) => {assert.strictEqual(actual, prepared); return 1;},
      clientProgramInstalledEffectManagedOperationPlan(parent: unknown, actual: unknown, request: unknown) {
        assert.strictEqual(this, moon); assert.strictEqual(parent, managedRun);
        assert.strictEqual(actual, prepared); assert.strictEqual(request, requestIdentity); return ok(plan);
      },
      clientProgramInstalledEffectManagedHostOpen() {assert.fail('Source must reach its original prepare boundary first');},
      clientProgramInstalledEffectManagedPlanSourceCoordinates(actual: unknown, program: unknown, request: unknown) {
        assert.strictEqual(actual, plan); assert.strictEqual(program, prepared);
        assert.strictEqual(request, requestIdentity); return ok([[0, 0, 0, 0]]);
      },
      clientProgramSelectInstalledEffectSourceInput(program: unknown, request: unknown, stage: number, input: number) {
        assert.strictEqual(program, prepared); assert.strictEqual(request, requestIdentity);
        assert.equal(stage, 0); assert.equal(input, 0); return ok(selection);
      },
      clientProgramSelectedSourceInputKind(actual: unknown) {assert.strictEqual(actual, selection); return 'query';},
      clientProgramSelectedSourceInputRef(actual: unknown) {assert.strictEqual(actual, selection); return 'original-source';},
      clientProgramInstalledEffectManagedPlanSource(actual: unknown, task: number) {
        assert.strictEqual(actual, plan); assert.equal(task, 0); return ok({_0: {}, _1: requirement});
      },
      clientProgramEffectRunQueryTimeMatches(...args: unknown[]) {
        assert.strictEqual(args[0], owner);
        assert.strictEqual(args[1], queryTimePreparation);
        assert.strictEqual(args[2], requestIdentity);
        checkedRun++; return matches;
      },
      clientProgramOpenLocalEffectHostAtQueryTime() { assert.fail('No captured source yet'); },
      clientProgramEffectPrepareQueryAcquisitionAtQueryTime: () => ok({}),
      clientProgramEffectPrepareLocalQueryRequirementAtQueryTime: () => ok({}),
      clientProgramQueryRequirementSourceRef: (actual: unknown) => {assert.strictEqual(actual, requirement); return 'original-source';},
    };
    await assert.rejects(openAcquiredEffectComputation({moon, owner, managedRun,
      acquired: {prepared, queryTimePreparation, requestIdentity},
      retainComputationOwner(value: ComputationCustody) { custody = value; },
      sourceProfile: {
        admitsSource: (ref: string) => ref === 'original-source',
        prepare(options: Readonly<Record<string, unknown>>) {
          prepares++;
          assert.strictEqual(options.preparedEffect, prepared);
          assert.strictEqual(options.queryTimePreparation, queryTimePreparation);
          assert.strictEqual(options.requestIdentity, requestIdentity);
          assert.equal(custody!.cleanupPending(), true);
          throw stop;
        },
        open() { opens++; },
      },
    } as unknown as AcquiredCall), error => matches ? error === stop : (error as Error).message === 'OriginalQueryTimeUnavailable');
    assert.equal(checkedRun, 1);
    assert.equal(prepares, matches ? 1 : 0);
    assert.equal(opens, 0);
    await custody!.close();
    assert.equal(await custody!.cleanup(), true);
  });
}
