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

// Physical Store adapter fixture only. A semantic typed raw factory/credential
// claim must supply the real grant/use/request and prefunded reservation.
test('raw physical role retains non2xx and rejected projection bytes after lost ACK and reopen', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-credential-raw-role-'));
  let accepted = false;
  let store, reopened;
  t.after(async () => {
    await reopened?.close();
    await store?.close();
    if (accepted) await rm(directory, {recursive: true, force: true});
    else console.log(JSON.stringify({retainedFailedRawFixture: directory}));
  });
  const configuration = {
    directory, storeAuthorityCid: digest('original-raw-store'),
    capacityBytes: 65536, maxObjectBytes: 8192, maxObjects: 8,
    maxContractNodes: 256, maxContractDepth: 16,
    privateEvidenceKey: Buffer.alloc(32, 7),
  };
  const control = createPublicationContractControlFixture();
  store = await openLocalPublicationStore(configuration, control);
  let commits = 0;
  const originals = [
    {status: 401, body: Buffer.from('e\u0301\r\n')},
    {status: 200, body: Buffer.from([0, 255, 13, 10])},
    {status: 204, body: Buffer.alloc(0)},
  ];
  const bindings = originals.map(({status, body}, index) => ({
    name: 'credential_raw_observation',
    semanticCid: digest(`original-raw-use-${index}`),
    holdingCid: digest(`original-raw-slot-${index}`),
    wire: JSON.stringify(['original-raw-adapter-fixture', String(status),
      digest(body), body.toString('base64')]),
  }));
  for (const binding of bindings) {
    const owner = preparePrivatePublicationHolding({
      confirmPrivateEvidence: value => store.confirmPrivateEvidence(value),
      preparePrivateEvidence: (...args) => store.preparePrivateEvidence(...args),
      async commitPhysicalHolding(...args) {
        commits++;
        await store.commitPhysicalHolding(...args);
        throw new Error('LostOriginalRawCommitReply');
      },
    }, binding);
    await owner.commit();
    await owner.retry();
  }
  assert.equal(commits, 3, 'Saved ACK loss must not repeat physical commit');
  await store.close();
  reopened = await openLocalPublicationStore(configuration, control);
  for (const binding of bindings) {
    assert.equal((await reopened.readPrivateEvidence(binding.name,
      binding.semanticCid, binding.holdingCid)).toString(), binding.wire);
    for (const role of ['effect_catalog', 'effect_capture', 'model_call_attempt']) {
      await assert.rejects(reopened.readPrivateEvidence(role,
        binding.semanticCid, binding.holdingCid));
    }
    await assert.rejects(reopened.confirmPrivateEvidence({...binding,
      semanticCid: digest('foreign-use')}));
    assert.equal((await reopened.retirePhysicalHolding(binding.holdingCid)).deleted, true);
  }
  const released = reopened.status();
  for (const binding of bindings) {
    assert.equal((await reopened.retirePhysicalHolding(binding.holdingCid)).deleted, true);
  }
  assert.deepEqual(reopened.status(), released);
  assert.equal(released.reservedBytes, 0);
  assert.equal(released.storedBytes, 0);
  accepted = true;
});

test('raw cipher independent vector cannot be authenticated as another private role', () => {
  const key = Buffer.from(Array.from({length: 32}, (_, i) => i));
  const nonce = Buffer.from(Array.from({length: 12}, (_, i) => i));
  const cid = `sha256:${'0'.repeat(64)}`;
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(Buffer.from(`actql-private-publication-evidence/0.1\0credential_raw_observation\0${cid}`));
  const encrypted = Buffer.concat([cipher.update('native-private-evidence-fixture'), cipher.final()]);
  assert.equal(encrypted.toString('base64'), 'KWOicrOA72v/KOHqxYxVCPW/41GeGDpRXg6d8WgbZQ==');
  const tag = cipher.getAuthTag();
  assert.equal(tag.toString('base64'), 'M5MACSiYVAwOAhJ4P/F8Tw==');
  for (const role of ['effect_catalog', 'effect_capture', 'effect_preview', 'checkpoint',
    'continuation_record', 'model_capture_bundle', 'model_slot_capture',
    'model_invocation_evidence', 'model_call_attempt', 'model_attempt_accounting',
    'model_attempt_outcome', 'model_dispatch_authority', 'observation_set',
    'run_invocation', 'source_evidence']) {
    const decipher = createDecipheriv('aes-256-gcm', key, nonce);
    decipher.setAAD(Buffer.from(`actql-private-publication-evidence/0.1\0${role}\0${cid}`));
    decipher.setAuthTag(tag);
    decipher.update(encrypted);
    assert.throws(() => decipher.final());
  }
});
