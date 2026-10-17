import assert from 'node:assert/strict';
import test from 'node:test';
import {bytesCid, canonicalJson, reviewBytesMatchCid} from './checkpoints.mjs';
import {vectors, expectedCids, canonicalText} from '../../scripts/fixtures/effect-review-projection-vectors.mjs';

const bytes = value => new TextEncoder().encode(value);

test('Effect review identity uses its exact original self-excluding preimage', async () => {
  for (const [index, vector] of vectors.entries()) {
    assert.notEqual(await bytesCid(bytes(vector.reviewWire)), expectedCids[index]);
    assert.equal(await reviewBytesMatchCid(bytes(vector.reviewWire), expectedCids[index]), true);
  }
});

test('Effect semantic review verification rejects altered DATA, self identity and encoding', async () => {
  const vector = vectors.at(-1);
  const changed = structuredClone(vector.review);
  changed.displayed_rows[0].after.value.line = 'changed';
  for (const wire of [canonicalText(changed),
    canonicalText({...vector.review, review_projection_cid: expectedCids[0]}),
    canonicalText({...vector.review, version: 'actql-review-projection/other'}),
    JSON.stringify(vector.review, null, 2)]) {
    assert.equal(await reviewBytesMatchCid(bytes(wire), vector.cid), false);
  }
  assert.throws(() => canonicalJson(vector.review), /CanonicalKeyCollision/);
  assert.equal(await reviewBytesMatchCid(Uint8Array.of(255), vector.cid), false);
});

test('legacy complete-byte digest remains separate from a semantic review proof', async () => {
  const legacy = bytes('{"legacy":"review"}');
  assert.equal(await reviewBytesMatchCid(legacy, await bytesCid(legacy)), true);
  assert.equal(await reviewBytesMatchCid(legacy, expectedCids[0]), false);
});
