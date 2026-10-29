import assert from 'node:assert/strict';
import test from 'node:test';
import {admitEffectPreviewIdentity, effectPreviewIdentityCid,
  admitPublicationContract, issueEffectfulFinalRunReceipt,
  validateEffectfulPublicationCommit} from './index.mjs';
import * as runtime from './dist/client_values_host_abi.js';
import {C, canonicalText, hash, vectors, originalRun, authoring,
  expectedCids} from '../../scripts/fixtures/effect-review-projection-vectors.mjs';

// Actual compiled ABI and public facade, using existing independent preimages.
// These pure fixtures perform no Provider operation, capture, claim or Store
// commit. Incomplete completion evidence below must refuse, never become a
// fabricated captured Run or a successful publication.
const limits = Object.freeze({maxWireBytes: 65536, maxNodes: 4096, maxDepth: 32});
const vector = vectors[0];
const preview = () => admitEffectPreviewIdentity(vector.previewWire,
  originalRun, authoring.authoring_context_cid, limits);

test('compiled Effect Preview admission and semantic observer use the public facade namespace', () => {
  for (const name of ['clientValuesHostAdmitEffectPreviewIdentity',
    'clientValuesHostEffectPreviewMemberCount', 'clientValuesHostEffectPreviewSemanticIdentity',
    'clientValuesHostIssueEffectfulFinalRunReceipt', 'clientValuesHostValidateEffectfulPublicationCommit']) {
    assert.equal(typeof runtime[name], 'function', `Missing compiled export: ${name}`);
  }
  assert.equal(hash(vector.body), expectedCids[0], 'Existing independent preimage pin');
  const original = preview();
  assert.equal(effectPreviewIdentityCid(original), vector.preview.effect_preview_cid);
  assert.equal(effectPreviewIdentityCid(original), vector.preview.effect_preview_cid);
});

test('compiled Preview refuses foreign original tuples and malformed bytes without scalar fallback', () => {
  const refused = error => error.code === 'RunHostEffectPreviewRejected';
  assert.throws(() => admitEffectPreviewIdentity(vector.previewWire, C('f'),
    authoring.authoring_context_cid, limits), refused);
  assert.throws(() => admitEffectPreviewIdentity(vector.previewWire, originalRun,
    C('f'), limits), refused);
  assert.throws(() => admitEffectPreviewIdentity('{', originalRun,
    authoring.authoring_context_cid, limits), refused);
  const original = preview();
  assert.throws(() => effectPreviewIdentityCid({...original}), /ForeignRunHostHandle/u);
  assert.throws(() => effectPreviewIdentityCid(vector.preview.effect_preview_cid), /ForeignRunHostHandle/u);
});

test('compiled receipt and commit ports refuse a real admitted contract of the wrong kind', () => {
  const body = {version: 'actql-result-definition/0.1',
    program_definition_cid: C('6'), result_name: 'answer'};
  const definition = admitPublicationContract('result_definition',
    canonicalText({...body, result_definition_cid: hash(body)}), limits);
  const original = preview();
  // A real Result Definition is deliberately not computation/capture evidence.
  // No positive final-receipt or complete captured-Run fixture is claimed.
  assert.throws(() => issueEffectfulFinalRunReceipt(definition, definition,
    definition, original, 'not an admitted set receipt', ['not an admitted member receipt'], limits),
  error => error.code === 'RunHostEffectfulFinalReceiptRejected');
  assert.throws(() => validateEffectfulPublicationCommit({runDefinition: definition,
    invocation: definition, definitions: [definition], artifacts: [], derivations: [],
    orderings: [], retentions: [], durableBindings: [], manifest: definition,
    computationReceipt: definition, capturedRun: definition, preview: original,
    setReceiptWire: 'not an admitted set receipt', memberReceiptWires: ['not an admitted member receipt'],
    finalReceipt: definition}, definition, definition, definition, limits),
  error => error.code === 'RunHostEffectfulPublicationCommitRejected');
});
