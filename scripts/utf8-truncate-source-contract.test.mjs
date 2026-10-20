import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import test from 'node:test';

const fixture = 'scripts/fixtures/utf8-truncate-source/';
const vector = JSON.parse(readFileSync(fixture + 'identities.json', 'utf8'));
const hash = text => 'sha256:' + createHash('sha256').update(text).digest('hex');
const canonical = value => value === null || typeof value !== 'object' ? JSON.stringify(value)
  : Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
    : `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;

test('UTF8_TRUNCATE preserves complete preceding source rules and all unrelated grammar members', () => {
  const rules = gunzipSync(readFileSync(fixture + 'preceding-query-rules.md.gz'));
  assert.equal(hash(rules).slice(7), vector.before.query_text_rules_sha256);
  for (const value of [vector.before, vector.after]) {
    const {grammar_manifest_cid: cid, ...body} = value;
    assert.equal(hash(canonical(body)), cid);
  }
  assert.deepEqual({...vector.after,
    grammar_manifest_cid: vector.before.grammar_manifest_cid,
    query_text_rules_sha256: vector.before.query_text_rules_sha256}, vector.before);
  assert.notEqual(vector.before.grammar_manifest_cid, vector.after.grammar_manifest_cid);
});

test('UTF8_TRUNCATE source machine and complete envelope have independent canonical preimages', () => {
  for (const record of vector.expressions) {
    assert.equal(canonical(record.value), record.preimage);
    assert.equal(hash(record.preimage), record.cid);
  }
  assert.notEqual(vector.expressions[0].cid, vector.expressions[1].cid);
  const {envelope_cid: cid, ...body} = vector.envelope.value;
  assert.equal(canonical(vector.envelope.value), vector.envelope.preimage);
  assert.equal(hash(canonical(body)), cid);
  assert.equal(hash(canonical({max_bytes: {literal: 6}, value: {field: 'text'}})), body.arguments_cid);
});
