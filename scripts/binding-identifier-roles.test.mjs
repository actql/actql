import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {bindingIdentifierSuccesses as normal, bindingIdentifierRefusals as refused,
  quotedIdentifierSuccesses, quotedIdentifierRefusals} from './fixtures/quoted-identifier-source-input.mjs';

test('binding roles retain independent machine values, ordered contracts and both text formats', () => {
  assert.equal(normal.length, 10);
  assert.equal(refused.length, 8);
  for (const name of ['id', 'ROWS']) {
    const control = normal.find(item => item.name === 'identifier-role-json-' + name);
    const program = JSON.parse(control.text);
    assert.deepEqual(program.stages[0].steps[0].values, {
      schema: {[name]: {type: 'number', nullable: false}}, rows: [{[name]: 1}],
    });
    assert.deepEqual(program.stages[0].results.rows.fields, [name]);
    assert.deepEqual(control.expected, [{[name]: 1}]);
  }
  for (const suffix of ['quoted-with', 'ordinary-with', 'quoted-range', 'quoted-output']) {
    const pair = normal.filter(item => item.name.endsWith('-' + suffix));
    assert.deepEqual(pair.map(item => item.format), ['sql', 'aql-text']);
    assert.equal(pair[0].text, pair[1].text);
    assert.deepEqual(pair[0].expected, pair[1].expected);
    assert.deepEqual(pair[0].columns, pair[1].columns);
  }
  assert.ok(normal.every(item => item.sourceReadCount === 0 && item.sourceReadSessionCount === 0));
});

test('reserved refusals keep exact authored source and the existing public refusal code', () => {
  const expected = [
    'WITH ROWS AS (SELECT 1 AS id) SELECT id FROM ROWS',
    'WITH rOwS AS (SELECT 1 AS id) SELECT id FROM rOwS',
    'SELECT 1 AS ROWS',
    'SELECT id FROM (SELECT 1 AS id) AS ROWS',
  ];
  assert.deepEqual(refused.map(item => item.text), expected.flatMap(text => [text, text]));
  assert.ok(refused.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  assert.ok(normal.every(item => quotedIdentifierSuccesses.includes(item)));
  assert.ok(refused.every(item => quotedIdentifierRefusals.includes(item)));
});

test('role cases use the existing delivered quoted-identifier selection and ordinary corpus', () => {
  const acceptance = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  const consumer = readFileSync('scripts/test-packed-public-query.mjs', 'utf8');
  assert.ok(acceptance.includes('successes: quotedIdentifierSuccesses, refusals: quotedIdentifierRefusals'));
  assert.ok(acceptance.includes('scopeInputs.successes.push(...quotedIdentifierSuccesses)'));
  assert.ok(consumer.includes("['scripts/fixtures/quoted-identifier-source-input.mjs', 'quoted-identifier-source-input.mjs']"));
  assert.ok(consumer.includes('--quoted-identifiers-only'));
});
