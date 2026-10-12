import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash, createCipheriv, createDecipheriv} from 'node:crypto';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {preparePrivatePublicationHolding} from
  '../host-common/private-publication-holding.mjs';

const digest = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;

test('Catalog physical holding keeps exact role bytes across lost reply and reopen', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-effect-catalog-role-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const configuration = {
    directory, storeAuthorityCid: digest('original-store'),
    capacityBytes: 65536, maxObjectBytes: 8192, maxObjects: 8,
    maxContractNodes: 256, maxContractDepth: 16,
    privateEvidenceKey: Buffer.alloc(32, 7),
  };
  // Independent physical adapter fixture; this does not issue semantic Catalog
  // evidence, Provider rights, Reviewer approval or a public Effect.
  const control = createPublicationContractControlFixture();
  const store = await openLocalPublicationStore(configuration, control);
  t.after(() => store.close());
  const binding = {
    name: 'effect_catalog', semanticCid: digest('original-catalog-slot'),
    holdingCid: digest('original-catalog-holding'),
    wire: '["original-binding","e\u0301\\r\\n"]',
  };
  let commits = 0;
  const owner = preparePrivatePublicationHolding({
    confirmPrivateEvidence: value => store.confirmPrivateEvidence(value),
    preparePrivateEvidence: (...args) => store.preparePrivateEvidence(...args),
    async commitPhysicalHolding(...args) {
      commits++;
      await store.commitPhysicalHolding(...args);
      throw new Error('LostOriginalCatalogCommitReply');
    },
  }, binding);
  await owner.commit();
  await owner.retry();
  assert.equal(commits, 1);
  assert.equal((await store.confirmPrivateEvidence(binding)).holding_cid, binding.holdingCid);
  await store.close();
  const reopened = await openLocalPublicationStore(configuration, control);
  t.after(() => reopened.close());
  assert.equal((await reopened.readPrivateEvidence(binding.name,
    binding.semanticCid, binding.holdingCid)).toString(), binding.wire);
  await assert.rejects(reopened.readPrivateEvidence('effect_capture',
    binding.semanticCid, binding.holdingCid), {code: 'PublicationPrivateEvidenceCorrupt'});
  await assert.rejects(reopened.confirmPrivateEvidence({...binding, wire: 'foreign'}));
  assert.equal((await reopened.retirePhysicalHolding(binding.holdingCid)).deleted, true);
  const retiredStatus = reopened.status();
  // deleted confirms physical absence; it does not count a new deletion.
  assert.equal((await reopened.retirePhysicalHolding(binding.holdingCid)).deleted, true);
  assert.deepEqual(reopened.status(), retiredStatus);
  assert.equal(reopened.status().reservedBytes, 0);
  assert.equal(reopened.status().storedBytes, 0);
});

test('independent Catalog cipher vector separates every existing private role', () => {
  const key = Buffer.from(Array.from({length: 32}, (_, i) => i));
  const nonce = Buffer.from(Array.from({length: 12}, (_, i) => i));
  const cid = `sha256:${'0'.repeat(64)}`;
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(Buffer.from(`actql-private-publication-evidence/0.1\0effect_catalog\0${cid}`));
  const encrypted = Buffer.concat([cipher.update('native-private-evidence-fixture'), cipher.final()]);
  assert.equal(encrypted.toString('base64'), 'KWOicrOA72v/KOHqxYxVCPW/41GeGDpRXg6d8WgbZQ==');
  assert.equal(cipher.getAuthTag().toString('base64'), 'Lp6w6J1zL2EI2B/BmufyJQ==');
  for (const role of ['effect_preview', 'effect_capture', 'continuation_record', 'checkpoint',
    'model_capture_bundle', 'model_slot_capture', 'model_invocation_evidence',
    'model_call_attempt', 'model_attempt_accounting', 'model_attempt_outcome',
    'model_dispatch_authority', 'observation_set', 'run_invocation', 'source_evidence']) {
    const decipher = createDecipheriv('aes-256-gcm', key, nonce);
    decipher.setAAD(Buffer.from(`actql-private-publication-evidence/0.1\0${role}\0${cid}`));
    decipher.setAuthTag(cipher.getAuthTag());
    decipher.update(encrypted);
    assert.throws(() => decipher.final());
  }
});
