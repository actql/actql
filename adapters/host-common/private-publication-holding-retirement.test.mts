// Exercise the actual private holding owner. Store preparation/confirmation
// are explicit boundary doubles; these tests do not issue Core admission or
// prove physical collection of an escaped prepared handle.
import assert from 'node:assert/strict';
import test from 'node:test';
import {preparePrivatePublicationHolding} from './private-publication-holding.mjs';

type HoldingOwner = ReturnType<typeof preparePrivatePublicationHolding>;
type HoldingRecord = Awaited<ReturnType<HoldingOwner['commit']>>;
type FixtureOptions = Readonly<{releaseFailure?: unknown; beforeCommitFailure?: unknown; raw?: boolean}>;

const cid = (digit: string) => `sha256:${digit.repeat(64)}`;
const binding = Object.freeze({name: 'effect_preview', semanticCid: cid('a'),
  holdingCid: cid('b'), wire: '{"original":null}'});

type HoldingArgs = Parameters<typeof preparePrivatePublicationHolding>;
type HoldingStore = HoldingArgs[0];
type WireBinding = typeof binding;
type RawFields = Omit<WireBinding, 'name'> &
  Readonly<{contentCid: string; byteCount: number}>;
type RawBinding<Name extends string> = RawFields & Readonly<{name: Name}>;
type Accept<Value extends HoldingArgs> = Value;
type IsNotAssignable<Value, Target> = Value extends Target ? false : true;
type Assert<Value extends true> = Value;
type ModelRawPortBinding = Parameters<NonNullable<HoldingStore['prepareModelRawEvidence']>>[0];
type LookupRawPortBinding = Parameters<NonNullable<HoldingStore['confirmLookupRawEvidence']>>[0];
type RawHoldingCases = [
  Accept<[HoldingStore, WireBinding]>,
  Accept<[HoldingStore, RawBinding<'model_raw_response'>, Uint8Array]>,
  Accept<[HoldingStore, RawBinding<'lookup_raw_response'>, Uint8Array]>,
  Assert<IsNotAssignable<[HoldingStore, Omit<RawBinding<'model_raw_response'>, 'contentCid'>, Uint8Array], HoldingArgs>>,
  Assert<IsNotAssignable<[HoldingStore, Omit<RawBinding<'lookup_raw_response'>, 'byteCount'>, Uint8Array], HoldingArgs>>,
  Assert<IsNotAssignable<[HoldingStore, RawBinding<'model_raw_response'>], HoldingArgs>>,
  Assert<IsNotAssignable<[HoldingStore, WireBinding, Uint8Array], HoldingArgs>>,
  Assert<IsNotAssignable<[HoldingStore, WireBinding & RawFields], HoldingArgs>>,
  Assert<IsNotAssignable<Omit<RawFields, 'byteCount'>, ModelRawPortBinding>>,
  Assert<IsNotAssignable<Omit<RawFields, 'contentCid'>, LookupRawPortBinding>>,
];

function fixture({releaseFailure, beforeCommitFailure, raw = false}: FixtureOptions = {}) {
  let visible = false, retired = false;
  let failRelease = releaseFailure, failCommit = beforeCommitFailure;
  const counts = {prepare: 0, commit: 0, confirm: 0, release: 0, status: 0};
  const record = Object.freeze({holding_cid: binding.holdingCid});
  const cleanupPending = Array(raw ? 2 : 1).fill(true);
  const objects = cleanupPending.map((_, index) => Object.freeze({
    physicalCid: cid(index === 0 ? 'c' : 'e'), bytes: 31,
    prepared: Object.freeze({
      status() {
        counts.status++;
        assert.equal(retired, false, 'retired prepared handle must not be consulted');
        return Object.freeze({pending: cleanupPending[index]});
      },
      async release() {
        counts.release++;
        if (failRelease !== undefined) throw failRelease;
        cleanupPending[index] = false;
        return true;
      },
    }),
  }));
  const confirm = async () => { counts.confirm++; return visible ? record as HoldingRecord : undefined; };
  const prepare = async () => objects[counts.prepare++];
  const store = {
    confirmPrivateEvidence: confirm,
    preparePrivateEvidence: prepare,
    confirmModelRawEvidence: async () => {
      const original = await confirm();
      return original === undefined ? undefined : {record: original};
    },
    prepareModelRawEvidence: async () => [await prepare(), await prepare()],
    async commitPhysicalHolding() {
      counts.commit++;
      if (failCommit !== undefined) throw failCommit;
      visible = true;
    },
  };
  const owner = raw
    ? preparePrivatePublicationHolding(store, {...binding,
      name: 'model_raw_response', contentCid: cid('d'), byteCount: 3}, Buffer.from('raw'))
    : preparePrivatePublicationHolding(store, binding, undefined);
  return {owner, counts, record,
    retire() { assert.ok(cleanupPending.every(value => value === false)); retired = true; },
    allowCleanup() { failRelease = undefined; },
    confirmOriginal() { visible = true; failCommit = undefined; },
  };
}

for (const raw of [false, true]) {
  test(`private holding retires prepared aliases after confirmed ${raw ? 'raw' : 'wire'} commit`, async () => {
    const f = fixture({raw});
    const first = f.owner.commit();
    assert.equal(f.owner.commit(), first);
    assert.equal(await first, f.record);
    const snapshot = f.owner.status();
    assert.equal(snapshot.committed, true);
    assert.equal(snapshot.preparedPending, false);
    const before = {...f.counts};
    f.retire();
    assert.equal(f.owner.status().preparedPending, false);
    assert.equal(await f.owner.commit(), f.record);
    assert.deepEqual(f.counts, before);
    assert.equal(snapshot.committed, true);
  });
}

test('private holding keeps rejected cleanup until same original commit is confirmed', async () => {
  const primary = new Error('OriginalPreparedCloseFailure');
  const f = fixture({releaseFailure: primary});
  await assert.rejects(f.owner.commit(), error => error === primary &&
    (error as Error & {cleanupPending?: boolean}).cleanupPending === true &&
    (error as Error & {cleanupHandle?: HoldingOwner}).cleanupHandle === f.owner);
  const pending = f.owner.status();
  assert.equal(pending.committed, false);
  assert.equal(pending.preparedPending, true);
  f.allowCleanup();
  assert.equal(await f.owner.retry(), f.record);
  assert.equal(f.counts.prepare, 1);
  assert.equal(f.counts.commit, 1);
  f.retire();
  assert.equal(f.owner.status().committed, true);
  assert.equal(f.owner.status().preparedPending, false);
  assert.equal(pending.preparedPending, true);
});

test('private holding retires prepared aliases only after confirmed abort cleanup', async () => {
  const primary = new Error('OriginalBeforeCommitFailure');
  const cleanup = new Error('OriginalAbortCloseFailure');
  const f = fixture({beforeCommitFailure: primary, releaseFailure: cleanup});
  await assert.rejects(f.owner.commit(), error => error === primary);
  await assert.rejects(f.owner.abort(), error => error === cleanup);
  assert.equal(f.owner.status().preparedPending, true);
  assert.equal(f.owner.status().abandoned, false);
  f.allowCleanup();
  assert.equal(await f.owner.abort(), true);
  f.retire();
  assert.equal(f.owner.status().preparedPending, false);
  assert.equal(f.owner.status().abandoned, true);
  await assert.rejects(f.owner.retry(), {code: 'PrivatePublicationHoldingAbandoned'});
  assert.deepEqual({prepare: f.counts.prepare, commit: f.counts.commit}, {prepare: 1, commit: 1});
});

test('private holding preserves a visible original instead of aborting or preparing again', async () => {
  const f = fixture({beforeCommitFailure: new Error('UnconfirmedOriginalCommit')});
  await assert.rejects(f.owner.commit(), {cleanupPending: true, cleanupHandle: f.owner});
  f.confirmOriginal();
  assert.equal(await f.owner.abort(), false);
  f.retire();
  assert.equal(f.owner.status().committed, true);
  assert.equal(f.owner.status().abandoned, false);
  assert.equal(f.owner.status().preparedPending, false);
  assert.deepEqual({prepare: f.counts.prepare, commit: f.counts.commit}, {prepare: 1, commit: 1});
});
