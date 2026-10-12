import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {machineCid} from './actql-spec-family.mjs';
import {verifyIdentity} from './check-canonical-json.mjs';
import {modelJournalIdentitySchemas, applyModelJournalIdentitySchemas,
  checkModelJournalIdentitySchemas} from './model-journal-identity-contract.mjs';
import {checkJournalIdentityVectors, originalEntry, originalSettlement}
  from './model-journal-identity-vectors.mjs';

test('original journal data kinds preserve every preexisting schema and CID', () => {
  const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
  checkModelJournalIdentitySchemas(registry);
  const historical = structuredClone(registry);
  for (const name of Object.keys(modelJournalIdentitySchemas())) {
    delete historical.artifact_schemas[name];
    delete historical.artifact_schema_cids[name];
  }
  historical.artifact_registry_cid = machineCid(historical.artifact_schemas);
  // The adopted b1ea baseline, read from Git before adding either new kind.
  assert.equal(Object.keys(historical.artifact_schemas).length, 66);
  assert.equal(historical.artifact_registry_cid,
    'sha256:9e88251f3962de80e1d087223af05f8d34dd75eedc6b334dccd793f830f6eda1');
  assert.deepEqual(applyModelJournalIdentitySchemas(structuredClone(historical)), registry);
  for (const [name, schema] of Object.entries(historical.artifact_schemas)) {
    assert.equal(machineCid(schema), registry.artifact_schema_cids[name]);
  }
});

test('generated descriptor chunks share one array and retain original root numbering', () => {
  const source = readFileSync('src/run_publication/protocol_schema.generated.mbt', 'utf8');
  assert.equal([...source.matchAll(/Array\(capacity=/gu)].length, 1);
  assert.equal(source.includes('.concat('), false);
  assert.equal(source.includes('("model_original_resource_state", true) => Some(5984)'), true);
  const segments = source.split(/^\/\/\/\|$/gmu);
  assert(segments.every(segment => segment.split('\n').length < 16384));
  const capacity = Number(/Array\(capacity=(\d+)\)/u.exec(source)[1]);
  assert.equal([...source.matchAll(/nodes\.push\(/gu)].length, capacity);
});

test('original journal independent canonical vectors and generated consumer are fresh', () => {
  checkJournalIdentityVectors();
  const corpus = JSON.parse(readFileSync('portability/corpus/model-journal-identities.json', 'utf8'));
  assert.equal(corpus.cases.length, 6);
  assert.equal(corpus.invalid.length, 12);
  for (const fixture of corpus.cases) verifyIdentity(fixture.body,
    fixture.expected_cid, fixture.expected_canonical_bytes);
});

test('original journal data identity covers each original binding without a self cycle', () => {
  for (const [name, value] of Object.entries(originalEntry)) {
    if (typeof value === 'string') assert.notEqual(machineCid(originalEntry),
      machineCid({...originalEntry, [name]: value + '-changed'}), name);
    if (typeof value === 'number') assert.notEqual(machineCid(originalEntry),
      machineCid({...originalEntry, [name]: value + 1}), name);
  }
  assert.equal(originalEntry.immediate.parent_resume_fence, null);
  assert.equal(originalEntry.deferred, null);
  assert.equal(Object.hasOwn(originalEntry, 'holding_cid'), false);
  assert.equal(Object.hasOwn(originalEntry, 'self_cid'), false);
  assert.notEqual(machineCid(originalEntry), originalEntry.attempt_cid);
});

test('original journal values preserve Unicode, line endings and observed absence', () => {
  assert.notEqual(machineCid(originalEntry), machineCid({...originalEntry,
    run_id: originalEntry.run_id.normalize('NFC')}));
  assert.notEqual(machineCid(originalEntry), machineCid({...originalEntry,
    run_id: originalEntry.run_id.replaceAll('\r\n', '\n')}));
  const nullFact = {...originalSettlement, evidence: {...originalSettlement.evidence,
    terminal_failure: null}};
  const falseFact = {...originalSettlement, evidence: {...originalSettlement.evidence,
    terminal_failure: false}};
  assert.notEqual(machineCid(nullFact), machineCid(falseFact));
});
