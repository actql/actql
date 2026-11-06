import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {pipeJoinRangesProgram, postJoinSetProgram, postJoinDropProgram,
  extendRangeProgram, renameTargetProgram, editCollisionProgram, pipeJoinRangesSuccesses, pipeJoinRangesRefusals}
  from './fixtures/pipe-join-ranges.mjs';

test('range obligations distinguish current values from original slots and preserve duplicates', () => {
  const cases = new Map(pipeJoinRangesSuccesses.map(item => [item.name, item]));
  const control = JSON.parse(cases.get('pipe-join-ranges-independent-json').text);
  assert.deepEqual(control, pipeJoinRangesProgram);
  assert.deepEqual(control.stages[1].steps[2].join.on, [{left: 'id', right: 'k'}]);
  assert.equal(control.stages[1].steps[2].join.select.current, 'left.replacement');
  assert.equal(control.stages[1].steps[2].join.select.original, 'left.id');
  assert.deepEqual(cases.get('pipe-join-ranges-set-original-key').expected,
    [{current: 12, original: 2, amount: 20, matched: 2},
      {current: 12, original: 2, amount: 20, matched: 2}]);
  assert.equal(cases.get('pipe-join-ranges-nullable-left').expected[0].matched, null);
  assert.equal(cases.get('pipe-join-ranges-empty-typed').columns.length, 4);
  assert.deepEqual(cases.get('pipe-join-ranges-star-visible-row').columns.map(column => column.name),
    ['amount', 'id', 'k']);
  assert.deepEqual(cases.get('pipe-join-ranges-parameter-slot').parameters, {increment: 10});
  assert.equal(cases.get('pipe-join-ranges-shared-source').expected.length, 6);
  assert.equal(cases.get('pipe-join-ranges-shared-source').sourceReadSessionCount, 1);
  const originalRefusals = pipeJoinRangesRefusals.filter(item =>
    !item.name.includes('refuse-extend-') && !item.name.includes('refuse-rename-')
    && !item.name.includes('refuse-edit-') && !item.name.includes('refuse-post-'));
  assert.equal(originalRefusals.length, 4);
  assert.ok(originalRefusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
});

test('post-JOIN edits keep old slots, current values, duplicate rows and authored limits', () => {
  const cases = new Map(pipeJoinRangesSuccesses.map(item => [item.name, item]));
  const set = cases.get('pipe-join-ranges-post-set-original-slot');
  const drop = cases.get('pipe-join-ranges-post-drop-original-slot');
  assert.deepEqual(JSON.parse(cases.get('pipe-join-ranges-post-set-independent-json').text), postJoinSetProgram);
  assert.deepEqual(JSON.parse(cases.get('pipe-join-ranges-post-drop-independent-json').text), postJoinDropProgram);
  assert.deepEqual(set.expected, [{current: 12, original: 2, amount: 20, matched: 2},
    {current: 12, original: 2, amount: 20, matched: 2}]);
  assert.deepEqual(drop.expected, [{current: 2, original: 2, amount: 20, matched: 2},
    {current: 2, original: 2, amount: 20, matched: 2}]);
  const steps = postJoinSetProgram.stages[1].steps;
  assert.equal(steps[1].join.max_output_rows, 10);
  assert.deepEqual(steps[1].join.on, [{left: 'id', right: 'k'}]);
  assert.deepEqual(steps[2].derive, {current: {add: [{field: 'old_id'}, {literal: 10}]}});
  assert.deepEqual(steps[4].select, ['current', {original: 'old_id'}, 'amount', 'matched']);
  assert.ok(set.text.indexOf('JOIN') < set.text.indexOf('SET id'));
  assert.deepEqual(cases.get('pipe-join-ranges-post-set-parameter').parameters, {increment: 10});
  assert.deepEqual(cases.get('pipe-join-ranges-post-set-typed-empty').columns, set.columns);
  assert.deepEqual(cases.get('pipe-join-ranges-post-set-left-nullable').expected[0],
    {current: 11, original: 1, amount: null, matched: null});
  assert.deepEqual(cases.get('pipe-join-ranges-post-extend-current-slot').expected, set.expected);
  assert.deepEqual(cases.get('pipe-join-ranges-post-extend-fresh-range').expected, set.expected);
  assert.deepEqual(set.columns.map(column => column.name), ['current', 'original', 'amount', 'matched']);
  assert.deepEqual(set.columns.map(column => column.contract.nullable), [false, false, true, false]);
  const refusals = pipeJoinRangesRefusals.filter(item => item.name.includes('refuse-post-'));
  assert.equal(refusals.length, 4);
  assert.ok(refusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  const successes = pipeJoinRangesSuccesses.filter(item => item.name.startsWith('pipe-join-ranges-post-'));
  assert.equal(successes.length, 10);
  assert.ok(successes.every(item => item.sourceReadSessionCount === 1));
});

test('RENAME targets only one current column and preserves independent JOIN values', () => {
  const cases = new Map(pipeJoinRangesSuccesses.map(item => [item.name, item]));
  const json = cases.get('pipe-join-ranges-rename-independent-json');
  assert.deepEqual(JSON.parse(json.text), renameTargetProgram);
  assert.deepEqual(renameTargetProgram.stages[1].steps[1].join,
    {with: 'rights', kind: 'inner', on: [{left: 'id', right: 'id'}], max_output_rows: 10,
      select: {current: 'left.amount', original: 'left.id', matched: 'right.id'}});
  const source = cases.get('pipe-join-ranges-rename-unrelated-duplicates');
  assert.deepEqual(source.expected, [{current: 20, original: 2, matched: 2},
    {current: 20, original: 2, matched: 2}]);
  assert.deepEqual(source.columns.map(column => column.name), ['current', 'original', 'matched']);
  assert.deepEqual(source.columns.map(column => column.contract.nullable), [true, false, false]);
  assert.equal(source.sourceReadSessionCount, 1);
  assert.ok(cases.get('pipe-join-ranges-rename-new-ambiguity').text.includes('SELECT l.amount AS `current`'));
  assert.equal(cases.get('pipe-join-ranges-rename-nullable').expected[0].current, null);
  assert.deepEqual(cases.get('pipe-join-ranges-rename-empty-typed').expected, []);
  const refusals = pipeJoinRangesRefusals.filter(item => item.name.includes('refuse-rename-'));
  assert.equal(refusals.length, 6);
  assert.ok(refusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
});

test('first EXTEND preserves original range membership and explicit fresh AS binding', () => {
  const cases = new Map(pipeJoinRangesSuccesses.map(item => [item.name, item]));
  const control = cases.get('pipe-join-ranges-extend-independent-json');
  const source = cases.get('pipe-join-ranges-extend-original-range');
  assert.deepEqual(JSON.parse(control.text), extendRangeProgram);
  assert.deepEqual(control.expected, [
    {original: 1, current: 11, amount: null},
    {original: 2, current: 12, amount: 20}, {original: 2, current: 12, amount: 20},
  ]);
  assert.deepEqual(source.expected, control.expected);
  assert.deepEqual(source.columns, control.columns);
  assert.deepEqual(source.columns.map(column => column.name), ['original', 'current', 'amount']);
  assert.deepEqual(source.columns.map(column => column.contract.nullable), [false, false, true]);
  const fresh = cases.get('pipe-join-ranges-extend-fresh-range');
  assert.ok(fresh.text.includes('AS fresh') && fresh.text.includes('fresh.z AS `current`'));
  assert.equal(source.sourceReadSessionCount, 1);
  const empty = cases.get('pipe-join-ranges-extend-empty-typed');
  assert.deepEqual(empty.expected, []);
  assert.deepEqual(empty.columns, source.columns);
  const refusals = pipeJoinRangesRefusals.filter(item => item.name.includes('refuse-extend-'));
  assert.equal(refusals.length, 5);
  assert.ok(refusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  const names = [...pipeJoinRangesSuccesses, ...pipeJoinRangesRefusals].map(item => item.name);
  assert.equal(new Set(names).size, names.length);
});

test('range corpus runs through ordinary packed acceptance and the same focused selector', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...pipeJoinRangesSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...pipeJoinRangesRefusals)'));
  assert.match(fixture, /const scopeOnly = [^;]*pipeJoinRangesOnly/u);
  assert.ok(driver.includes("['scripts/fixtures/pipe-join-ranges.mjs', 'pipe-join-ranges.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_PIPE_JOIN_RANGES_ONLY = '1'"));
  assert.ok(driver.includes("if (process.argv.includes('--pipe-join-ranges-only')) return;"));
});


test('same-name edits use replacement objects and remove hidden range access', () => {
  const cases = new Map(pipeJoinRangesSuccesses.map(item => [item.name, item]));
  const json = cases.get('pipe-join-ranges-edit-independent-json');
  const source = cases.get('pipe-join-ranges-edit-object-current');
  assert.deepEqual(JSON.parse(json.text), editCollisionProgram);
  assert.deepEqual(editCollisionProgram.stages[1].steps[1].derive.current,
    {property: {value: {field: 'updated'}, name: 'id'}});
  assert.deepEqual(source.expected, [{current: 99, amount: null},
    {current: 99, amount: 20}, {current: 99, amount: 20}]);
  assert.deepEqual(source.expected, json.expected);
  assert.deepEqual(source.columns, json.columns);
  assert.deepEqual(source.columns.map(column => column.name), ['current', 'amount']);
  assert.deepEqual(source.columns.map(column => column.contract.nullable), [false, true]);
  assert.equal(source.sourceReadSessionCount, 1);
  assert.ok(source.text.includes('amount = id.amount'));
  assert.deepEqual(cases.get('pipe-join-ranges-edit-empty-typed').expected, []);
  const refusals = pipeJoinRangesRefusals.filter(item => item.name.includes('refuse-edit-'));
  assert.equal(refusals.length, 5);
  assert.ok(refusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  for (const refusal of refusals) {
    if (!refusal.text.includes('@replacement')) {
      assert.equal(refusal.parameterDeclarations, undefined);
      assert.equal(refusal.parameters, undefined);
    }
  }
});
