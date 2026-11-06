// Independent inclusive-comparison and three-valued AND expectations.
// Retain one common BETWEEN node; never expand its tested operand.
const boolean = (name, nullable = false) => ({name, contract: {type: 'boolean', nullable}});
const number = name => ({name, contract: {type: 'number', nullable: false}});
const literal = value => ({literal: value});
const range = (value, low, high) => ({between: [value, low, high]});
function control(expression, params) {
  return {version: 'actql/0.1', id: 'fixture.between', ...(params ? {params} : {}),
    stages: [{id: 'main', inputs: {}, steps: [
      {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
      {from: 'seed', derive: {value: expression}}, {select: ['value'], as: 'selected'},
    ], results: {rows: {from: 'selected', fields: ['value']}}}],
    results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}
const success = (name, text, expected, columns, extra = {}) => ({
  name: 'between-' + name, format: 'sql', text, expected, columns,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
const params = {p: {type: 'number', nullable: true}};
const parameter = range({$param: 'p'}, literal(1), literal(2));
export const betweenSuccesses = [
  success('json-null-boundary', JSON.stringify(control(range(literal(3), literal(4), literal(null)))),
    [{value: false}], [boolean('value', true)], {format: 'json'}),
  success('json-parameter', JSON.stringify(control(parameter, params)),
    [{value: true}], [boolean('value', true)], {format: 'json', parameters: {p: 2}}),
  success('inclusive-and-reversed',
    'SELECT 1 BETWEEN 1 AND 2 AS lower, 2 BETWEEN 1 AND 2 AS upper, 3 BETWEEN 1 AND 2 AS outside, 1 BETWEEN 2 AND 0 AS reversed',
    [{lower: true, upper: true, outside: false, reversed: false}],
    ['lower', 'upper', 'outside', 'reversed'].map(name => boolean(name))),
  success('null-truth-table',
    'SELECT 1 BETWEEN NULL AND 0 AS false_first, 3 BETWEEN 4 AND NULL AS false_second, 1 BETWEEN NULL AND 2 AS unknown, NULL BETWEEN 1 AND 2 AS null_value, 3 NOT BETWEEN 4 AND NULL AS true_not',
    [{false_first: false, false_second: false, unknown: null, null_value: null, true_not: true}],
    ['false_first', 'false_second', 'unknown', 'null_value', 'true_not'].map(name => boolean(name, true))),
  success('parameter-match', 'SELECT @p BETWEEN 1 AND 2 AS value',
    [{value: true}], [boolean('value', true)], {parameterDeclarations: params, parameters: {p: 2}}),
  success('parameter-null', 'SELECT @P BETWEEN 1 AND 2 AS value',
    [{value: null}], [boolean('value', true)], {parameterDeclarations: params, parameters: {p: null}}),
  success('lazy-branches',
    'SELECT IF(FALSE, (1 / 0) BETWEEN 0 AND 2, FALSE) AS skipped, CASE WHEN TRUE THEN TRUE ELSE 1 BETWEEN 2 AND (1 / 0) END AS chosen',
    [{skipped: false, chosen: true}], [boolean('skipped'), boolean('chosen')]),
  success('empty', 'SELECT CAST(NULL AS FLOAT64) BETWEEN 1 AND 2 AS value WHERE FALSE',
    [], [boolean('value', true)]),
];
const sourceRows = [{id: 2, amount: 2}, {id: 1, amount: 1}, {id: 3, amount: 2},
  {id: 4, amount: 3}, {id: 5, amount: null}, {id: 0, amount: 99}];
const filtered = [{id: 1}, {id: 2}, {id: 3}];
const acquired = {version: 'actql/0.1', id: 'fixture.between_rows', stages: [
  {id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: literal(true)}, {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', filter: range({field: 'amount'}, literal(1), literal(2))},
      {select: ['id']}, {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'selected'}],
    results: {rows: {from: 'selected', fields: ['id']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const captured = {sourceRows, sourceReadCount: 1, sourceReadSessionCount: 1};
betweenSuccesses.push(
  success('acquired-json', JSON.stringify(acquired), filtered, [number('id')], {format: 'json', ...captured}),
  success('acquired-sql', 'SELECT id FROM records WHERE amount BETWEEN 1 AND 2 ORDER BY id', filtered, [number('id')], captured),
  success('acquired-pipe', 'FROM records |> WHERE amount BETWEEN 1 AND 2 |> SELECT id |> ORDER BY id', filtered, [number('id')], {format: 'aql-text', ...captured}),
);
export const betweenRefusals = [
  {name: 'between-incompatible-types', format: 'sql', text: "SELECT 1 BETWEEN 'a' AND 'z' AS value", expectedCode: 'ClientProgramInvalidInput'},
  {name: 'between-incompatible-boolean', format: 'sql', text: 'SELECT TRUE BETWEEN 1 AND 2 AS value', expectedCode: 'ClientProgramInvalidInput'},
  {name: 'between-undeclared-parameter', format: 'sql', text: 'SELECT @missing BETWEEN 1 AND 2 AS value'},
  {name: 'between-missing-upper', format: 'sql', text: 'SELECT 1 BETWEEN 0 AS value'},
];
export const betweenExecutionFailures = [
  // FALSE from the lower comparison does not erase evaluation of the upper operand.
  'SELECT 1 BETWEEN 2 AND (1 / 0) AS value',
  'SELECT (1 / 0) BETWEEN 0 AND 2 AS value',
].map((text, index) => ({name: 'between-demanded-failure-' + index, format: 'sql', text,
  resultNames: ['main'], sourceReadSessionCount: 0}));
