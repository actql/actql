// Independent full-payload observations only. This issues no Content reference,
// validates no authority/evidence preimage and reads no provider or Store.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

const cid = value => assert.match(value, /^sha256:[0-9a-f]{64}$/u);

export function assertInstalledFamilyCompleteContent(reference, expected) {
  assert(expected.bytes instanceof Uint8Array, 'Supply independently authored original bytes');
  assert.equal(typeof expected.mediaType, 'string'); assert(expected.mediaType.length > 0);
  assert(['content_derivation', 'connector_capture'].includes(expected.issuerKind));
  assert.deepEqual(Object.keys(expected).sort(), ['bytes', 'issuerKind', 'mediaType',
    ...(expected.issuerKind === 'connector_capture' ? ['reportedMediaType'] : [])].sort());
  const bytes = Buffer.from(expected.bytes);
  const contentCid = 'sha256:' + createHash('sha256').update(bytes).digest('hex');
  assert.deepEqual(Object.keys(reference).sort(), ['$actql_ref', 'content_ref_cid', 'media_type', 'metadata', 'version']);
  assert.equal(reference.$actql_ref, 'content');
  assert.equal(reference.version, 'actql-content-ref/0.1');
  cid(reference.content_ref_cid);
  assert.equal(reference.media_type, expected.mediaType);
  const metadata = reference.metadata;
  assert.equal(metadata.content_cid, contentCid);
  assert.equal(metadata.size_bytes, bytes.length);
  assert.equal(metadata.media_type, expected.mediaType);
  assert.equal(metadata.truncated, false);
  assert.equal(Object.hasOwn(metadata, 'byte_range'), false,
    'A selected range is a separate qualification, not a complete-object observation');
  const evidence = metadata.issuer_evidence;
  assert.equal(evidence.version, 'actql-content-issuer-evidence/0.1');
  assert.equal(evidence.issuer_kind, expected.issuerKind);
  assert.equal(evidence.content_cid, contentCid);
  if (expected.issuerKind === 'connector_capture') {
    assert.equal(typeof expected.reportedMediaType, 'string'); assert(expected.reportedMediaType.length > 0);
    assert.equal(evidence.reported_media_type, expected.reportedMediaType);
  } else {
    assert.equal(Object.hasOwn(evidence, 'reported_media_type'), false);
  }
}

export function assertInstalledFamilySavedContent(original, recovered, expected) {
  // Call with the actual persisted first envelope, never one rebuilt from the
  // current response or just its digest. Equal bytes alone do not pin lifetime,
  // policy, issuer, holding, availability or original Source provenance.
  assertInstalledFamilyCompleteContent(original, expected);
  assertInstalledFamilyCompleteContent(recovered, expected);
  assert.deepEqual(recovered, original, 'Saved must retain the complete original issued Content envelope');
}
