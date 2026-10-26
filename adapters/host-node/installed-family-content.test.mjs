// Unissued Content envelope DATA only, not an issuer, codec, Host, real stored
// bytes or public Result. Business bytes/digests are independent literals.
import assert from 'node:assert/strict';
import test from 'node:test';
import {assertInstalledFamilyCompleteContent, assertInstalledFamilySavedContent}
  from './fixtures/installed-family-content.fixture.mjs';

const token = digit => 'sha256:' + digit.repeat(64);
const jsonlCid = 'sha256:51bc513113548e062ada62b03efea153cae2abdf46b051c551c3e62a4dfb88cf';
const emptyCid = 'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
const jsonl = () => ({bytes: Buffer.from('{"id":1}\n'), mediaType: 'application/x-ndjson', issuerKind: 'content_derivation'});
function envelope(contentCid = jsonlCid, size = 9, media = 'application/x-ndjson', kind = 'content_derivation') {
  return {$actql_ref: 'content', version: 'actql-content-ref/0.1', content_ref_cid: token('a'), media_type: media,
    metadata: {content_store_id: 'unissued-fixture', content_cid: contentCid, media_type: media,
      size_bytes: size, storage_scope: 'workspace', retention_class: 'fixture', expires_at: '2026-11-01T00:00:00Z',
      availability_evidence_cid: token('1'), capture_authority: 'read_content', truncated: false,
      data_classification: 'internal', effective_data_policy_cid: token('2'),
      issuer_evidence: {version: 'actql-content-issuer-evidence/0.1', issuer_kind: kind,
        issuer_contract_cid: token('3'), content_store_cid: token('4'), workspace_scope_cid: token('5'),
        content_cid: contentCid, effective_data_policy_cid: token('2'), capture_authority_cid: token('6'),
        evidence_cid: token('7'), ...(kind === 'connector_capture' ? {reported_media_type: 'TEXT/PLAIN'} : {})}}};
}

test('complete Content observations preserve independent JSONL newline and genuinely empty bytes', () => {
  assertInstalledFamilyCompleteContent(envelope(), jsonl());
  const expected = {bytes: new Uint8Array(), mediaType: 'application/octet-stream', issuerKind: 'content_derivation'};
  assertInstalledFamilyCompleteContent(envelope(emptyCid, 0, expected.mediaType), expected);
  assert.throws(() => assertInstalledFamilyCompleteContent(envelope(), {...jsonl(), bytes: Buffer.from('{"id":1}')}));
  assert.throws(() => assertInstalledFamilyCompleteContent(envelope(), {...jsonl(), bytes: Buffer.from('{"id":1}\r\n')}));
});

test('wrong payload size media truncation range or issuer digest cannot pass complete Content', () => {
  for (const mutate of [
    x => {x.metadata.content_cid = token('8');},
    x => {x.metadata.size_bytes = '9';},
    x => {x.metadata.size_bytes = 8;},
    x => {x.media_type = 'text/plain';},
    x => {x.metadata.media_type = 'text/plain';},
    x => {x.metadata.truncated = true;},
    x => {x.metadata.byte_range = {start: 0, end_exclusive: 9};},
    x => {x.metadata.issuer_evidence.content_cid = token('9');},
  ]) {
    const observed = envelope(); mutate(observed);
    assert.throws(() => assertInstalledFamilyCompleteContent(observed, jsonl()));
  }
});

test('capture observed media spelling is independent of the explicitly expected effective media', () => {
  const expected = {bytes: Buffer.from('{"id":1}\n'), mediaType: 'text/plain',
    issuerKind: 'connector_capture', reportedMediaType: 'TEXT/PLAIN'};
  const observed = envelope(jsonlCid, 9, 'text/plain', 'connector_capture');
  assertInstalledFamilyCompleteContent(observed, expected);
  assert.throws(() => assertInstalledFamilyCompleteContent(observed, {...expected, reportedMediaType: 'text/plain'}));
  assert.throws(() => assertInstalledFamilyCompleteContent(observed, jsonl()));
});

test('generated issuer observations do not substitute capture headers or issuer kind', () => {
  for (const mutate of [
    x => {x.metadata.issuer_evidence.reported_media_type = 'application/x-ndjson';},
    x => {x.metadata.issuer_evidence.issuer_kind = 'connector_capture';},
  ]) {
    const observed = envelope(); mutate(observed);
    assert.throws(() => assertInstalledFamilyCompleteContent(observed, jsonl()));
  }
});

test('Saved envelope comparison retains original issuer policy availability lifetime and identity', () => {
  const original = envelope(); assertInstalledFamilySavedContent(original, structuredClone(original), jsonl());
  for (const mutate of [
    x => {x.content_ref_cid = token('b');},
    x => {x.metadata.expires_at = '2027-11-01T00:00:00Z';},
    x => {x.metadata.availability_evidence_cid = token('c');},
    x => {x.metadata.effective_data_policy_cid = token('d');},
    x => {x.metadata.issuer_evidence.workspace_scope_cid = token('e');},
    x => {x.metadata.issuer_evidence.evidence_cid = token('f');},
    x => {x.metadata.content_store_id = 'other-holding';},
    x => {x.metadata.source_resource_ref = {unissued: 'different-source'};},
    x => {x.metadata.source_version = 'different-version';},
    x => {x.metadata.source_etag = 'different-etag';},
  ]) {
    const recovered = structuredClone(original); mutate(recovered);
    assertInstalledFamilyCompleteContent(recovered, jsonl()); // Same payload alone is insufficient.
    assert.throws(() => assertInstalledFamilySavedContent(original, recovered, jsonl()));
  }
});

test('reference-looking strings bad tags missing metadata and output-derived extra expectations refuse', () => {
  assert.throws(() => assertInstalledFamilyCompleteContent(JSON.stringify(envelope()), jsonl()));
  for (const mutate of [x => {delete x.metadata;}, x => {x.$actql_ref = 'resource';},
    x => {x.content_ref_cid = 'not-a-cid';}, x => {x.extra = true;}]) {
    const observed = envelope(); mutate(observed);
    assert.throws(() => assertInstalledFamilyCompleteContent(observed, jsonl()));
  }
  assert.throws(() => assertInstalledFamilyCompleteContent(envelope(), {...jsonl(), contentCid: jsonlCid}));
  assert.throws(() => assertInstalledFamilyCompleteContent(envelope(), {...jsonl(), bytes: '{"id":1}\n'}));
});


test('binary Content hashes original bytes without UTF-8 decoding or Unicode normalization', () => {
  const bytes = Buffer.from([0, 255, 13, 10, 195, 169, 101, 204, 129]);
  const expected = {bytes, mediaType: 'application/octet-stream', issuerKind: 'content_derivation'};
  const observed = envelope("sha256:b0560599837a617a5f0f121f95d995d934caa15552adb04859d92e0fdba92d3c", 9, expected.mediaType);
  assertInstalledFamilyCompleteContent(observed, expected);
  assert.throws(() => assertInstalledFamilyCompleteContent(observed,
    {...expected, bytes: Buffer.from(bytes.toString('utf8'))}));
});
