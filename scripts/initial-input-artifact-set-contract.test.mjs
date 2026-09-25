import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {verifyIdentity} from './check-canonical-json.mjs';
import {admitEmptyInitialInputSet, checkInitialInputArtifactSetSchema,
  emptyInitialInputSetBody, emptyInitialInputSetCid} from
  './initial-input-artifact-set-contract.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));

test('initial empty input set has an independent canonical vector', () => {
  const corpus = read('portability/corpus/initial-input-artifact-set.json');
  assert.equal(corpus.version,
    'actql-initial-input-artifact-set-vectors/0.1');
  assert.equal(corpus.cases.length, 1);
  const fixture = corpus.cases[0];
  verifyIdentity(fixture.body, fixture.expected_cid,
    fixture.expected_canonical_bytes);
  assert.equal(admitEmptyInitialInputSet(fixture.body,
    fixture.expected_cid), emptyInitialInputSetCid);
  assert.deepEqual(fixture.body, emptyInitialInputSetBody);
  assert.throws(() => admitEmptyInitialInputSet({
    version: emptyInitialInputSetBody.version,
    captured_artifact_cids: [`sha256:${'a'.repeat(64)}`],
  }, fixture.expected_cid));
  assert.throws(() => admitEmptyInitialInputSet(fixture.body,
    `sha256:${'0'.repeat(64)}`));
});

test('initial input set schema and registry retain their pins', () => {
  checkInitialInputArtifactSetSchema(
    read('spec/contracts/actql-protocol-schemas.json'));
});
