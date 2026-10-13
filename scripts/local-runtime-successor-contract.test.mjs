import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const fixture = JSON.parse(readFileSync(new URL('../spec/contracts/fixtures/local-runtime-successor.json', import.meta.url)));
const schema = JSON.parse(readFileSync(new URL('../spec/contracts/actql-local-runtime-successor.schema.json', import.meta.url)));
const record = JSON.parse(fixture.body);
const cid = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;

// Structural schema interpreter only. It does not authenticate an original,
// create a physical witness or perform a current Account/compatibility check.
function valid(shape, value) {
  for (const key of Object.keys(shape)) assert.ok([
    '$schema', '$id', 'type', 'additionalProperties', 'required', 'properties',
    'const', 'pattern', 'minLength', 'maxLength',
  ].includes(key), key);
  if (Object.hasOwn(shape, 'const')) return value === shape.const;
  if (shape.type === 'string') return typeof value === 'string'
    && (!shape.pattern || new RegExp(shape.pattern).test(value))
    && (!shape.minLength || [...value].length >= shape.minLength)
    && (!shape.maxLength || [...value].length <= shape.maxLength);
  if (shape.type !== 'object' || !value || typeof value !== 'object' || Array.isArray(value)) return false;
  return shape.required.every(key => Object.hasOwn(value, key))
    && Object.entries(value).every(([key, field]) => Object.hasOwn(shape.properties, key) && valid(shape.properties[key], field));
}

test('successor independent eleven-field bytes keep prior exact manifest separate from synthetic current', () => {
  assert.equal(valid(schema, record), true);
  assert.deepEqual(Object.keys(record), [...schema.required].sort());
  assert.equal(fixture.bytes, 4344);
  assert.equal(Buffer.byteLength(fixture.body), 4344);
  assert.equal(cid(fixture.body), 'sha256:e4a1b2d89f094acc5680f3f88fd04224022d8682b9b2dffbe7b4eda3d0e2616b');
  assert.equal(fixture.cid, cid(fixture.body));
  assert.equal(cid(record.prior_runtime_wire), 'sha256:585e5959c972a801335103217d2dede6cb12f72333a58f6b88bf88c85075fd85');
  const prior = JSON.parse(record.prior_runtime_wire);
  const current = JSON.parse(record.current_package_identity_wire);
  assert.equal(prior.sourceSha, 'a3b1643fbedc5180db38b6e08459a188f05b1135');
  assert.equal(current.source_sha, 'b'.repeat(40));
  assert.notEqual(current.source_sha, prior.sourceSha);
  assert.equal(record.original_upgrade_cid, 'sha256:8210e07a447b79db5057fcf92a7d39fa583519a1e52fc631360cf3f8e7a542f9');
});

test('successor closed shape rejects every missing/null field and invalid identity/operation bounds', () => {
  for (const key of schema.required) {
    const missing = {...record}; delete missing[key];
    assert.equal(valid(schema, missing), false);
    assert.equal(valid(schema, {...record, [key]: null}), false);
  }
  for (const key of ['account_configuration_cid', 'adoption_cid', 'authority_scope_cid', 'original_upgrade_cid']) {
    for (const value of ['copied', `sha256:${'A'.repeat(64)}`, `sha256:${'a'.repeat(63)}`]) {
      assert.equal(valid(schema, {...record, [key]: value}), false);
    }
  }
  for (const key of ['original_upgrade_packet_sha256', 'prior_pair_sha256']) {
    assert.equal(valid(schema, {...record, [key]: `sha256:${'a'.repeat(64)}`}), false);
  }
  for (const value of ['', '\0', 'x'.repeat(129)]) assert.equal(valid(schema, {...record, operation_id: value}), false);
  for (const key of ['current_package_identity_wire', 'prior_runtime_wire', 'successor_runtime_pair_wire']) {
    for (const value of ['', 'x'.repeat(4097), true]) assert.equal(valid(schema, {...record, [key]: value}), false);
  }
  assert.equal(valid(schema, {...record, version: 'actql-local-runtime-policy-upgrade/0.1'}), false);
  assert.equal(valid(schema, {...record, grant: true}), false);
});

test('independent framing/count bounds remain storage sizing rather than current permission', () => {
  const maximum = {...record, operation_id: '\u0001'.repeat(128)};
  const encode = value => JSON.stringify(Object.fromEntries(Object.entries(value).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)));
  const packet = body => {
    const b64 = Buffer.from(body).toString('base64');
    // Length placeholder only; no HMAC/key is generated.
    return JSON.stringify({payload_head: b64.slice(0, 4096), payload_tail: b64.slice(4096), tag: '0'.repeat(64)});
  };
  assert.equal(encode(record), fixture.body);
  assert.equal(Buffer.byteLength(packet(fixture.body)), 5902);
  assert.equal(Buffer.byteLength(encode(maximum)), 5079);
  assert.equal(Buffer.byteLength(packet(encode(maximum))), 6882);
  assert.ok(5079 <= 5632 && 6882 <= 8192);
  assert.ok(2 <= Math.min(8, 7 + 1) && 2 * 8192 <= 65536);
  assert.equal(6 <= Math.min(8, 4 + 1), false);
  assert.equal(9 <= Math.min(8, 7 + 1), false);
  // Structural Unicode length is not the Owner's UTF16/UTF8 resource bound.
  const astral = {...record, operation_id: '😀'.repeat(65)};
  assert.equal(valid(schema, astral), true);
  assert.equal(astral.operation_id.length <= 128, false);
});
