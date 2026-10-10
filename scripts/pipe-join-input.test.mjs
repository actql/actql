import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {pipeJoinInputProgram, pipeJoinInputSuccesses, pipeJoinInputRefusals}
  from './fixtures/pipe-join-input.mjs';

test('Pipe JOIN independent obligations detect lost predicates limits and multiplicity', () => {
  const cases = new Map(pipeJoinInputSuccesses.map(item => [item.name, item]));
  const control = JSON.parse(cases.get('pipe-join-input-independent-json').text);
  assert.deepEqual(control, pipeJoinInputProgram);
  assert.deepEqual(control.stages[1].steps[2].filter,
    {gte: [{field: 'key'}, {$param: 'minimum'}]});
  assert.deepEqual(control.stages[1].steps[4].take, {count: {$param: 'take'}, offset: 0});
  assert.equal(control.stages[1].steps[6].join.max_output_rows, 10);
  assert.deepEqual(cases.get('pipe-join-input-projected-prefix').expected,
    [{amount: 30, key: 13, matched: 13}]);
  assert.deepEqual(cases.get('pipe-join-input-set-then-rebind').expected,
    [{amount: 20, key: 13, matched: 13}]);
  assert.deepEqual(cases.get('pipe-join-input-empty-typed').columns,
    cases.get('pipe-join-input-projected-prefix').columns);
  assert.equal(cases.get('pipe-join-input-nullable-left').columns.at(-1).contract.nullable, true);
  assert.equal(cases.get('pipe-join-input-where-between-fused-joins').expected.length, 2);
  assert.ok(pipeJoinInputRefusals.some(item => item.name.endsWith('removed-range')));
  const all = [...pipeJoinInputSuccesses, ...pipeJoinInputRefusals];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('removed Pipe JOIN names and duplicate ranges are invalid input', () => {
  assert.deepEqual(pipeJoinInputRefusals.slice(0, 3).map(({name, expectedCode}) =>
    ({name, expectedCode})), [
    {name: 'pipe-join-input-refuse-removed-range', expectedCode: 'ClientProgramInvalidInput'},
    {name: 'pipe-join-input-refuse-removed-column', expectedCode: 'ClientProgramInvalidInput'},
    {name: 'pipe-join-input-refuse-duplicate-range', expectedCode: 'ClientProgramInvalidInput'},
  ]);
  assert.ok(pipeJoinInputRefusals[0].text.includes('ON old.id = r.key'));
  assert.ok(pipeJoinInputRefusals[1].text.includes('ON l.id = r.key'));
  assert.ok(pipeJoinInputRefusals[2].text.includes('AS l ON l.key = l.key'));
});

test('ordinary and narrow packed acceptance use the same Pipe JOIN corpus', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...pipeJoinInputSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...pipeJoinInputRefusals)'));
  assert.match(fixture, /const scopeOnly = [^;]*pipeJoinInputOnly/u);
  assert.ok(fixture.includes('pipeJoinInputOnly ? {successes: pipeJoinInputSuccesses'));
  assert.ok(driver.includes("['scripts/fixtures/pipe-join-input.mjs', 'pipe-join-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_PIPE_JOIN_INPUT_ONLY = '1'"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--pipe-join-input-only'/u);
  assert.ok(driver.includes("if (process.argv.includes('--pipe-join-input-only')) return;"));
});
