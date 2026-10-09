import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {joinStarProgram, pipeSetTargetProgram, joinStarSuccesses, joinStarRefusals, joinStarExecutionFailures}
  from './fixtures/join-star-source-input.mjs';

test('JOIN-star independent oracles distinguish USING order from input order', () => {
  const cases = new Map(joinStarSuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(cases.get('join-star-independent-json').text), joinStarProgram);
  assert.deepEqual(cases.get('join-star-on-unique-columns').columns.map(column => column.name), ['amount', 'id', 'k']);
  assert.deepEqual(cases.get('join-star-left-using-key-first').columns.map(column => column.name), ['id', 'amount']);
  assert.deepEqual(cases.get('join-star-declared-using-order').expected,
    [{id: 2, amount: 20}, {id: 3, amount: 30}, {id: 3, amount: 30}, {id: 3, amount: 30}, {id: 3, amount: 30}]);
  assert.deepEqual(cases.get('join-star-using-qualified-null-control').expected[0],
    {id: 1, amount: null, original: 1, joined: null});
  assert.equal(cases.get('join-star-using-qualified-null-control').columns.at(-1).contract.nullable, true);
  assert.deepEqual(cases.get('join-star-empty-typed-result').columns, cases.get('join-star-on-unique-columns').columns);
  const all = [...joinStarSuccesses, ...joinStarRefusals];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('SET target controls distinguish one current column from operand range slots', () => {
  const cases = new Map(joinStarSuccesses.map(item => [item.name, item]));
  const json = cases.get('join-star-set-target-independent-json');
  const text = cases.get('join-star-set-target-unique-range');
  assert.deepEqual(JSON.parse(json.text), pipeSetTargetProgram);
  assert.deepEqual(json.expected, text.expected);
  assert.deepEqual(json.columns, text.columns);
  for (const item of joinStarSuccesses.filter(item => item.name.includes('set-target-') && item.format !== 'json')) {
    assert.equal(item.format, 'aql-text');
  }
  assert.deepEqual(text.columns.map(column => column.contract.nullable), [false, true, false]);
  assert.deepEqual(cases.get('join-star-set-target-unmatched-range').expected,
    [{current: 99, original: null, matched: 9}]);
  const using = cases.get('join-star-set-target-coalesced-using');
  assert.deepEqual(using.expected.map(row => row.current), [-1, -2, -3, -3, -3, -3]);
  assert.deepEqual(using.expected.map(row => row.right_original), [1, 2, 3, 3, 3, 3]);
  const refusals = joinStarRefusals.filter(item => item.name.includes('refuse-set-target-'));
  assert.equal(refusals.length, 8);
  assert.ok(refusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  assert.ok(refusals.some(item => item.text.includes('SET `ID` = 99')));
  assert.ok(refusals.some(item => item.text.includes('SET id = ROW_NUMBER()')));
});

test('JOIN input refusals cannot be hidden by projection or confused with repeated ON', () => {
  const controls = new Map(joinStarSuccesses.map(item => [item.name, item]));
  const ordinary = controls.get('join-star-on-unique-columns');
  const repeated = controls.get('join-star-repeated-on-kept');
  assert.deepEqual(repeated.expected, ordinary.expected);
  assert.deepEqual(repeated.columns, ordinary.columns);
  assert.ok(repeated.text.includes('ON l.id = r.k AND l.id = r.k MAX_OUTPUT_ROWS 10'));
  const hidden = joinStarRefusals.filter(item => item.name.startsWith('join-star-refuse-hidden-using-'));
  assert.equal(hidden.length, 4);
  assert.ok(hidden.every(item => item.text.includes('SELECT l.id AS original')
    && item.text.includes('USING (id, `ID`) MAX_OUTPUT_ROWS 10')
    && item.expectedCode === 'ClientProgramInvalidInput'));
  assert.ok(joinStarRefusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
});

test('JOIN-star cases remain in ordinary and targeted public acceptance', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...joinStarSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...joinStarRefusals)'));
  assert.match(fixture, /const scopeOnly = [^;]*joinStarOnly/u);
  assert.ok(fixture.includes('joinStarOnly ? {successes: joinStarSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_JOIN_STAR_ONLY = '1'"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--join-star-only'/u);
  assert.match(driver, /if \(process\.argv\.includes\('--join-star-only'\)\) return;/u);
});

test('captured projection uses independent JSON ports and unchanged NULL/multiplicity controls', () => {
  const controls = new Map(joinStarSuccesses.map(item => [item.name, item]));
  const json = controls.get('join-star-captured-projection-json');
  const source = controls.get('join-star-captured-projection-source');
  const program = JSON.parse(json.text);
  assert.deepEqual(program.stages[1].steps[0].join.on, [{left: 'id', right: 'id'}]);
  assert.equal(program.stages[1].steps[0].join.max_output_rows, 10);
  assert.deepEqual(program.stages[1].results.rows.fields, ['id', 'amount']);
  assert.deepEqual(source.expected, json.expected);
  assert.deepEqual(source.columns, json.columns);
  assert.equal(source.expected.length, 6);
  assert.equal(source.expected[0].amount, null);
  assert.equal(source.sourceReadSessionCount, 1);
  assert.equal(controls.get('join-star-captured-projection-filtered').expected.length, 4);
  assert.deepEqual(controls.get('join-star-captured-projection-limited').expected,
    [{id: 2, amount: 20}, {id: 3, amount: 30}]);
});

test('Values JOIN ceiling controls distinguish complete output from exceeded guards', () => {
  const controls = new Map(joinStarSuccesses.map(item => [item.name, item]));
  const json = controls.get('join-star-values-ceiling-json');
  const source = controls.get('join-star-values-ceiling-source');
  const program = JSON.parse(json.text);
  assert.equal(program.stages[2].steps[0].join.max_output_rows, 5);
  assert.deepEqual(json.expected, [{x: 1}, {x: 2}]);
  assert.deepEqual(source.expected, json.expected);
  assert.deepEqual(source.columns, json.columns);
  assert.ok(source.text.endsWith('MAX_OUTPUT_ROWS 5'));
  assert.equal(json.sourceReadSessionCount, 0);
  assert.equal(source.sourceReadSessionCount, 0);
  assert.equal(joinStarExecutionFailures.length, 2);
  const failed = JSON.parse(joinStarExecutionFailures[0].text);
  assert.equal(failed.stages[2].steps[0].join.max_output_rows, 1);
  failed.stages[2].steps[0].join.max_output_rows = 5;
  assert.deepEqual(failed, program);
  assert.equal(joinStarExecutionFailures[1].text,
    source.text.replace('MAX_OUTPUT_ROWS 5', 'MAX_OUTPUT_ROWS 1'));
  assert.ok(joinStarExecutionFailures.every(item => item.sourceReadSessionCount === 0));
});

test('Values JOIN exceeded guards remain in normal and focused public execution', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('executionFailures: joinStarExecutionFailures}'));
  assert.ok(fixture.includes('scopeInputs.executionFailures.push(...joinStarExecutionFailures)'));
});
