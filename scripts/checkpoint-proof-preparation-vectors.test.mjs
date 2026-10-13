// Fixed expectations are from Python JSON/hashlib, never product output.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import test from 'node:test';
const fixture = JSON.parse(readFileSync(new URL('../portability/corpus/checkpoint-resolution-proof-preparation.json', import.meta.url)));
const sorted = value => Array.isArray(value) ? value.map(sorted) : value !== null && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, sorted(value[key])])) : value;
const canonical = value => JSON.stringify(sorted(value));
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const without = (value, ...names) => Object.fromEntries(Object.entries(value).filter(([key]) => !names.includes(key)));

test('independent fixed Checkpoint and unsigned preimage identities', () => {
  assert.equal(fixture.checkpoint.checkpoint_cid, cid(without(fixture.checkpoint, 'checkpoint_cid')));
  assert.equal(fixture.expected_preimage, cid(fixture.unsigned));
  assert.deepEqual(fixture.checkpoint.subject, {kind: 'run_unit', run_id: 'proof-run', unit_id: 'proof-unit', continuation: 'resume_unit'});
  assert.equal(fixture.unsigned.checkpoint_cid, fixture.checkpoint.checkpoint_cid);
  assert.equal(fixture.unsigned.run_id, fixture.checkpoint.run_id);
  assert.equal(fixture.unsigned.run_definition_cid, fixture.checkpoint.run_definition_cid);
  assert.equal(fixture.unsigned.required_artifact_cid, fixture.checkpoint.required_artifact.artifact_cid);
  assert.equal(fixture.unsigned.review_projection_cid, fixture.checkpoint.review_projection_cid);
  assert.equal('proof' in fixture.unsigned, false);
  assert.equal('resolution_cid' in fixture.unsigned, false);
});

test('fixed proof attachment uses the existing domains and exact 64 encoding bytes only', () => {
  assert.deepEqual(without(fixture.emitted, 'proof', 'resolution_cid'), fixture.unsigned);
  assert.equal(fixture.emitted.resolution_cid, cid(without(fixture.emitted, 'resolution_cid')));
  assert.equal(fixture.emitted.version, 'actql-checkpoint-resolution/0.1');
  assert.deepEqual(fixture.emitted.proof, {scheme: 'ed25519-v1', key_id: fixture.key_id, signature: fixture.signature});
  assert.equal(Buffer.from(fixture.signature, 'base64').length, 64);
  assert.equal(Buffer.from(fixture.signature, 'base64').toString('base64'), fixture.signature);
  assert.notEqual(fixture.emitted.resolution_cid, fixture.expected_preimage);
});

test('Moon fixed inputs and expectations are the independent corpus bytes', () => {
  const source = readFileSync(new URL('../src/checkpoint_runtime/resolution_proof_preparation_wbtest.mbt', import.meta.url), 'utf8');
  for (const [name, value] of [['checkpoint', fixture.checkpoint], ['unsigned', fixture.unsigned], ['emitted', fixture.emitted]]) {
    const match = source.match(new RegExp('let proof_preparation_' + name + '_wire : String =\\s*#\\|([^\\n]+)'));
    assert.ok(match, name);
    assert.equal(match[1], canonical(value));
  }
  assert.ok(source.includes('"' + fixture.expected_preimage + '"'));
  assert.notEqual(cid({...fixture.unsigned, run_id: 'foreign-run'}), fixture.expected_preimage);
});
