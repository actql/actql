// Authored from IFNULL's two-argument COALESCE semantics, never from compiler
// output. FALSE and empty STRING are values; only SQL NULL selects fallback.
const column = (name, type, nullable = false) => ({name, contract: {type, nullable}});
const control = {version: 'actql/0.1', id: 'fixture.ifnull', stages: [{
  id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}},
      rows: [{unit: true}]}},
    {from: 'seed', derive: {value: {coalesce: [{literal: null}, {literal: 7}]}}},
    {select: ['value'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['value']}},
}], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, columns, extra = {}) => ({
  name: 'ifnull-' + name, format: 'sql', text, expected, columns,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
export const ifnullSuccesses = [
  success('json-control', JSON.stringify(control), [{value: 7}],
    [column('value', 'number')], {format: 'json'}),
  success('null-fallback', 'SELECT IFNULL(NULL, 7) AS value', [{value: 7}],
    [column('value', 'number')]),
  success('lazy-fallback',
    "SELECT IFNULL(1, 1 / 0) AS first, IFNULL(2, CAST('bad' AS FLOAT64)) AS second",
    [{first: 1, second: 2}], [column('first', 'number'), column('second', 'number')]),
  success('false-and-empty', "SELECT IFNULL(FALSE, TRUE) AS flag, IFNULL('', 'fallback') AS value",
    // Literal bounds are 0 and 8 UTF-8 bytes. Common type join retains the
    // larger upper bound even though runtime skips the second operand here.
    [{flag: false, value: ''}], [column('flag', 'boolean'),
      {name: 'value', contract: {type: 'string', nullable: false, max_utf8_bytes: 8}}]),
  success('typed-null', 'SELECT IFNULL(CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64)) AS value',
    [{value: null}], [column('value', 'number', true)]),
  success('pipe', 'SELECT IFNULL(NULL, 7) AS value |> WHERE value = 7 |> SELECT value',
    [{value: 7}], [column('value', 'number')], {format: 'aql-text'}),
  success('empty', 'SELECT IFNULL(NULL, 7) AS value WHERE FALSE', [],
    [column('value', 'number')]),
  success('nullable-parameter', 'SELECT IFNULL(@value, 7) AS value', [{value: 7}],
    [column('value', 'number')], {
      parameterDeclarations: {value: {type: 'number', nullable: true}},
      parameters: {value: null},
    }),
];
export const ifnullRefusals = [
  'SELECT IFNULL(1) AS value',
  'SELECT IFNULL(1, 2, 3) AS value',
  "SELECT IFNULL(1, 'text') AS value",
  'SELECT IFNULL(1, unknown_function(2)) AS value',
  'SELECT IFNULL(@missing, 7) AS value',
  'SELECT IFNULL(NULL, NULL) AS value',
].map((text, index) => ({name: 'ifnull-static-refusal-' + index, format: 'sql', text}));
export const ifnullExecutionFailures = [{
  name: 'ifnull-demanded-failing-fallback', format: 'sql',
  text: 'SELECT IFNULL(CAST(NULL AS FLOAT64), 1 / 0) AS value',
  resultNames: ['answer'], sourceReadSessionCount: 0,
}];
