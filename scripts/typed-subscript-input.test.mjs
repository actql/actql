import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {typedSubscriptProgram, typedSubscriptSuccesses, typedSubscriptRefusals,
  typedSubscriptExecutionFailures} from './fixtures/typed-subscript-input.mjs';

test('typed subscript controls retain independent complete Program and nullable result', () => {
  assert.deepEqual(JSON.parse(typedSubscriptSuccesses[0].text), typedSubscriptProgram({
    subscript: {value: {array: [{literal: 2}, {literal: 1}, {literal: 2}]}, index: {literal: 1}},
  }));
  assert.deepEqual(typedSubscriptSuccesses.slice(0, 2).map(item => item.results.answer), [
    {rows: [{v: 1}], columns: [{name: 'v', contract: {type: 'number', nullable: true}}]},
    {rows: [{v: null}], columns: [{name: 'v', contract: {type: 'number', nullable: true}}]},
  ]);
  assert.equal(typedSubscriptSuccesses.length, 6);
  assert.equal(typedSubscriptExecutionFailures.length, 2);
  assert.equal(typedSubscriptRefusals.length, 2);
  assert.deepEqual(typedSubscriptSuccesses[5].results.answer, {
    rows: [{v: 'e\u0301\r\n😀'}],
    columns: [{name: 'v', contract: {type: 'string', nullable: true, max_utf8_bytes: 9}}],
  });
  assert.equal(Buffer.byteLength('e\u0301\r\n😀', 'utf8'), 9);
  for (const item of [...typedSubscriptSuccesses, ...typedSubscriptExecutionFailures,
    ...typedSubscriptRefusals]) {
    const program = JSON.parse(item.text);
    assert.equal(program.stages.length, 1);
    assert.deepEqual(program.stages[0].steps[0].values.rows, [{id: 1}]);
    assert.deepEqual(program.results, {answer: {from: {stage: 'main', result: 'rows'}}});
  }
});

test('typed subscript packed selection stays narrow and reuses original retained restart', async () => {
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const corpus = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const start = driver.indexOf('const narrowPublicQuery =');
  const end = driver.indexOf('.includes(flag));', start);
  assert.ok(driver.slice(start, end).includes("'--typed-subscript-only'"));
  assert.ok(driver.includes("['scripts/fixtures/typed-subscript-input.mjs', 'typed-subscript-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_TYPED_SUBSCRIPT_ONLY = '1'"));
  assert.ok(corpus.includes('typedSubscriptOnly ? {successes: typedSubscriptSuccesses'));
  const restart = driver.indexOf("await exerciseRetainedQueryRestart({ACTQL_TEST_RETAINED_COHORT_ONLY: '1'})");
  assert.ok(restart > end);
  assert.ok(driver.slice(driver.indexOf("if (process.argv.includes('--graph-graft-only')"), restart)
    .includes("process.argv.includes('--typed-subscript-only')"));
});
