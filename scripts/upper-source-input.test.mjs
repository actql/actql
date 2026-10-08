import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {upperSuccesses, upperRefusals, upperExecutionFailures} from './fixtures/upper-source-input.mjs';

const cases = new Map(upperSuccesses.map(item => [item.name, item]));
test('uppercase expectations retain full mappings, raw mark order and Unicode 16 characters', () => {
  assert.deepEqual(cases.get('upper-full-expansions').expected,
    [{word: 'STRASSE', ligature: 'FFI', greek: 'ἈΙ', marks: 'Ϊ́'}]);
  assert.deepEqual(cases.get('upper-unicode-16-and-supplementary').expected,
    [{deseret: '𐐀', garay: '𐵐', cyrillic: 'Ᲊ'}]);
  assert.deepEqual(cases.get('upper-no-normalization').expected,
    [{decomposed: 'E\u0301', composed: '\u00C9', mark_order: 'J\u030C\u0323'}]);
  assert.deepEqual(cases.get('upper-locale-independent').expected,
    [{value: 'I I I İ I\u0307 Σ Σ Σ'}]);
  assert.deepEqual(JSON.parse(cases.get('upper-json-control').text).stages[0].steps[1].derive.value,
    {upper: {literal: 'straße'}});
});

test('uppercase public fixtures distinguish NULL, empty rows, duplicates and demanded failure', () => {
  assert.deepEqual(cases.get('upper-literal-null').columns,
    ['value', 'typed_value'].map(name => ({name, contract: {type: 'string', nullable: true}})));
  assert.deepEqual(cases.get('upper-sql-input').expected,
    [{id: 1, value: null}, {id: 2, value: 'STRASSE-20'}, {id: 3, value: 'STRASSE-30'}, {id: 3, value: 'STRASSE-30'}]);
  assert.deepEqual(cases.get('upper-pipe-input').expected, cases.get('upper-sql-input').expected);
  assert.deepEqual(cases.get('upper-typed-empty').expected, []);
  assert.deepEqual(cases.get('upper-typed-empty').columns, cases.get('upper-sql-input').columns);
  assert.equal(upperSuccesses.length, 15);
  assert.equal(upperRefusals.length, 7);
  assert.ok(upperRefusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  assert.equal(upperExecutionFailures.length, 1);
  const all = [...upperSuccesses, ...upperRefusals, ...upperExecutionFailures];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('uppercase cases use normal packed acceptance and a bounded source selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'upperSuccesses'], ['refusals', 'upperRefusals'],
    ['executionFailures', 'upperExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.includes('upperOnly ? {successes: upperSuccesses'));
  assert.match(fixture, /const scopeOnly = [^;]*\bupperOnly\b/u);
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_UPPER_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/upper-source-input.mjs', 'upper-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^;]*'--upper-only'/u);
  assert.ok(driver.includes("if (process.argv.includes('--upper-only')) return;"));
});
