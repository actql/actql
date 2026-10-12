// Independent observation detector, not a Ref verifier or execution owner.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const canonical = value => value === null || typeof value !== 'object' ? JSON.stringify(value)
  : Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
    : `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
export const packedGcsRowsDigest = rows => createHash('sha256').update(canonical(rows)).digest('hex');

export function verifyPackedGcsObservations({entrance, phases, manifest}) {
  assert.equal(phases.length, 2);
  const [capture, read] = phases;
  for (const [index, phase] of phases.entries()) {
    assert.equal(phase.complete, true);
    assert.equal(phase.entrance, entrance);
    assert.equal(phase.phase, index === 0 ? 'capture' : 'read');
    assert.ok(Number.isSafeInteger(phase.pid) && phase.pid > 0);
    assert.deepEqual(phase.cases.map(value => value.name), ['capture', 'empty']);
  }
  assert.notEqual(capture.pid, read.pid);
  assert.deepEqual(capture.cases.map(value => value.runRef), read.cases.map(value => value.runRef));
  for (const [index, value] of capture.cases.entries()) {
    const expected = index === 0 ? manifest.expectedObjects : [];
    assert.deepEqual(value.rows.map(row => row.name), expected.map(object => object.name));
    assert.deepEqual(value.description.columns.map(column => column.name), ['name', 'content']);
    assert.equal(value.description.columns[1].contract.type, 'content_ref');
    for (const [rowIndex, row] of value.rows.entries()) {
      assert.equal(row.content.$actql_ref, 'content');
      assert.equal(row.content.media_type, expected[rowIndex].mediaType);
      assert.equal(row.content.metadata.content_cid, expected[rowIndex].contentCid);
      assert.equal(row.content.metadata.size_bytes, expected[rowIndex].sizeBytes);
      assert.equal(row.content.metadata.truncated, false);
      assert.equal(row.content.metadata.issuer_evidence.issuer_kind, 'connector_capture');
    }
    assert.equal(read.cases[index].rows, value.rows.length);
    assert.equal(read.cases[index].orderedRowsSha256, packedGcsRowsDigest(value.rows));
  }
  const {credentialResolutions: requests, reservedResponseBytes: bytes, tokenMints: mints} = capture.credential;
  assert.ok(Number.isSafeInteger(requests) && requests > 0 && requests <= Math.floor(manifest.limits.maxRequests / 2));
  assert.ok(Number.isSafeInteger(bytes) && bytes > 0 && bytes <= Math.floor(manifest.limits.maxResponseBytes / 2));
  assert.ok(Number.isSafeInteger(mints) && mints > 0 && mints <= requests);
  assert.equal(read.credential.credentialResolutions, 0);
  assert.equal(read.credential.tokenMints, 0);
}
