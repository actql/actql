import assert from 'node:assert/strict';
import test from 'node:test';
import {acquisitionFailure} from '../host-common/acquisition-outcome.mjs';
import {openAcquiredEffectComputation} from './acquired-effect-computation.mjs';

for (const outcome of ['not_started', 'stopped', 'unknown']) {
  test(`acquired Effect opening keeps the adapter's ${outcome} observation`,
    async () => {
      let retained;
      let reads = 0;
      let prepares = 0;
      const failure = new Error('ReadUnavailable');
      const prepared = {};
      const preparedSource = {};
      await assert.rejects(openAcquiredEffectComputation({
        acquired: {prepared}, now: () => '2026-09-29T00:00:00.000Z',
        retainComputationOwner(owner) { retained = owner; },
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

test('source evidence failure retains capture cleanup until release succeeds',
  async () => {
    let retained;
    let reads = 0;
    let closes = 0;
    const primary = new Error('SourceEvidenceUnavailable');
    const cleanupFailure = new Error('SourceReleaseUnavailable');
    await assert.rejects(openAcquiredEffectComputation({
      acquired: {prepared: {}, authorityScopeCid: 'scope'},
      now: () => '2026-09-29T00:00:00.000Z',
      retainComputationOwner(owner) { retained = owner; },
      sourceProfile: {prepare() { return {}; }, open() {
        reads++;
        return {
          checkedSource: {sourceDataPolicyCid: 'policy'},
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
  });
