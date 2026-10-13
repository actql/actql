import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {capturedMediaEvidenceSchema, applyCapturedMediaEvidenceSchema} from './content-media-evidence-schema.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const canonical = value => value !== null && typeof value === 'object'
  ? Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
    : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
  : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const withoutIdentity = (value, key) => { const body = {...value}; delete body[key]; return cid(body); };
const current = read('spec/contracts/actql-protocol-schemas.json');
const predecessor = JSON.parse(execFileSync('git', ['show',
  '389448adbcd33ffa8d5831d97a50529095a8cdb6:spec/contracts/actql-protocol-schemas.json'],
{encoding: 'utf8', maxBuffer: 8 * 1024 * 1024}));
const original = predecessor.schemas
  .content_ref.properties.metadata.properties.issuer_evidence;

test('captured report schema contribution is closed, immutable and idempotent without repinning', () => {
  const before = structuredClone(original);
  const schema = capturedMediaEvidenceSchema(original);
  assert.deepEqual(original, before);
  assert.deepEqual(capturedMediaEvidenceSchema(schema), schema);
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required, original.required);
  assert.deepEqual(schema.properties.reported_media_type,
    {type: 'string', minLength: 1, maxLength: 256});
  assert.deepEqual(schema.allOf, [{
    if: {properties: {issuer_kind: {const: 'connector_capture'}}, required: ['issuer_kind']},
    then: {required: ['reported_media_type']},
    else: {not: {required: ['reported_media_type']}},
  }]);
  assert.notEqual(cid(schema), cid(original));
  assert.deepEqual(current.schemas.content_ref.properties.metadata.properties.issuer_evidence, schema);
  assert.throws(() => capturedMediaEvidenceSchema({...original, allOf: [{}]}));
});

test('current Ref and captured embedding use the same schema and independent current pins', () => {
  assert.deepEqual(applyCapturedMediaEvidenceSchema(current), current);
  assert.equal(current.schema_cids.content_ref, cid(current.schemas.content_ref));
  assert.equal(current.registry_cid, cid(current.schemas));
  assert.equal(current.artifact_registry_cid, cid(current.artifact_schemas));
  for (const [name, body] of Object.entries(current.artifact_schemas)) {
    assert.equal(current.artifact_schema_cids[name], cid(body));
  }
  assert.deepEqual(current.artifact_schemas.captured_run.properties.effect_context.properties
    .content_generations.items.properties.content_reference, current.schemas.content_ref);
  assert.notEqual(current.schema_cids.content_ref, predecessor.schema_cids.content_ref);
  assert.deepEqual(current.schemas.resource_ref, predecessor.schemas.resource_ref);
  assert.deepEqual(current.schemas.canonical_value_contract, predecessor.schemas.canonical_value_contract);
});

test('independent captured report vectors bind exact report while content byte identity stays unchanged', () => {
  const {vectors} = read('portability/corpus/content-mime-report-identities.json');
  assert.equal(vectors.length, 4);
  for (const vector of vectors) {
    const ref = JSON.parse(vector.wire), evidence = ref.metadata.issuer_evidence;
    assert.equal(vector.wire, canonical(ref));
    assert.equal(ref.media_type, vector.media);
    assert.equal(evidence.reported_media_type, vector.reported);
    assert.equal(withoutIdentity(evidence, 'evidence_cid'), vector.issuer);
    assert.equal(evidence.evidence_cid, vector.issuer);
    assert.equal(withoutIdentity(ref, 'content_ref_cid'), vector.ref);
    assert.equal(ref.content_ref_cid, vector.ref);
    assert.equal(ref.metadata.content_cid,
      'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  }
  assert.equal(vectors[0].media, vectors[1].media);
  assert.notEqual(vectors[0].ref, vectors[1].ref);
  assert.notEqual(vectors[2].ref, vectors[3].ref, 'no NFC equivalence for data');
});

test('actual predecessor capture identities remain fixed without report repair or relabeling', () => {
  const legacy = read('portability/corpus/historical/pre-reported-content-mime.json');
  assert.equal(legacy.source, '389448adbcd33ffa8d5831d97a50529095a8cdb6');
  const originalSource = execFileSync('git', ['show', `${legacy.source}:${legacy.originalSource}`],
    {encoding: 'utf8'});
  assert.ok(originalSource.includes(legacy.ref));
  assert.ok(originalSource.includes(legacy.issuer));
  const ref = JSON.parse(legacy.wire), evidence = ref.metadata.issuer_evidence;
  assert.equal(withoutIdentity(evidence, 'evidence_cid'), legacy.issuer);
  assert.equal(withoutIdentity(ref, 'content_ref_cid'), legacy.ref);
  assert.equal(Object.hasOwn(evidence, 'reported_media_type'), false);
  assert.equal(legacy.ref,
    'sha256:2dfff07c2e376252233bf4a15fa5c1277c255adc2ec6c946a6e70d9206c71716');
  assert.equal(legacy.issuer,
    'sha256:3262be0c7204cd24b97fc4e3a322a51916435887dde89dc873017202a7379771');
});
