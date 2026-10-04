import assert from 'node:assert/strict';
import test from 'node:test';
import {acquisitionEndHandoff, acquisitionFailure} from
  '../host-common/acquisition-outcome.mjs';
import {openAcquiredEffectComputation} from './acquired-effect-computation.mjs';

test('acquisition end handoff rejects an unissued or conflicting statement',
  () => {
    const handoff = acquisitionEndHandoff();
    assert.throws(() => handoff.retain(new Error('Unissued')),
      {message: 'InvalidAcquisitionEndHandoff'});
    assert.equal(handoff.outcome(new Error('Wrapped')).outcome, 'unknown');
    const first = acquisitionFailure(new Error('ReadLost'), 'stopped');
    assert.equal(handoff.retain(first), first);
    assert.equal(handoff.retain(first), first);
    assert.throws(() => handoff.retain(acquisitionFailure(
      new Error('OtherRead'), 'not_started')),
    {message: 'InvalidAcquisitionEndHandoff'});
    assert.equal(handoff.outcome(new Error('Wrapped')).outcome, 'stopped');
  });

for (const outcome of ['not_started', 'stopped', 'unknown']) {
  test(`acquired Effect opening keeps the adapter's ${outcome} observation`,
    async () => {
      let retained;
      let reads = 0;
      let prepares = 0;
      const failure = new Error('ReadUnavailable');
      const prepared = {};
      const selection = {status: 'selected', selectedCandidate: 'nativeQuery'};
      const preparedSource = {selection};
      const observations = [];
      await assert.rejects(openAcquiredEffectComputation({
        acquired: {prepared}, now: () => '2026-09-29T00:00:00.000Z',
        retainComputationOwner(owner) { retained = owner; },
        observe(name, detail) { observations.push({name, detail}); },
        sourceProfile: {
          async prepare({preparedEffect, preparedProgram}) {
            prepares++;
            assert.equal(retained.cleanupPending(), true);
            assert.equal(preparedEffect, prepared);
            assert.equal(preparedProgram, undefined);
            return preparedSource;
          },
          async open(options) {
            reads++;
            assert.equal(options.preparedSource, preparedSource);
            throw acquisitionFailure(failure, outcome);
          },
        },
      }), error => error.cause === failure);
      await retained.close();
      assert.equal(await retained.cleanup(), outcome !== 'unknown');
      assert.equal(retained.cleanupPending(), outcome === 'unknown');
      assert.equal(prepares, 1);
      assert.equal(reads, 1);
      assert.deepEqual(observations, [{name: 'acquisition_started', detail: {task: 0, selection}}],
        'a failed physical acquisition must not emit a completed selection');
    });
}

test('acquired Effect cleanup retries the recovery owner without another read',
  async () => {
    let retained;
    let reads = 0;
    let cleanups = 0;
    let pending = true;
    const failure = new Error('TransportStopUnconfirmed');
    const recovery = {
      async close() { throw new Error('FirstCloseFailed'); },
      async cleanup() {
        cleanups++;
        if (cleanups === 1) return false;
        pending = false;
        return true;
      },
      cleanupPending: () => pending,
    };
    await assert.rejects(openAcquiredEffectComputation({
      acquired: {prepared: {}}, now: () => '2026-09-29T00:00:00.000Z',
      retainComputationOwner(owner) { retained = owner; },
      sourceProfile: {prepare() { return {}; }, open() {
        reads++;
        throw acquisitionFailure(failure, 'unknown', recovery);
      }},
    }), error => error.cause === failure);
    await assert.rejects(retained.close(), {message: 'FirstCloseFailed'});
    assert.equal(await retained.cleanup(), false);
    assert.equal(retained.cleanupPending(), true);
    assert.equal(await retained.cleanup(), true);
    assert.equal(retained.cleanupPending(), false);
    assert.equal(reads, 1);
  });

test('acquired Effect retains a reported recovery owner across error wrapping',
  async () => {
    let retained;
    let reads = 0;
    let pending = true;
    let closes = 0;
    const recovery = {async close() { closes++; },
      async cleanup() { return !pending; },
      cleanupPending: () => pending};
    await assert.rejects(openAcquiredEffectComputation({
      acquired: {prepared: {}}, now: () => '2026-09-29T00:00:00.000Z',
      retainComputationOwner(owner) { retained = owner; },
      sourceProfile: {prepare() { return {}; },
        open({reportAcquisitionFailure}) {
          reads++;
          const failure = acquisitionFailure(new Error('ReadLost'),
            'unknown', recovery);
          reportAcquisitionFailure(failure);
          throw new Error('AdapterBoundaryFailed', {cause: failure});
        }},
    }), {message: 'AdapterBoundaryFailed'});
    await retained.close();
    assert.equal(await retained.cleanup(), false);
    assert.equal(retained.cleanupPending(), true);
    pending = false;
    assert.equal(await retained.cleanup(), true);
    assert.equal(retained.cleanupPending(), false);
    assert.equal(reads, 1);
    assert.equal(closes, 1);
  });

test('acquired Effect preparation failure is not an unobserved acquisition',
  async () => {
    let retained;
    let reads = 0;
    await assert.rejects(openAcquiredEffectComputation({acquired: {prepared: {}},
      retainComputationOwner(owner) { retained = owner; },
      sourceProfile: {prepare() { throw new Error('ForeignCheckedSource'); },
        open() { reads++; }},
    }), {message: 'ForeignCheckedSource'});
    await retained.close();
    assert.equal(await retained.cleanup(), true);
    assert.equal(retained.cleanupPending(), false);
    assert.equal(reads, 0);
  });

test('a stale Source admission is not an unknown provider acquisition', async () => {
  let retained;
  let reads = 0;
  let closes = 0;
  await assert.rejects(openAcquiredEffectComputation({
    acquired: {prepared: {}}, now: () => '2026-09-29T00:00:00.000Z',
    retainComputationOwner(owner) { retained = owner; },
    sourceProfile: {prepare: () => ({}), open() { reads++; }},
    sourceContinuation: {
      accessFor: access => access, prepared() {}, times: () => ({}),
      beforeRead: () => ({enter() { throw new Error('StaleResumeClaim'); }}),
      close() { closes++; },
    },
  }), {message: 'StaleResumeClaim'});
  await retained.close();
  assert.equal(await retained.cleanup(), true);
  assert.equal(retained.cleanupPending(), false);
  assert.equal(reads, 0);
  assert.equal(closes, 1);
});

test('source evidence failure retains capture cleanup until release succeeds',
  async () => {
    let retained;
    let reads = 0;
    let closes = 0;
    const selection = {status: 'selected', selectedCandidate: 'broadQuery'};
    const observations = [];
    const primary = new Error('SourceEvidenceUnavailable');
    const cleanupFailure = new Error('SourceReleaseUnavailable');
    await assert.rejects(openAcquiredEffectComputation({
      acquired: {prepared: {}, authorityScopeCid: 'scope'},
      now: () => '2026-09-29T00:00:00.000Z',
      retainComputationOwner(owner) { retained = owner; },
      observe(name, detail) { observations.push({name, detail}); },
      sourceProfile: {prepare() { return {selection}; }, open() {
        reads++;
        return {
          checkedSource: {sourceDataPolicyCid: 'policy'},
          acquisition: {selection},
          issueSourceEvidence() { throw primary; },
          close() {
            closes++;
            if (closes === 1) throw cleanupFailure;
          },
        };
      }},
    }), error => error === primary);
    await retained.close();
    await assert.rejects(retained.cleanup(), error => error === cleanupFailure);
    assert.equal(retained.cleanupPending(), true);
    assert.equal(await retained.cleanup(), true);
    assert.equal(retained.cleanupPending(), false);
    await retained.close();
    assert.equal(await retained.cleanup(), true);
    assert.equal(reads, 1);
    assert.equal(closes, 2);
    assert.deepEqual(observations, [
      {name: 'acquisition_started', detail: {task: 0, selection}},
      {name: 'acquisition_completed', detail: {task: 0, acquisition: {selection}}},
    ], 'cleanup retries do not emit another physical acquisition');
  });

test('plural Effect preparation retains custody before either read can start', async () => {
  const prepared = {};
  const failure = new Error('SecondSourcePreparationUnavailable');
  let custody;
  let reads = 0;
  const preparedTasks = [];
  const sources = [0, 1].map(task => {
    const access = {name: `source-${task}`};
    return {
      realizationKey: 'duckdb-acquired', sourceAccess: access,
      admitsSource: ref => ref === `source-${task}`,
      async prepare(options) {
        assert.equal(custody.cleanupPending(), true);
        assert.equal(options.preparedEffect, prepared);
        assert.equal(options.sourceAccess, access);
        assert.deepEqual(options.occurrence, {stage: task, input: 0, task});
        preparedTasks.push(task);
        if (task === 1) throw failure;
        return {};
      },
      async open() { reads++; throw new Error('UnexpectedRead'); },
    };
  });
  await assert.rejects(openAcquiredEffectComputation({
    moon: {
      clientProgramEffectAcquisitionCount: () => 2,
      clientProgramEffectPrepareLocalQueryRequirement: (_, task) => ({$tag: 1, _0: task}),
      clientProgramQueryRequirementSourceRef: task => `source-${task}`,
    },
    owner: {}, acquired: {prepared}, sourceProfile: {sources},
    retainComputationOwner(value) { custody = value; },
  }), error => error === failure);
  assert.deepEqual(preparedTasks, [0, 1]);
  assert.equal(reads, 0);
  assert.equal(await custody.cleanup(), false);
  await custody.close();
  assert.equal(await custody.cleanup(), true);
  assert.equal(custody.cleanupPending(), false);
});
