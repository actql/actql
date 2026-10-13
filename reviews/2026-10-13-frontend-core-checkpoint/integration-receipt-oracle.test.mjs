import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import test from 'node:test';

const canonical = value => Array.isArray(value) ? value.map(canonical)
  : value && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]))
    : value;
const cid = value => 'sha256:' + createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
const read = path => readFileSync(path, 'utf8');
const original = JSON.parse(read('reviews/2026-10-13-frontend-core-checkpoint/integration-receipt-original-controls.json'));
const prior = path => {
  const text = execFileSync('git', ['show', original.base + ':' + path], {encoding: 'utf8'});
  assert.equal(createHash('sha256').update(text).digest('hex'), original.sources[path]);
  return text;
};
const oldPin = 'sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8';
const currentPin = 'sha256:d3d2737da6d73801f85208a2cdfe50c412e9f7b24e8bf9807e6f804e11757dd7';

test('Native fixture capability and independent observation identify the current normative preimage', () => {
  const body = JSON.parse(read('spec/contracts/actql-query-two-receipt.json'));
  const preimage = JSON.stringify(canonical(body));
  assert.match(preimage, /^[\x00-\x7f]*$/);
  assert.equal(Buffer.byteLength(preimage), 7219);
  assert.equal(cid(body), currentPin);
  assert.equal(cid(original.historicalReceipt.body), oldPin);
  for (const file of ['resident_native_source_wbtest.mbt', 'duckdb_native_capture_wbtest.mbt']) {
    const path = 'src/query_integration/' + file;
    const text = read(path);
    assert.equal(text.split(currentPin).length, 2);
    assert.equal(text.replace(currentPin, oldPin), prior(path));
  }
});

test('All original Native authorization inputs and refusals remain verbatim', () => {
  const path = 'src/query_integration/python_local_native_authorization_wbtest.mbt';
  const old = prior(path);
  assert.ok(read(path).startsWith(old));
  assert.ok(read(path).slice(old.length).includes('source_evidence_context_supports'));
});

test('Current independently reconstructed Program CID leaves every policy offer and assignment unchanged', () => {
  const fixture = JSON.parse(read('portability/corpus/policy-candidates.json'));
  assert.equal(cid(original.historicalPolicy.body), original.historicalPolicy.expected_cid);
  assert.equal(cid(fixture.body), fixture.expected_cid);
  assert.equal(fixture.body[1], 'sha256:63af34b702f8d1b719cc9492d220c9c6929b2b047cd0e4837d70d1ef9d3a0dfd');
  assert.deepEqual([fixture.body[0], ...fixture.body.slice(2)],
    [original.historicalPolicy.body[0], ...original.historicalPolicy.body.slice(2)]);
  execFileSync(process.execPath, ['scripts/check-policy-candidates.mjs'], {stdio: 'pipe'});
});
