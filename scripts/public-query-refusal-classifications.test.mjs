import assert from 'node:assert/strict';
import test from 'node:test';
import {rightJoinRefusals} from './fixtures/right-join-source-input.mjs';
import {replaceCallRefusals} from './fixtures/replace-call-source-input.mjs';
import {analyticCountifRefusals} from './fixtures/analytic-countif-source-input.mjs';
import {analyticPropertyRefusals} from './fixtures/analytic-property-source-input.mjs';

// These expected inputs and policies are authored independently of the compiler,
// installed runtime and observed refusal codes. Only these five support gaps
// may override the ordinary invalid-input fixture policy.
const declarations = {
  a: {type: 'object', nullable: true, fields: {score: {type: 'number', nullable: false}}},
  b: {type: 'object', nullable: true, fields: {score: {type: 'number', nullable: false}}},
  c: {type: 'object', nullable: true, fields: {score: {type: 'number', nullable: false}}},
  oa: {type: 'object', nullable: false, fields: {score: {type: 'number', nullable: false}}},
  ob: {type: 'object', nullable: false, fields: {score: {type: 'number', nullable: false}}},
  oc: {type: 'object', nullable: false, fields: {score: {type: 'number', nullable: false}}},
};
const parameters = {a: {score: 10}, b: {score: 20}, c: null,
  oa: {score: 30}, ob: {score: 5}, oc: {score: 15}};
const objects = 'WITH objects AS (SELECT 2 AS id, @a AS payload, @oa AS other '
  + 'UNION ALL SELECT 1 AS id, @b AS payload, @ob AS other '
  + 'UNION ALL SELECT 3 AS id, @c AS payload, @oc AS other) ';
const limits = [
  {name: 'right-join-refuse-2', format: 'sql',
    text: 'SELECT l.id FROM records AS l RIGHT JOIN records AS r ON l.id > r.id MAX_OUTPUT_ROWS 10',
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'replace-call-refuse-3', format: 'sql',
    text: "SELECT REPLACE('a', unknown_function('b'), 'c') AS value",
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'replace-call-refuse-5', format: 'sql',
    text: "SELECT ACTQL.REPLACE('a', 'b', 'c') AS value",
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'analytic-countif-refuse-1', format: 'sql',
    text: 'SELECT COUNTIF(amount > 10) OVER (ORDER BY id) AS n FROM records',
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'analytic-property-invalid-5', hostProfile: 'analytic-property', format: 'aql-text',
    text: objects + 'SELECT FIRST_VALUE(payload.score) OVER (ORDER BY id) AS value FROM objects',
    parameterDeclarations: declarations, parameters,
    expectedCode: 'ClientProgramImplementationLimit'},
];
const invalid = [
  {name: 'right-join-refuse-0', format: 'sql',
    text: 'SELECT id FROM records AS l RIGHT JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 10'},
  {name: 'replace-call-refuse-0', format: 'sql',
    text: "SELECT REPLACE('a', 'b') AS value"},
  {name: 'analytic-countif-refuse-0', format: 'sql',
    text: 'SELECT COUNTIF(id) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS n FROM records'},
  {name: 'analytic-property-invalid-6', hostProfile: 'analytic-property', format: 'aql-text',
    text: objects + 'SELECT LAG(payload.score, -1) OVER (ORDER BY id) AS previous FROM objects',
    parameterDeclarations: declarations, parameters},
];
const cases = [...rightJoinRefusals, ...replaceCallRefusals,
  ...analyticCountifRefusals, ...analyticPropertyRefusals];

test('only five independently proven support gaps override refusal classification', () => {
  assert.deepEqual(cases.filter(item => Object.hasOwn(item, 'expectedCode')), limits);
});

test('nearby semantic input violations retain complete original inputs and default policy', () => {
  assert.deepEqual(invalid.map(expected => cases.find(item => item.name === expected.name)), invalid);
  for (const item of cases) {
    assert.equal(Object.hasOwn(item, 'expectedCode'), limits.some(expected => expected.name === item.name), item.name);
  }
});
