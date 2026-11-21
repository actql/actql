import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import type {TestContext} from 'node:test';
import {openLocalPublicationStore} from
  // @ts-expect-error TS7016: remove after migrating the Local publication Store.
  '../store-local/publication-store.mjs';
// @ts-expect-error TS7016: remove after migrating the Common runtime adapter.
import {runtimeCore} from './runtime-core.mjs';
import {preparePrivatePublicationHolding} from
  './private-publication-holding.mjs';

type HoldingStore = Parameters<typeof preparePrivatePublicationHolding>[0];
type HoldingOwner = ReturnType<typeof preparePrivatePublicationHolding>;
type PrepareEvidence = NonNullable<HoldingStore['preparePrivateEvidence']>;
type ConfirmEvidence = NonNullable<HoldingStore['confirmPrivateEvidence']>;
type FixtureStore = Omit<HoldingStore, 'confirmPrivateEvidence'> & Readonly<{
  preparePrivateEvidence: PrepareEvidence;
  confirmPrivateEvidence(...args: Parameters<ConfirmEvidence>): Promise<Awaited<ReturnType<ConfirmEvidence>>>;
  close(): Promise<boolean>;
  inspectPhysicalHolding(cid: string): Promise<unknown>;
  readPrivateEvidence(name: string, semanticCid: string, holdingCid: string): Promise<Buffer>;
  retirePhysicalHolding(cid: string): Promise<Readonly<{deleted: boolean}>>;
  status(): Readonly<{storedBytes: number; reservedBytes: number}>;
}>;
type CustodyFailure = Error & Readonly<{cleanupPending?: boolean; cleanupHandle?: HoldingOwner}>;

const runtimePath = '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
const moon = await import(runtimePath) as object;

const cid = (digit: string) => `sha256:${digit.repeat(64)}`;
const binding = Object.freeze({
  name: 'effect_preview', semanticCid: cid('a'),
  holdingCid: cid('b'), wire: '{"private":"preview"}',
});

async function fixture(t: TestContext) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-private-owner-'));
  const store = await openLocalPublicationStore({
    directory, storeAuthorityCid: cid('c'),
    capacityBytes: 1024 * 1024, maxObjectBytes: 4096,
    maxObjects: 20, maxContractNodes: 200, maxContractDepth: 16,
    privateEvidenceKey: Buffer.alloc(32, 7),
  }, runtimeCore(moon).publicationControl) as FixtureStore;
  t.after(async () => {
    assert.equal(await store.close(), true);
    await rm(directory, {recursive: true, force: true});
  });
  return store;
}

test('private holding reconciles a lost durable commit acknowledgement',
  async t => {
    const store = await fixture(t);
    let prepares = 0;
    let commits = 0;
    const observed: HoldingStore = {
      confirmPrivateEvidence: value => store.confirmPrivateEvidence(value),
      preparePrivateEvidence: (...args) => {
        prepares++;
        return store.preparePrivateEvidence(...args);
      },
      async commitPhysicalHolding(...args) {
        commits++;
        await store.commitPhysicalHolding(...args);
        throw new Error('LostHoldingAcknowledgement');
      },
    };
    const owner = preparePrivatePublicationHolding(observed, binding);
    const first = owner.commit();
    assert.equal(owner.commit(), first);
    const record = await first;
    assert.equal(record.holding_cid, binding.holdingCid);
    assert.equal(prepares, 1);
    assert.equal(commits, 1);
    assert.equal(owner.status().committed, true);
    assert.equal(await owner.abort(), false);
    assert.equal((await store.readPrivateEvidence(binding.name,
      binding.semanticCid, binding.holdingCid)).toString(), binding.wire);
    assert.equal((await store.retirePhysicalHolding(
      binding.holdingCid)).deleted, true);
  });

test('private holding retains one preparation across failed commit retry',
  async t => {
    const store = await fixture(t);
    let prepares = 0;
    let commits = 0;
    const observed: HoldingStore = {
      confirmPrivateEvidence: value => store.confirmPrivateEvidence(value),
      preparePrivateEvidence: (...args) => {
        prepares++;
        return store.preparePrivateEvidence(...args);
      },
      commitPhysicalHolding(...args) {
        commits++;
        if (commits === 1) throw new Error('BeforeHoldingCommit');
        return store.commitPhysicalHolding(...args);
      },
    };
    const owner = preparePrivatePublicationHolding(observed, binding);
    await assert.rejects(owner.commit(), error => {
      assert.equal((error as CustodyFailure).message, 'BeforeHoldingCommit');
      assert.equal((error as CustodyFailure).cleanupPending, true);
      assert.equal((error as CustodyFailure).cleanupHandle, owner);
      return true;
    });
    assert.equal(owner.status().preparedPending, true);
    assert.equal((await owner.commit()).holding_cid, binding.holdingCid);
    assert.equal(prepares, 1);
    assert.equal(commits, 2);
    assert.equal(owner.status().preparedPending, false);
    assert.equal((await store.retirePhysicalHolding(
      binding.holdingCid)).deleted, true);
  });

test('private holding abort requires confirmed non-commit', async t => {
  const store = await fixture(t);
  const owner = preparePrivatePublicationHolding(store, binding);
  assert.equal(await owner.abort(), true);
  await assert.rejects(owner.commit(),
    {code: 'PrivatePublicationHoldingAbandoned'});
  assert.equal(await store.inspectPhysicalHolding(binding.holdingCid),
    undefined);
});

test('source observation custody survives a failed write without replacement',
  async t => {
    const store = await fixture(t);
    const source = {...binding, name: 'source_evidence'};
    let preparations = 0;
    let commits = 0;
    const owner = preparePrivatePublicationHolding({
      confirmPrivateEvidence: value => store.confirmPrivateEvidence(value),
      preparePrivateEvidence: (...args) => {
        preparations++;
        return store.preparePrivateEvidence(...args);
      },
      commitPhysicalHolding: (...args) => {
        if (++commits === 1) throw new Error('SourceCustodyWriteFailed');
        return store.commitPhysicalHolding(...args);
      },
    }, source);
    await assert.rejects(owner.commit(), {message: 'SourceCustodyWriteFailed'});
    assert.equal(owner.status().preparedPending, true);
    await owner.retry();
    assert.equal(preparations, 1);
    assert.equal(commits, 2);
    assert.equal((await store.readPrivateEvidence(source.name,
      source.semanticCid, source.holdingCid)).toString(), source.wire);
    await assert.rejects(store.confirmPrivateEvidence({...source,
      wire: '{"private":"replacement"}'}));
    assert.equal((await store.retirePhysicalHolding(source.holdingCid)).deleted,
      true);
  });

test('private holding abort reclaims an uncommitted preparation', async t => {
  const store = await fixture(t);
  const observed: HoldingStore = {
    confirmPrivateEvidence: value => store.confirmPrivateEvidence(value),
    preparePrivateEvidence: (...args) =>
      store.preparePrivateEvidence(...args),
    commitPhysicalHolding() { throw new Error('BeforeHoldingCommit'); },
  };
  const owner = preparePrivatePublicationHolding(observed, binding);
  await assert.rejects(owner.commit(), {cleanupPending: true});
  const first = owner.abort();
  assert.equal(owner.abort(), first);
  assert.equal(await first, true);
  assert.equal(owner.status().preparedPending, false);
  assert.equal(store.status().storedBytes, 0);
  assert.equal(store.status().reservedBytes, 0);
});
