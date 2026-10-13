// Independent public identity expectations; no Engine, key, grant or signing use.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import test from 'node:test';
const load = name => JSON.parse(readFileSync(new URL('../spec/contracts/' + name, import.meta.url)));
const pins = load('fixtures/local-signing-public-key-pins.json');
const vectors = load('fixtures/local-signing-public-key-vectors.json').vectors;
const schema = load('actql-local-signing-public-key.schema.json');
const digest = value => 'sha256:' + createHash('sha256').update(value).digest('hex');

test('independent authored bytes reproduce exact Common identity bodies and CIDs', () => {
  assert.equal(pins.identity_domain, 'actql-local-signing-public-key/0.1');
  assert.equal(pins.schema_urn, schema.$id);
  for (const pin of pins.files) {
    assert.equal(createHash('sha256').update(readFileSync(new URL('../' + pin.path, import.meta.url))).digest('hex'), pin.sha256);
  }
  for (const value of vectors) {
    const raw = Buffer.from(value.raw32_hex, 'hex');
    assert.equal(raw.length, 32);
    assert.equal(raw.toString('base64'), value.body.public_key);
    const body = JSON.stringify({ algorithm: 'ed25519', public_key: raw.toString('base64'),
      version: 'actql-local-signing-public-key/0.1' });
    assert.equal(body, value.wire);
    assert.equal(digest(body), value.cid);
  }
  assert.notEqual(vectors[0].cid, vectors[1].cid);
});

test('adopted schema encodes exact standard padded base64, not permission fields', () => {
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required, ['algorithm', 'public_key', 'version']);
  assert.equal(schema.properties.algorithm.const, 'ed25519');
  assert.equal(schema.properties.version.const, 'actql-local-signing-public-key/0.1');
  const spelling = new RegExp(schema.properties.public_key.pattern, 'u');
  for (const value of vectors) assert.equal(spelling.test(value.body.public_key), true);
  for (const encoded of [vectors[0].body.public_key.slice(0, -1),
    vectors[0].body.public_key.slice(0, -2) + '9=',
    vectors[1].body.public_key.replace('/', '_'),
    'A'.repeat(42) + '==', '!'.repeat(44)]) assert.equal(spelling.test(encoded), false);
  for (const field of ['host', 'issuer', 'purpose', 'permission', 'key_generation_cid', 'signature']) {
    assert.equal(Object.hasOwn(schema.properties, field), false);
  }
});

test('different independent public PEM layouts contain the same authored bytes', () => {
  // Fixed SPKI framing for this authored Ed25519 public vector; no private key.
  const raw = Buffer.from(vectors[1].raw32_hex, 'hex');
  const encoded = Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), raw]).toString('base64');
  const pem = width => '-----BEGIN PUBLIC KEY-----\n' +
    encoded.match(new RegExp('.{1,' + width + '}', 'gu')).join('\n') + '\n-----END PUBLIC KEY-----\n';
  const publicBytes = wire => {
    const der = Buffer.from(wire.replace(/-----[^-]+-----|\s+/gu, ''), 'base64');
    assert.equal(der.subarray(0, 12).toString('hex'), '302a300506032b6570032100');
    assert.equal(der.length, 44);
    return der.subarray(12);
  };
  assert.notEqual(pem(32), pem(64));
  assert.deepEqual(publicBytes(pem(32)), raw);
  assert.deepEqual(publicBytes(pem(64)), raw);
  assert.equal(digest(vectors[1].wire), vectors[1].cid);
});

test('new identity preserves existing grant/use schemas or historical independent vectors', () => {
  const files = ['spec/contracts/actql-local-signing-credential-grant.schema.json',
    'spec/contracts/actql-local-signing-credential-use.schema.json',
    'spec/contracts/fixtures/local-signing-credential-vectors.json',
    'src/remote_credential/local_signing_scope.mbt'];
  for (const path of files) {
    assert.deepEqual(readFileSync(path), execFileSync('git', ['show',
      '97828fc4d42b2fd7a30acaaff679df3ec1f95111:' + path]));
  }
});
