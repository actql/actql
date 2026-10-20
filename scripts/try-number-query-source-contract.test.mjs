import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort()
    .map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}' : JSON.stringify(value);
const hash = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
const prior = read('scripts/fixtures/try-number-query-source/predecessor.json');
const vector = read('scripts/fixtures/try-number-query-source/identities.json');

test('TRY_NUMBER query rules preserve their full predecessor and all existing machine bodies', () => {
  assert.deepEqual(vector.before, prior.grammar);
  assert.equal(vector.before.grammar_manifest_cid, 'sha256:6478ebc4ffe1e551c3afa978d18a615e884d368a51ef16f50ffe2c7e83abd5ce');
  assert.equal(hash(prior.query_rules).slice(7), vector.before.query_text_rules_sha256);
  for (const grammar of [vector.before, vector.after]) {
    const {grammar_manifest_cid, ...body} = grammar;
    assert.equal(hash(canonical(body)), grammar_manifest_cid);
  }
  assert.deepEqual(read('spec/manifests/actql-grammar-0.1.json'), vector.after);
  assert.deepEqual({...vector.after, grammar_manifest_cid: vector.before.grammar_manifest_cid,
    query_text_rules_sha256: vector.before.query_text_rules_sha256,
    expression_contract_cid: vector.before.expression_contract_cid}, vector.before);
  const current = readFileSync('docs/spec/query-text.md', 'utf8');
  const start = current.indexOf('`TRY_NUMBER(value)` takes exactly one original operand');
  const end = current.indexOf('`CONTAINS(value, part)` selects ActQL', start);
  assert.ok(start >= 0 && end > start);
  assert.equal(current.slice(0, start) + current.slice(end), prior.query_rules);
  assert.equal(hash(current).slice(7), vector.after.query_text_rules_sha256);
});

test('TRY_NUMBER expectations retain complete independent closed expression preimages', () => {
  assert.equal(vector.expressions.length, 4);
  for (const record of vector.expressions) {
    assert.equal(canonical(record.value), record.preimage);
    assert.equal(hash(record.preimage), record.cid);
    assert.deepEqual(Object.keys(record.value), ['try_number']);
    assert.deepEqual(Object.keys(record.value.try_number), ['value']);
  }
  assert.equal(hash(canonical(read('spec/contracts/actql-expressions.json'))), vector.after.expression_contract_cid);
  const program = read('spec/contracts/actql-protocol-schemas.json').artifact_schemas
    .executable_plan.properties.execution_material.properties.program;
  assert.equal(hash(canonical(program)), vector.before.source_grammar_cid);
});
