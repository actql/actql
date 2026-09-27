import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {programs} from './document-validation.mjs';
import {structuralToJson, jsonToStructural, jsonAdmissionDiagnostic} from
  '../_build/js/debug/build/aql_text_test_bridge/aql_text_test_bridge.js';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('imported structural orders fixture equals the independent canonical Program', () => {
  const text = read('spec/frontend/fixtures/orders.structural.aql');
  const expected = JSON.parse(read('spec/frontend/fixtures/orders.canonical.json'));
  assert.deepEqual(JSON.parse(structuralToJson(text)), expected);
  const formatted = jsonToStructural(JSON.stringify(expected));
  assert.deepEqual(JSON.parse(structuralToJson(formatted)), expected);
  assert.equal(jsonToStructural(structuralToJson(formatted)), formatted);
});

test('hand-authored native Values fixture matches the ordinary Client fixture', () => {
  assert.deepEqual(JSON.parse(structuralToJson(
    read('spec/frontend/fixtures/client-values.structural.aql'))),
  JSON.parse(read('packages/sdk/fixtures/values.json')));
});

// This matrix tests closed spelling and lossless bodies, not operator typing or
// execution. Real Program checking/execution is exercised separately.
const inventory = JSON.parse(read('spec/manifests/actql-grammar-0.1.json')).operations;
const generators = new Set(['values', 'graph', 'mean_graphs', 'calendar_series', 'time_series']);
for (const operation of inventory) {
  test(`STEP and OP retain the complete body for registered spelling ${operation}`, () => {
    const body = {probe: ['concat(null, "x")', null, 3, {literal: {meta: 'data'}}]};
    if (operation === 'graph') {
      body.nodes = {from: 'input'};
      body.edges = {from: 'input'};
    }
    const input = {carrier: 'relation', schema: {x: {type: 'number', nullable: false}}};
    const step = {...(generators.has(operation) ? {} : {from: 'input'}),
      [operation]: body, as: 'output'};
    const expected = {version: 'actql/0.1', id: 'inventory', stages: [{
      id: 's', inputs: {input}, steps: [step], results: {r: {from: 'output'}},
    }], results: {r: {from: {stage: 's', result: 'r'}}}};
    const source = `AQL '0.1'; PROGRAM 'inventory' { STAGE s {
      INPUT 'input' = ${JSON.stringify(input)};
      DATA output = ${generators.has(operation) ? '' : "FROM 'input' |> "}
        OP ${operation} ${JSON.stringify(body)};
      RESULT r = {"from":"output"};
      } RESULT r = {"from":{"stage":"s","result":"r"}}; }`;
    assert.deepEqual(JSON.parse(structuralToJson(source)), expected);
    assert.deepEqual(JSON.parse(structuralToJson(
      jsonToStructural(JSON.stringify(expected)))), expected);
  });
}

for (const document of JSON.parse(read('spec/actql-doc-examples.json')).documents) {
  const fixtures = new Map(programs(read(document.path), document.path)
    .map(program => [program.id, program]));
  for (const entry of document.programs.filter(value => value.expected_status === 'valid')) {
    test(`structural roundtrip preserves documented Program ${document.path}#${entry.id}`, () => {
      const expected = fixtures.get(entry.id);
      assert.ok(expected);
      const text = jsonToStructural(JSON.stringify(expected));
      assert.notEqual(text, '', 'existing Program must pass ordinary source admission');
      assert.deepEqual(JSON.parse(structuralToJson(text)), expected);
      assert.equal(jsonToStructural(structuralToJson(text)), text);
    });
  }
}

test('explicit no-ops, unused fixed windows, composite defaults and metadata survive', () => {
  const expected = JSON.parse(read('packages/sdk/fixtures/values.json'));
  expected.meta = {tag: 'root'};
  expected.params = {config: {type: 'object', nullable: false,
    fields: {items: {type: 'array', nullable: false, items: {type: 'number', nullable: true}}},
    default: {items: [null, 3, 1]}}};
  expected.bindings = {opaque: {kind: 'resource', resource_kind: 'table'}};
  const stage = expected.stages[0];
  stage.meta = {tag: 'stage'};
  stage.inputs.original = {carrier: 'relation',
    schema: {id: {type: 'number', nullable: false}}, meta: {tag: 'input'}};
  stage.steps[0].meta = {tag: 'step'};
  stage.steps.push({sort: []}, {rename: {}}, {drop: []},
    {row_window: {kind: 'fixed', time: 'id', size: 10, step: 3}, as: 'unused'});
  stage.results.rows.meta = {tag: 'local-result'};
  stage.effects = {second: {kind: 'mapping', source: {result: 'rows'},
    contract_ref: 'second', failure_policy: 'stop', meta: {tag: 'effect'}},
  first: {kind: 'mapping', source: {result: 'rows'},
    contract_ref: 'first', failure_policy: 'stop'}};
  const formatted = jsonToStructural(JSON.stringify(expected));
  assert.notEqual(formatted, '', jsonAdmissionDiagnostic(JSON.stringify(expected)));
  assert.deepEqual(JSON.parse(structuralToJson(formatted)), expected);
  const reversed = structuredClone(expected);
  reversed.stages[0].effects = Object.fromEntries(
    Object.entries(reversed.stages[0].effects).reverse());
  assert.deepEqual(JSON.parse(structuralToJson(jsonToStructural(
    JSON.stringify(reversed)))), expected);
});

test('native ranking peer lists and score policies retain authored order', () => {
  const policies = [
    {score_policy: 'max', score_contract: {domain: 'relevance', range: [0, 1], normalization: 'identity'}},
    {score_policy: {rrf: {rank: 'rank', c: 60}}},
  ];
  for (const policy of policies) {
    const body = {with: ['third', 'second', 'third'], by: ['query_id'],
      candidate: 'candidate_id', score: 'score', k: 5, ...policy};
    const text = `AQL '0.1'; PROGRAM 'rank' { STAGE s {
      INPUT first = {}; INPUT second = {}; INPUT third = {};
      DATA merged = FROM first |> OP merge_rankings ${JSON.stringify(body)};
      RESULT r = {"from":"merged"};
      } RESULT r = {"from":{"stage":"s","result":"r"}}; }`;
    const program = JSON.parse(structuralToJson(text));
    assert.deepEqual(program.stages[0].steps,
      [{from: 'first', merge_rankings: body, as: 'merged'}]);
    assert.deepEqual(JSON.parse(structuralToJson(jsonToStructural(
      JSON.stringify(program)))), program);
  }
});
