import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {verifyIdentity} from './check-canonical-json.mjs';
import {admitNoInputIntent, checkCallerInputIntentSchema,
  noInputBody, noInputCid} from './caller-input-intent-contract.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));

test('fixed caller input intent has an independent canonical vector', () => {
  const corpus = read('portability/corpus/caller-input-intent.json');
  assert.equal(corpus.version, 'actql-caller-input-intent-vectors/0.1');
  assert.equal(corpus.cases.length, 1);
  const fixture = corpus.cases[0];
  verifyIdentity(fixture.body, fixture.expected_cid,
    fixture.expected_canonical_bytes);
  assert.equal(admitNoInputIntent(fixture.body, fixture.expected_cid),
    noInputCid);
  assert.deepEqual(fixture.body, noInputBody);
  assert.throws(() => admitNoInputIntent(
    {version: noInputBody.version, selection: 'explicit', inputs: []},
    fixture.expected_cid));
  assert.throws(() => admitNoInputIntent(fixture.body,
    `sha256:${'0'.repeat(64)}`));
});

test('caller input intent schema and registry retain their pins', () => {
  checkCallerInputIntentSchema(read('spec/contracts/actql-protocol-schemas.json'));
});
