// Read-only oracle for independently authored Effect literal source identities.
// This deliberately imports no product encoder, parser or runtime, and never
// rewrites either these fixed vectors or the historical Stage/Program corpora.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const expressionContractCid =
  'sha256:800ab1eed12a3bcf98779493833081bc636c6ea108adbe1b57a57c01512b2f67';
const corpusUrl = new URL(
  '../portability/corpus/effect-literal-key-identities.json', import.meta.url);

// Test/oracle only. JSON keys sort by their exact UTF-16 code units. Writing
// each field directly also avoids JavaScript's numeric-key re-enumeration.
// No NFC or line-ending normalization is applied to keys or String values.
export function exactDataJson(value) {
  if (Array.isArray(value)) return `[${value.map(exactDataJson).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value).sort().map(key =>
      `${JSON.stringify(key)}:${exactDataJson(value[key])}`).join(',')}}`;
  }
  assert.ok(value === null || ['string', 'boolean', 'number'].includes(typeof value),
    'the independent fixture oracle accepts JSON values only');
  if (typeof value === 'number') assert.ok(Number.isFinite(value));
  return JSON.stringify(value);
}

const hash = preimage => `sha256:${createHash('sha256')
  .update(preimage, 'utf8').digest('hex')}`;

// Independently named payloads prevent an internally consistent accidental
// rewrite of both a fixture and its digest from removing the intended cases.
const authoredPayloads = JSON.parse(String.raw`[
  ["ascii-key", {"key": 1}],
  ["nfc-key", {"\u00e9": 1}],
  ["nfd-key", {"e\u0301": 1}],
  ["lf-key", {"line\nkey": 1}],
  ["cr-key", {"line\rkey": 1}],
  ["crlf-key", {"line\r\nkey": 1}],
  ["paired-keys", {"\u00e9": 1, "e\u0301": 2,
    "line\nkey": 3, "line\rkey": 4, "line\r\nkey": 5}],
  ["paired-keys-reordered", {"line\r\nkey": 5, "line\rkey": 4,
    "line\nkey": 3, "e\u0301": 2, "\u00e9": 1}],
  ["nested-array-json", {"nested": [
    {"$json": {"\u00e9": 1, "e\u0301": 2,
      "line\nkey": 3, "line\rkey": 4, "line\r\nkey": 5}},
    {"": ["unchanged", {"__proto__": {"constructor": "data"}}]},
    {"10": "ten", "2": "two", "\ud83d\ude00": 1, "\ue000": 2}
  ]}],
  ["null", null]
]`);

function stageEnvelope(payload) {
  // Source projection retains this authored Values schema; it does not add
  // typed-target defaults, a Stage id or an absent Stage-level `from` field.
  return {
    version: 'actql-stage-semantics/0.1',
    expression_contract_cid: expressionContractCid,
    parameters: {}, parameter_references: [],
    bindings: {}, binding_references: [],
    local_body: {
      inputs: {},
      steps: [{values: {
        schema: {id: {type: 'string', nullable: false}},
        rows: [{id: 'record-1'}],
      }, as: 'selected'}],
      results: {rows: {from: 'selected', fields: ['id']}},
      effects: {save: {update: {
        target: 'connector://fixture/records',
        mapping: 'mapping:fixture.records.json.v1',
        from: {result: 'rows'}, id: 'id',
        set: {payload: {literal: payload}},
      }}},
    },
  };
}

function programEnvelope(stageCid) {
  return {
    version: 'actql-program-semantics/0.1', actql_version: 'actql/0.1',
    expression_contract_cid: expressionContractCid,
    parameters: {}, parameter_references: [],
    bindings: {}, binding_references: [],
    program_template: {
      stages: [{id: 'source', after: 'initial', imports: {},
        stage_semantics_cid: stageCid}],
      exports: {answer: {from: {stage: 'source', result: 'rows'}}},
    },
  };
}

function checkEnvelope(envelope, expected, preimage, cid, label) {
  assert.deepEqual(envelope, expected, `${label}: authored envelope`);
  assert.equal(exactDataJson(envelope), preimage, `${label}: exact UTF-8 preimage`);
  assert.match(cid, /^sha256:[a-f0-9]{64}$/, `${label}: CID syntax`);
  assert.equal(hash(preimage), cid, `${label}: fixed SHA-256 digest`);
}

export function checkEffectLiteralKeyVectors(corpus = JSON.parse(
  readFileSync(corpusUrl, 'utf8'))) {
  assert.equal(corpus.version, 'actql-effect-literal-key-identities/0.1');
  assert.equal(corpus.expression_contract_cid, expressionContractCid);
  assert.deepEqual(corpus.cases.map(c => c.name),
    authoredPayloads.map(([name]) => name));
  for (const [index, c] of corpus.cases.entries()) {
    assert.deepEqual(c.payload, authoredPayloads[index][1], `${c.name}: payload`);
    assert.equal(exactDataJson(c.payload), c.payload_preimage,
      `${c.name}: exact payload bytes`);
    checkEnvelope(c.stage_envelope, stageEnvelope(c.payload),
      c.stage_preimage, c.expected_stage_cid, `${c.name}: Stage semantics`);
    checkEnvelope(c.program_envelope, programEnvelope(c.expected_stage_cid),
      c.program_preimage, c.expected_program_cid, `${c.name}: Program semantics`);
    checkEnvelope(c.definition_envelope, {
      version: 'actql-program-definition/0.1', id: 'installed-json-update',
      program_semantics_cid: c.expected_program_cid,
    }, c.definition_preimage, c.expected_definition_cid,
    `${c.name}: Program Definition`);
  }
  const cases = new Map(corpus.cases.map(c => [c.name, c]));
  const paired = cases.get('paired-keys');
  const reordered = cases.get('paired-keys-reordered');
  assert.deepEqual(Object.keys(reordered.payload), Object.keys(paired.payload).reverse(),
    'the paired-key fixture must actually reorder authored members');
  for (const key of ['stage', 'program', 'definition']) {
    const cid = `expected_${key}_cid`;
    assert.equal(paired[cid], reordered[cid], `${key}: key order is identity-neutral`);
    const distinct = corpus.cases.filter(c => c.name !== 'paired-keys-reordered');
    assert.equal(new Set(distinct.map(c => c[cid])).size, distinct.length,
      `${key}: distinct exact literal payloads must retain distinct identities`);
  }
  return corpus.cases.length;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 2, 'this fixed-vector checker is read-only');
  const count = checkEffectLiteralKeyVectors();
  console.log(`${count} independent raw Effect literal Stage/Program identities verified.`);
}
