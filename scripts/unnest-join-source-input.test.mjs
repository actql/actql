import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {unnestJoinProgram, unnestFullJoinProgram, unnestObjectJoinProgram, unnestJoinSuccesses, unnestJoinRefusals}
  from './fixtures/unnest-join-source-input.mjs';
import {correlatedUnnestSuccesses, correlatedUnnestRefusals}
  from './fixtures/correlated-unnest-source-input.mjs';

test('independent control expands before matching and preserves authored bounds', () => {
  assert.deepEqual(unnestJoinProgram.stages[0].steps.slice(1, 3), [
    {from: 'seed', derive: {array: {$param: 'items'}}},
    {unnest: {column: 'array', as: 'element', with_index: 'position'}, as: 'expanded'},
  ]);
  assert.deepEqual(unnestJoinProgram.stages[0].steps[4], {
    from: 'expanded', join: {with: 'keys', kind: 'inner', on: [{left: 'element', right: 'key'}],
      max_output_rows: 10, select: {element: 'left.element', position: 'left.position', key: 'right.key'}},
    as: 'joined',
  });
  assert.deepEqual(unnestJoinSuccesses[0].expected,
    [{element: 2, position: 0, key: 2}, {element: 2, position: 2, key: 2}]);
  assert.deepEqual(JSON.parse(unnestJoinSuccesses[0].text), unnestJoinProgram);
  const object = unnestJoinSuccesses.find(item => item.name === 'unnest-join-object-json-control');
  assert.deepEqual(JSON.parse(object.text), unnestObjectJoinProgram);
  assert.deepEqual(object.expected, [{code: 2, label: 'b', position: 0, key: 2},
    {code: 2, label: 'b', position: 2, key: 2}]);
  const full = unnestJoinSuccesses.find(item => item.name === 'unnest-join-full');
  const fullControl = unnestJoinSuccesses.find(item => item.name === 'unnest-join-full-json-control');
  assert.deepEqual(JSON.parse(fullControl.text), unnestFullJoinProgram);
  assert.deepEqual(full.expected, fullControl.expected);
  assert.deepEqual(full.expected, [{element: 2, position: 0, key: 2},
    {element: null, position: 1, key: null}, {element: 2, position: 2, key: 2},
    {element: null, position: null, key: 3}]);
  assert.deepEqual(unnestFullJoinProgram.stages[0].steps[3].assert_rows, {unique_by: ['position']});
  assert.deepEqual(unnestFullJoinProgram.stages[0].steps[5].assert_rows, {unique_by: ['key']});
  assert.equal(unnestFullJoinProgram.stages[0].steps[6].join.max_output_rows, 10);
  assert.match(full.text, /ASSERT UNIQUE BY \(position\) \|> FULL JOIN/u);
  assert.match(full.text, /ASSERT UNIQUE BY \(key\)/u);
});

test('NULL extension, original range and empty schemas have distinct obligations', () => {
  const byName = new Map(unnestJoinSuccesses.map(item => [item.name, item]));
  const left = byName.get('unnest-join-left');
  assert.deepEqual(left.expected.map(row => [row.element, row.key]), [[2, 2], [null, null], [2, 2]]);
  assert.deepEqual(left.columns[2], {name: 'key', contract: {type: 'number', nullable: true}});
  const original = byName.get('unnest-join-immutable-range');
  assert.deepEqual(original.expected.map(row => [row.current, row.original]), [[99, 2], [99, 2]]);
  assert.match(original.text, /SET code = 99 \|> JOIN.*ON e\.code = k\.key/u);
  const whole = byName.get('unnest-join-whole-object');
  assert.deepEqual(whole.columns[0], {name: 'original', contract: {
    type: 'object', nullable: true, additional_properties: false,
    fields: {code: {type: 'number', nullable: false}, label: {type: 'string', nullable: true}},
  }});
  assert.equal(Object.hasOwn(whole.parameterDeclarations.objects.items, 'additional_properties'), false,
    'author contracts omit fixed machine fields; describe returns the complete checked contract');
  for (const name of ['empty', 'null-array']) {
    assert.deepEqual(byName.get('unnest-join-' + name).expected, []);
    assert.deepEqual(byName.get('unnest-join-' + name).columns, byName.get('unnest-join-sql').columns);
  }
  const acquired = byName.get('unnest-join-acquired');
  assert.equal(acquired.sourceReadCount, 1);
  assert.equal(acquired.sourceReadSessionCount, 1);
  assert.deepEqual(acquired.expected.map(row => row.position), [0, 2, 3]);
});

test('new positive and refusal obligations participate in normal and selected public routes', () => {
  for (const item of unnestJoinSuccesses) assert.ok(correlatedUnnestSuccesses.includes(item));
  for (const item of unnestJoinRefusals) {
    assert.ok(correlatedUnnestRefusals.includes(item));
    assert.equal(item.expectedCode, 'ClientProgramInvalidInput');
  }
  assert.equal(new Set([...correlatedUnnestSuccesses, ...correlatedUnnestRefusals].map(item => item.name)).size,
    correlatedUnnestSuccesses.length + correlatedUnnestRefusals.length);
  assert.ok(!correlatedUnnestRefusals.some(item => item.name === 'correlated-unnest-refusal-join-after-expansion'));
  const cross = correlatedUnnestSuccesses.find(item => item.name === 'correlated-unnest-join-after-expansion');
  assert.equal(cross.expected.length, 8);
  assert.equal(cross.sourceReadCount, 1);
  assert.match(cross.text, /MAX_OUTPUT_ROWS 10/u);
  const driver = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/unnest-join-source-input.mjs', 'unnest-join-source-input.mjs']"));
});
