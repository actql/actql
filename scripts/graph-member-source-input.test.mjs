import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {graphProjectionPropertySuccesses as successes,
  graphProjectionPropertyRefusals as refusals}
  from './fixtures/graph-projection-property-source-input.mjs';

test('Graph member source counterexamples retain independently authored rows and contracts', () => {
  const expected = [{id: 1, score: 20}, {id: 2, score: 10},
    {id: 3, score: null}, {id: 4, score: null}];
  const columns = [{name: 'id', contract: {type: 'number', nullable: false}},
    {name: 'score', contract: {type: 'number', nullable: true}}];
  for (const suffix of ['folded-qualified-member', 'folded-quoted-member',
    'folded-projected-receiver']) {
    const item = successes.find(value => value.name.endsWith(suffix));
    assert.ok(item, suffix);
    assert.deepEqual(item.results.matched, {rows: expected, columns});
    assert.equal(item.sourceReadCount, 0);
    assert.match(item.text, /GRAPH \(/);
    assert.match(item.text, /ORDER BY id \|> RESULT matched$/);
  }
  const control = JSON.parse(successes.find(item => item.format === 'json').text);
  assert.deepEqual(control.stages[0].steps[3].derive.score,
    {property: {name: 'score', value: {field: 'payload'}}});
});

test('quoted path calls preserve duplicate parallel-edge occurrences and the common traversal', () => {
  const control = successes.find(x => x.name.endsWith('path-independent-json'));
  const program = JSON.parse(control.text);
  assert.deepEqual(program.stages[0].steps[1].values.rows,
    [{key: 10, src: 1, dst: 1}, {key: 11, src: 1, dst: 1}]);
  assert.deepEqual(program.stages[0].steps[4].traverse, {
    start: {from: 'seeds', id: 'identity'}, path_mode: 'walk', emit: 'paths',
    hops: [{direction: 'out', edge_types: ['R']}],
  });
  assert.deepEqual(control.results.matched, {rows: [{depth: 1}, {depth: 1}],
    columns: [{name: 'depth', contract: {type: 'number', nullable: false}}]});
  for (const index of [0, 1, 2]) {
    const item = successes.find(x => x.name.endsWith('quoted-path-' + index));
    assert.deepEqual(item.results, control.results);
    assert.equal(item.sourceReadCount, 0);
  }
});

test('Graph nullable, empty and unknown-member cases retain their separate obligations', () => {
  const nullable = successes.find(item => item.name.endsWith('folded-null-receiver-and-member'));
  assert.deepEqual(nullable.results.matched.rows,
    [{id: 3, score: null}, {id: 4, score: null}]);
  const empty = successes.find(item => item.name.endsWith('folded-typed-empty'));
  assert.deepEqual(empty.results.matched.rows, []);
  assert.deepEqual(empty.results.matched.columns, [
    {name: 'id', contract: {type: 'number', nullable: false}},
    {name: 'score', contract: {type: 'number', nullable: false}},
  ]);
  assert.equal(nullable.results.matched.columns[1].contract.nullable, true);
  assert.ok(refusals.some(item => item.text.includes('a.payload.MISSING')));
  assert.ok(refusals.some(item => item.name.endsWith('removed-graph-variable')));
  assert.ok(refusals.some(item => item.name.endsWith('scalar-receiver')));
});

test('Graph member fixtures remain in the normal public acceptance consumer', async () => {
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(driver.includes('fixtures/graph-projection-property-source-input.mjs'));
  assert.ok(driver.includes('--graph-projection-property-only'));
});

test('grouped Graph binding fixtures retain independent identity and multiplicity controls', () => {
  const identity = successes.find(item => item.name.endsWith('grouped-identity-independent-json'));
  assert.deepEqual(identity.results.matched.rows, [{id: 1, score: 20}]);
  const control = JSON.parse(identity.text);
  assert.deepEqual(control.stages[0].steps[3].filter, {and: [
    {not: {is_null: {field: 'identity'}}},
    {gt: [{property: {name: 'score', value: {field: 'payload'}}}, {literal: 10}]},
  ]});
  assert.equal(control.stages[0].steps[4].from, undefined);
  for (const argument of ['(a)', '(((a)))', '(`A`)']) {
    const item = successes.find(value => value.text.includes('NODE_ID(' + argument + ')')
      && value.parameters?.min === 10);
    assert.ok(item, argument);
    assert.deepEqual(item.results, identity.results);
  }
  const empty = successes.find(item => item.name.endsWith('grouped-identity-typed-empty'));
  assert.deepEqual(empty.results.matched.rows, []);
  assert.deepEqual(empty.results.matched.columns, identity.results.matched.columns);
  const path = successes.find(item => item.name.endsWith('grouped-path-independent-json'));
  assert.deepEqual(path.results.matched, {rows: [{depth: 1}, {depth: 1}],
    columns: [{name: 'depth', contract: {type: 'number', nullable: false}}]});
  assert.deepEqual(JSON.parse(path.text).stages[0].steps[1].values.rows,
    [{key: 10, src: 1, dst: 1}, {key: 11, src: 1, dst: 1}]);
  for (const argument of ['p', '((p))', '(`P`)']) {
    const item = successes.find(value => value.text.includes('PATH_LENGTH(' + argument + ')'));
    assert.ok(item, argument);
    assert.deepEqual(item.results, path.results);
  }
});

test('grouped Graph binding refusals preserve closed roles and post-projection scope', () => {
  for (const suffix of ['property', 'expression', 'wrong-role', 'wrong-arity', 'removed-binding']) {
    assert.ok(refusals.some(item => item.name.endsWith('grouped-macro-' + suffix)), suffix);
  }
  assert.equal(refusals.find(item => item.name.endsWith('grouped-macro-property')).expectedCode,
    'ClientProgramImplementationLimit');
});
test('quoted Graph identity calls retain the authored predicate value and typed empty output', () => {
  const json = successes.find(x => x.name.endsWith('identity-independent-json'));
  const program = JSON.parse(json.text);
  assert.deepEqual(program.stages[0].steps[2].match_nodes.bindings, {identity: 'identity'});
  assert.deepEqual(program.stages[0].steps[3].filter, {and: [
    {not: {is_null: {field: 'identity'}}},
    {gt: [{property: {name: 'score', value: {field: 'payload'}}}, {literal: 10}]},
  ]});
  assert.equal(program.stages[0].steps[4].from, undefined);
  assert.deepEqual(program.stages[0].steps[4].derive.score,
    {property: {name: 'score', value: {field: 'payload'}}});
  assert.deepEqual(json.results.matched.rows, [{id: 1, score: 20}]);
  for (const index of [0, 1, 2]) {
    const item = successes.find(x => x.name.endsWith('quoted-identity-' + index));
    assert.deepEqual(item.results, json.results);
    assert.equal(item.parameters.min, 10);
    assert.equal(item.sourceReadCount, 0);
  }
  const empty = successes.find(x => x.name.endsWith('quoted-identity-typed-empty'));
  assert.deepEqual(empty.results.matched.rows, []);
  assert.deepEqual(empty.results.matched.columns, json.results.matched.columns);
  for (const name of ['quoted-unknown-macro', 'quoted-macro-namespace',
    'quoted-macro-wrong-role', 'quoted-macro-wrong-arity', 'quoted-macro-removed-binding']) {
    assert.ok(refusals.some(x => x.name.endsWith(name)));
  }
});
