import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openLocalPublicationStore} from
  '../store-local/publication-store.mjs';
import {runtimeCore} from './runtime-core.mjs';
import {preparePrivatePublicationHolding} from
  './private-publication-holding.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const binding = Object.freeze({
  name: 'effect_preview', semanticCid: cid('a'),
  holdingCid: cid('b'), wire: '{"private":"preview"}',
});

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-private-owner-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const store = await openLocalPublicationStore({
    directory, storeAuthorityCid: cid('c'),
    capacityBytes: 1024 * 1024, maxObjectBytes: 4096,
    maxObjects: 20, maxContractNodes: 200, maxContractDepth: 16,
    privateEvidenceKey: Buffer.alloc(32, 7),
  }, runtimeCore(moon).publicationControl);
  t.after(() => store.close());
  return store;
}

test('private holding reconciles a lost durable commit acknowledgement',
  async t => {
    const store = await fixture(t);
    let prepares = 0;
    let commits = 0;
    const observed = {
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
    const observed = {
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
      assert.equal(error.message, 'BeforeHoldingCommit');
      assert.equal(error.cleanupPending, true);
      assert.equal(error.cleanupHandle, owner);
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

test('private holding abort reclaims an uncommitted preparation', async t => {
  const store = await fixture(t);
  const observed = {
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
