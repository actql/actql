import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {pipeUnpivotSuccesses, pipeUnpivotRefusals} from './fixtures/pipe-unpivot-source-input.mjs';

test('UNPIVOT fixtures independently retain NULL, duplicates, labels and column order', () => {
  const cases = new Map(pipeUnpivotSuccesses.map(item => [item.name, item]));
  const include = cases.get('pipe-unpivot-include-json-control');
  const exclude = cases.get('pipe-unpivot-exclude-json-control');
  assert.equal(include.expected.length, 6);
  assert.equal(exclude.expected.length, 3);
  assert.deepEqual(exclude.expected, [{id: 1, amount: 5, month: 'feb'},
    {id: 2, amount: 7, month: 'jan'}, {id: 2, amount: 7, month: 'jan'}]);
  assert.deepEqual(cases.get('pipe-unpivot-default').expected, exclude.expected);
  assert.deepEqual(cases.get('pipe-unpivot-include-and-range').expected, include.expected);
  const program = JSON.parse(include.text);
  assert.deepEqual(program.stages[0].steps[1].unpivot,
    {columns: ['jan', 'feb'], keep: ['id'], name_column: 'month', value_column: 'amount'});
  assert.deepEqual(program.stages[0].steps.at(-1).select, ['id', 'amount', 'month']);
  assert.deepEqual(cases.get('pipe-unpivot-empty').expected, []);
  assert.deepEqual(cases.get('pipe-unpivot-empty').columns, include.columns);
  const replaced = cases.get('pipe-unpivot-current-slots-and-labels').expected;
  assert.deepEqual(replaced.filter(row => row.month === 'jan').map(row => row.amount), [null, 107, 107]);
  assert.ok(replaced.some(row => row.month === 'february'));
  assert.ok(replaced.every(row => !row.month.startsWith('aql_')));
  assert.equal(pipeUnpivotSuccesses.length, 7);
  assert.equal(pipeUnpivotRefusals.length, 6);
  assert.ok(pipeUnpivotRefusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
});

test('UNPIVOT participates in ordinary public acceptance and a narrow bounded selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'pipeUnpivotSuccesses'], ['refusals', 'pipeUnpivotRefusals']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.includes('pipeUnpivotOnly ? {successes: pipeUnpivotSuccesses'));
  assert.match(fixture, /const scopeOnly = [^;]*\bpipeUnpivotOnly\b/u);
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_PIPE_UNPIVOT_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/pipe-unpivot-source-input.mjs', 'pipe-unpivot-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^;]*'--pipe-unpivot-only'/u);
  assert.ok(driver.includes("if (process.argv.includes('--pipe-unpivot-only')) return;"));
});
