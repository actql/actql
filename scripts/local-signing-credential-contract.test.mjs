import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {project, structuralValidatorSource} from './generate-client-publication-wire.mjs';

const load = name => JSON.parse(readFileSync(new URL('../' + name, import.meta.url)));
const vectors = load('spec/contracts/fixtures/local-signing-credential-vectors.json');
const grant = load('spec/contracts/actql-local-signing-credential-grant.schema.json');
const use = load('spec/contracts/actql-local-signing-credential-use.schema.json');
const pins = load('spec/contracts/fixtures/local-signing-credential-pins.json');
const digest = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
// Reuse the existing generated structural validator. Remove only nonsemantic
// root annotations unsupported by its projection. Canonical byte admission,
// current authority, private custody and durable claim remain separate layers.
const withoutAnnotations = ({description, $comment, ...schema}) => schema;
const shapes = new Map([grant, use].map(schema => [schema, project(withoutAnnotations(schema))]));
const valid = new Function(structuralValidatorSource({extended: true}) + '\nreturn valid;')();
const shape = (schema, value) => valid(value, shapes.get(schema));

test('signing schemas and independent vectors retain exact explicit pins', () => {
  for (const row of pins.files) {
    assert.equal(createHash('sha256').update(readFileSync(new URL('../' + row.path, import.meta.url))).digest('hex'), row.sha256);
  }
  for (const vector of vectors.vectors) {
    assert.equal(shape(grant, vector.body), true);
    assert.deepEqual(JSON.parse(vector.wire), vector.body);
    assert.equal(digest(vector.wire), vector.cid);
    assert.deepEqual(Object.keys(JSON.parse(vector.wire)), [...grant.required].sort());
  }
  for (const vector of vectors.useVectors) {
    assert.equal(shape(use, vector.body), true);
    assert.equal(digest(vector.wire), vector.cid);
    assert.equal(vector.body.grant_cid, vectors.vectors.find(row => row.purpose === vector.purpose).cid);
  }
});

test('closed purpose and original key fields distinguish independent role identities', () => {
  const [reviewer, host] = vectors.vectors;
  assert.notEqual(reviewer.cid, host.cid);
  for (const name of ['key_configuration_cid', 'key_generation_cid', 'key_public_key_cid', 'key_id', 'authority_scope_cid', 'principal', 'preimage']) {
    assert.notEqual(reviewer.body[name], host.body[name]);
  }
  assert.equal(shape(grant, {...reviewer.body, purpose: 'provider_sign'}), false);
  assert.equal(shape(grant, {...reviewer.body, request_method: 'GET'}), false);
  assert.equal(shape(grant, {...reviewer.body, resource_origin: 'https://example.test'}), false);
  assert.equal(shape(grant, {...reviewer.body, issuer_allow: true}), false);
});

test('all required original bindings refuse missing or invalid structural values', () => {
  const body = vectors.vectors[0].body;
  for (const name of grant.required) {
    const missing = {...body}; delete missing[name];
    assert.equal(shape(grant, missing), false, name);
    assert.equal(shape(grant, {...body, [name]: null}), false, name);
  }
  for (const name of grant.required.filter(name => name.endsWith('_cid') || name === 'preimage')) {
    assert.equal(shape(grant, {...body, [name]: 'copied-public-token'}), false, name);
  }
  for (const max_uses of [0, 1025, 1.5, '1']) assert.equal(shape(grant, {...body, max_uses}), false);
  assert.equal(shape(grant, {...body, checkpoint_kind: 'effect_commit'}), false);
  assert.equal(shape(grant, {...body, expires_unix_ms: '0'}), false);
});

test('signing checkpoint vocabulary follows the existing closed Checkpoint Owner', () => {
  const owner = readFileSync(new URL('../src/checkpoint_runtime/checkpoint.mbt', import.meta.url), 'utf8');
  const start = owner.indexOf('pub fn checkpoint_kind_token(');
  const end = owner.indexOf('\n///|', start);
  const tokens = [...owner.slice(start, end).matchAll(/=> "([a-z_]+)"/gu)].map(row => row[1]);
  assert.deepEqual(grant.properties.checkpoint_kind.enum, tokens);
});

test('use record preserves finite ordinal and original grant while excluding new authority', () => {
  const body = vectors.useVectors[0].body;
  for (const use_ordinal of [0, 1025, 1.5, '1']) assert.equal(shape(use, {...body, use_ordinal}), false);
  for (const name of use.required) {
    const missing = {...body}; delete missing[name];
    assert.equal(shape(use, missing), false);
  }
  assert.equal(shape(use, {...body, current_allowed: true}), false);
  assert.equal(shape(use, {...body, signature: 'not-a-signature'}), false);
});

test('original decomposed Unicode and CRLF remain identity-relevant literal data', () => {
  const original = vectors.vectors[0];
  assert.equal(original.body.principal, 'e\u0301\r\n');
  for (const principal of ['é\r\n', 'e\u0301\r', 'e\u0301\n']) {
    const changed = JSON.stringify(Object.fromEntries(Object.entries({...original.body, principal}).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)));
    assert.notEqual(digest(changed), original.cid);
  }
});
