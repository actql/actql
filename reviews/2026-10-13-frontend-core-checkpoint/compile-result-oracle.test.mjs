import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
const record = JSON.parse(readFileSync(new URL('./compile-result-original-controls.json', import.meta.url)));
const hash = text => createHash('sha256').update(text).digest('hex');
const tokens = source => [...source.slice(source.indexOf('test "')).split('\n')
  .filter(line => !line.trim().startsWith('#|') && !line.trim().startsWith('//')).join('\n')
  .matchAll(/"(?:\\.|[^"\\])*"/g)].map(match => match[0]);

test('compile controls change only the six declared private assertion tokens', () => {
  const actual = tokens(readFileSync('src/query_program/compile_test.mbt', 'utf8'));
  assert.equal(actual.length, record.compileTestTokenCount);
  for (const update of record.privateAssertionUpdates) {
    assert.equal(actual.filter(token => token === update.current).length, 1);
    assert.equal(actual.filter(token => token === update.old).length, 0);
  }
  const previous = actual.map(token => record.privateAssertionUpdates
    .find(update => update.current === token)?.old ?? token);
  assert.equal(hash(previous.join('\n')), record.compileTestTokenSha256);
});

test('parenthesized key oracle preserves the original full Values and JOIN contracts', () => {
  const source = readFileSync('src/query_program/join_parenthesized_key_test.mbt', 'utf8');
  const literal = name => {
    const start = source.indexOf(`fn ${name}(`);
    assert.ok(start >= 0);
    const lines = source.slice(start, source.indexOf('\n}\n', start)).split('\n')
      .map(line => line.trim()).filter(line => line.startsWith('#|'));
    assert.equal(lines.length, 1);
    return lines[0].slice(2);
  };
  const original = literal('staged_parenthesized_join_expected');
  assert.equal(hash(original), record.parenthesizedOriginalLiteralSha256);
  const strings = tokens(source);
  assert.equal(strings.length, record.parenthesizedTestTokenCount);
  assert.equal(hash(strings.join('\n')), record.parenthesizedTestTokenSha256);
  const expected = JSON.parse(original);
  const main = expected.stages[2];
  const coordinates = new Map([['l', 'aql_script_seed_2'], ['r', 'aql_script_seed_3'],
    ['aql_join_output', 'aql_join_output_5']]);
  const seeds = expected.stages.slice(0, 2).map((stage, index) => {
    assert.equal(stage.steps.length, 1);
    return {values: stage.steps[0].values, as: `aql_script_seed_${2 + index}`};
  });
  for (const step of main.steps) {
    step.from = coordinates.get(step.from);
    step.join.with = coordinates.get(step.join.with);
    step.as = coordinates.get(step.as);
  }
  main.results.rows.from = coordinates.get(main.results.rows.from);
  main.inputs = {};
  main.steps = [...seeds, ...main.steps];
  expected.stages = [main];
  assert.deepEqual(JSON.parse(literal('parenthesized_join_expected')), expected);
});
