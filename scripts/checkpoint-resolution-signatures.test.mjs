import assert from 'node:assert/strict';
import test from 'node:test';
import {createPublicKey, verify} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {verifyIdentity} from './check-canonical-json.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const corpus = read('portability/corpus/checkpoint-resolution-signatures.json');
const registry = read('spec/contracts/actql-protocol-schemas.json');

// Ed25519 SubjectPublicKeyInfo DER prefix for a raw 32-byte public key (RFC 8410).
const spki = raw => createPublicKey({
  key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), Buffer.from(raw, 'base64')]),
  format: 'der', type: 'spki',
});
const without = (value, ...fields) =>
  Object.fromEntries(Object.entries(value).filter(([key]) => !fields.includes(key)));
const signatureOf = (artifact, field) => artifact[field].signature;
const verifies = (key, text, signature) =>
  verify(null, Buffer.from(text, 'utf8'), key, Buffer.from(signature, 'base64'));

test('signature vectors use the registered closed artifact fields', () => {
  assert.equal(corpus.version, 'actql-checkpoint-resolution-signature-vectors/0.1');
  for (const c of corpus.cases) {
    const schema = registry.artifact_schemas[c.kind];
    assert.ok(schema, c.id);
    assert.deepEqual(Object.keys(c.artifact).sort(),
      Object.keys(c.artifact).filter(key => Object.hasOwn(schema.properties, key)).sort(), c.id);
    for (const key of schema.required) assert.ok(Object.hasOwn(c.artifact, key), `${c.id}: ${key}`);
    assert.equal(c.artifact.version, schema.properties.version.const, c.id);
  }
});

test('self CIDs include the signature and signatures cover the unsigned CID text', () => {
  for (const c of corpus.cases) {
    const key = spki(corpus.public_keys[c.key]);
    const unsigned = without(c.artifact, c.self_field, c.signature_field);
    verifyIdentity(unsigned, c.expected_unsigned_cid);
    verifyIdentity(without(c.artifact, c.self_field), c.expected_self_cid);
    assert.equal(c.artifact[c.self_field], c.expected_self_cid, c.id);
    const signature = signatureOf(c.artifact, c.signature_field);
    assert.ok(verifies(key, c.expected_unsigned_cid, signature), c.id);
    // The preimage is exactly the unsigned CID text: neither the self CID, the
    // canonical body bytes nor the other party's key verifies the signature.
    assert.equal(verifies(key, c.expected_self_cid, signature), false, c.id);
    assert.equal(verifies(key, c.expected_unsigned_cid.slice('sha256:'.length), signature), false, c.id);
    const other = spki(corpus.public_keys[c.key === 'host' ? 'reviewer' : 'host']);
    assert.equal(verifies(other, c.expected_unsigned_cid, signature), false, c.id);
  }
});

test('a verified wrapper embeds the exact signed Resolution', () => {
  const byId = new Map(corpus.cases.map(c => [c.id, c]));
  const wrapper = byId.get('verified-rejected-resolution').artifact;
  const resolution = byId.get('rejected-resolution').artifact;
  assert.deepEqual(wrapper.resolution, resolution);
  assert.equal(wrapper.authorization_evidence.resolution_cid, resolution.resolution_cid);
  assert.equal(wrapper.authorization_evidence.checkpoint_cid, resolution.checkpoint_cid);
  verifyIdentity(wrapper.authorization_evidence, wrapper.authorization_evidence_cid);
});
