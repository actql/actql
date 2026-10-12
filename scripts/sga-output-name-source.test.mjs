import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {sgaOutputNameSuccesses, sgaOutputNameRefusals} from './fixtures/sga-output-name-source.mjs';

test('quoted OutputName source and independent JSON preserve ordinary identity projection', () => {
  const [json, source] = sgaOutputNameSuccesses;
  const steps = JSON.parse(json.text).stages[0].steps;
  assert.deepEqual(steps[2].match_nodes.bindings, {identity: 'SELECT'});
  assert.deepEqual(steps[2].match_nodes.fields, ['node_key', 'SELECT']);
  assert.deepEqual(steps[3].derive, {bound: {not: {is_null: {field: 'SELECT'}}}});
  assert.deepEqual(source.results, json.results);
  assert.deepEqual(source.results.matched, {rows: [{node_key: 1, bound: true}, {node_key: 2, bound: true}],
    columns: [{name: 'node_key', contract: {type: 'number', nullable: false}},
      {name: 'bound', contract: {type: 'boolean', nullable: false}}]});
  assert.ok(source.text.includes('bindings: {identity: `SELECT`}'));
  assert.ok(source.text.includes('`SELECT` IS NOT NULL AS bound'));
});

test('reserved unquoted OutputNames are rejected without changing original Graph values or guards', () => {
  const source = sgaOutputNameSuccesses[1];
  for (const [entry, value] of sgaOutputNameRefusals.map((entry, i) => [entry, ['SELECT', 'null'][i]])) {
    assert.equal(entry.text, source.text.replace('identity: `SELECT`', 'identity: ' + value));
    assert.equal(entry.expectedCode, 'ClientProgramInvalidInput');
    assert.equal(entry.sourceReadCount, 0);
  }
  assert.ok(sgaOutputNameSuccesses.every(c => c.sourceReadCount === 0));
});

test('supplemental OutputName controls are registered in the existing Graph MATCH cohort', () => {
  const source = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  assert.ok(source.includes("from './sga-output-name-source.mjs'"));
  assert.ok(source.includes('...sgaOutputNameSuccesses'));
  assert.ok(source.includes('...sgaOutputNameRefusals'));
});
