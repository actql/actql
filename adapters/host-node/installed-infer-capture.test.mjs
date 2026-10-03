import assert from 'node:assert/strict';
import test from 'node:test';
import {readInstalledInferCapture} from './installed-infer-capture.mjs';

function fixture({missing, rejectReplay = false} = {}) {
  const reads = [];
  let released = 0;
  const bundle = {};
  const definition = {};
  const compiled = {};
  const verified = {};
  const control = {
    modelPrivateHoldingCid(actual, store, role, slot) {
      assert.equal(actual, definition);
      assert.equal(store, 'store');
      return `${role}:${slot}`;
    },
    admitRunEvidence(name, wire) {
      assert.ok(['observation_set', 'source_evidence'].includes(name));
      return {name, wire};
    },
    readCheckedClientInferSlotReplay(actual, run, observation, records,
      capture, proofs) {
      assert.equal(actual, compiled);
      assert.equal(run, definition);
      assert.equal(capture, bundle);
      assert.equal(records.length, 1);
      assert.equal(proofs.length, 1);
      if (rejectReplay) throw new Error('CommonReplayBindingRejected');
      return verified;
    },
  };
  const store = {
    async inspectPhysicalHolding(key) {
      reads.push(key);
      return key === missing ? undefined : {manifest_cid: key};
    },
    async readPrivateEvidence(name, semantic, holding) {
      assert.equal(semantic, holding);
      return Buffer.from(name === 'observation_set'
        ? '{"model_slot_capture_cids":["slot"]}' : '{}');
    },
    async confirmPrivateEvidence() {},
  };
  const moon = {
    strategyRunEvidenceAdmit: () => ({$tag: 1, _0: {}}),
    clientProgramInferAttemptRecords: (...leaves) => {
      assert.equal(leaves.length, 4);
      return {};
    },
    clientProgramReadInferCaptureBundle: () => ({$tag: 1, _0: bundle}),
    clientProgramReleaseInferCaptureBundle(value) {
      assert.equal(value, bundle);
      released++;
    },
  };
  return {options: {moon, control, store, compiled, runDefinition: definition,
    storeAuthorityCid: 'store'}, reads, verified, released: () => released};
}

test('installed capture read transfers only a common-verified replay owner',
  async () => {
    const value = fixture();
    assert.equal(await readInstalledInferCapture(value.options), value.verified);
    assert.equal(value.released(), 1);
    assert.deepEqual(value.reads, ['observation_set:-1', 'model_slot_capture:0',
      'model_call_attempt:0', 'model_attempt_accounting:0',
      'model_attempt_outcome:0', 'model_dispatch_authority:0',
      'model_capture_bundle:-1']);
  });

test('missing slot custody cannot become a provider fallback', async () => {
  const value = fixture({missing: 'model_slot_capture:0'});
  await assert.rejects(readInstalledInferCapture(value.options),
    {code: 'InstalledInferCaptureUnavailable'});
  assert.deepEqual(value.reads, ['observation_set:-1', 'model_slot_capture:0']);
});

test('common replay rejection releases the temporary bundle reader', async () => {
  const value = fixture({rejectReplay: true});
  await assert.rejects(readInstalledInferCapture(value.options),
    /CommonReplayBindingRejected/);
  assert.equal(value.released(), 1);
});

test('acquired replay restores source custody before reading model slots', async () => {
  const value = fixture();
  let restored = 0;
  value.options.restoreSource = (source, observation) => {
    assert.equal(source.name, 'source_evidence');
    assert.equal(observation.name, 'observation_set');
    assert.deepEqual(value.reads, ['observation_set:-1', 'source_evidence:0']);
    restored++;
  };
  assert.equal(await readInstalledInferCapture(value.options), value.verified);
  assert.equal(restored, 1);
});

test('missing or rejected source custody never opens the model capture', async () => {
  for (const missing of [undefined, 'source_evidence:0']) {
    const value = fixture({missing});
    value.options.restoreSource = () => { throw new Error('SourceBindingRejected'); };
    await assert.rejects(readInstalledInferCapture(value.options),
      missing === undefined ? /SourceBindingRejected/ :
        {code: 'InstalledInferCaptureUnavailable'});
    assert.deepEqual(value.reads, ['observation_set:-1', 'source_evidence:0']);
    assert.equal(value.released(), 0);
  }
});
