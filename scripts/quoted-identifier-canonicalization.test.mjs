import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {canonicalQuotedIdentifierProgram, canonicalQuotedIdentifierSuccesses,
  canonicalQuotedIdentifierRefusals, quotedIdentifierSuccesses, quotedIdentifierRefusals}
  from './fixtures/quoted-identifier-source-input.mjs';

test('canonical names and complete JSON control use independent common contracts', () => {
  const program = JSON.parse(canonicalQuotedIdentifierSuccesses[0].text);
  assert.deepEqual(program, canonicalQuotedIdentifierProgram);
  assert.deepEqual(program.stages[0].steps[0].values, {
    schema: {'é': {type: 'number', nullable: false}, 'line\nname': {type: 'number', nullable: false}},
    rows: [{'é': 1, 'line\nname': 2}],
  });
  assert.deepEqual(program.stages[0].results.rows.fields, ['é', 'line\nname']);
  assert.deepEqual(canonicalQuotedIdentifierSuccesses[1].expected, [{'é': 1, 'line\nname': 2}]);
});

test('STRING values keep decomposed Unicode and CR while their column names canonicalize', () => {
  const fixture = canonicalQuotedIdentifierSuccesses.find(item => item.name.endsWith('exact-string-values'));
  assert.deepEqual(fixture.expected, [{'é': 'e\u0301\r\n', 'line\nname': '\r'}]);
  assert.deepEqual(fixture.columns, [
    {name: 'é', contract: {type: 'string', nullable: false, max_utf8_bytes: 5}},
    {name: 'line\nname', contract: {type: 'string', nullable: false, max_utf8_bytes: 1}},
  ]);
  const pipe = canonicalQuotedIdentifierSuccesses.find(item => item.name.endsWith('pipe-rename-filter-order'));
  assert.deepEqual(pipe.expected, [{'line\nname': 2}, {'line\nname': 3}, {'line\nname': 3}]);
  assert.equal(pipe.sourceReadSessionCount, 1);
  assert.deepEqual(canonicalQuotedIdentifierSuccesses.find(item => item.name.endsWith('empty')).expected, []);
  const parameter = canonicalQuotedIdentifierSuccesses.find(item => item.name.endsWith('parameter'));
  assert.deepEqual(parameter.parameterDeclarations, {p: {type: 'number'}});
  assert.deepEqual(parameter.parameters, {p: 20});
});

test('normal and focused public consumers retain the name cases and exact typed refusals', () => {
  assert.equal(canonicalQuotedIdentifierSuccesses.length, 10);
  assert.equal(canonicalQuotedIdentifierRefusals.length, 3);
  assert.equal(quotedIdentifierSuccesses.length, 29);
  assert.equal(quotedIdentifierRefusals.length, 20);
  assert.ok(canonicalQuotedIdentifierRefusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  assert.equal(canonicalQuotedIdentifierRefusals[2].format, 'aql-text',
    'the retired-range refusal must reach Pipe lowering, not SQL format rejection');
  const all = [...quotedIdentifierSuccesses, ...quotedIdentifierRefusals];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
  const harness = readFileSync('scripts/fixtures/packed-public-query.mjs', 'utf8');
  assert.ok(harness.includes('successes: quotedIdentifierSuccesses, refusals: quotedIdentifierRefusals'));
  assert.ok(harness.includes('scopeInputs.successes.push(...quotedIdentifierSuccesses)'));
  assert.ok(harness.includes('scopeInputs.refusals.push(...quotedIdentifierRefusals)'));
});
