import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {pipeJoinRangesProgram, extendRangeProgram, pipeJoinRangesSuccesses, pipeJoinRangesRefusals}
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
  const originalRefusals = pipeJoinRangesRefusals.filter(item => !item.name.includes('refuse-extend-'));
  assert.equal(originalRefusals.length, 4);
  assert.ok(originalRefusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
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
  assert.ok(fresh.text.includes('AS fresh') && fresh.text.includes('fresh.z AS current'));
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
