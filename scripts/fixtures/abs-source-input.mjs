// Independent vectors from the finite binary64 ABS contract.
const column = (name, nullable = false) => ({name, contract: {type: 'number', nullable}});
const sourceRows = [{id: 1, amount: -4}, {id: 2, amount: null},
  {id: 3, amount: -9}, {id: 3, amount: -9}];
const sourceExpected = [{id: 1, value: 4}, {id: 2, value: null},
  {id: 3, value: 9}, {id: 3, value: 9}];
const control = {version: 'actql/0.1', id: 'fixture.abs', stages: [{
  id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'seed', derive: {value: {abs: {literal: -9}}}},
    {select: ['value'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['value']}},
}], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, columns, extra = {}) => ({
  name: 'abs-' + name, format: 'sql', text, expected, columns,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
const acquired = (name, text, expected, extra = {}) => success(name, text, expected,
  [column('id'), column('value', true)], {
    sourceRows, sourceReadCount: undefined, sourceReadSessionCount: 1, ...extra,
  });
export const absSuccesses = [
  success('json-control', JSON.stringify(control), [{value: 9}], [column('value')], {format: 'json'}),
  // A signed SQL expression normalizes zero; canonical JSON and Parameter
  // negative-zero inputs retain their separate admission refusal.
  success('authored-negative-zero', 'SELECT ABS(-0.0) AS value', [{value: 0}], [column('value')]),
  success('finite-values',
    'SELECT ABS(0) AS zero, ABS(-0.25) AS fractional, ABS(-2.25) AS exact, ABS(0 * -1) AS negative_zero',
    [{zero: 0, fractional: 0.25, exact: 2.25, negative_zero: 0}],
    ['zero', 'fractional', 'exact', 'negative_zero'].map(name => column(name))),
  success('finite-extremes',
    'SELECT ABS(-5e-324) AS tiny, ABS(-1.7976931348623157e308) AS large',
    [{tiny: 5e-324, large: 1.7976931348623157e308}],
    [column('tiny'), column('large')]),
  acquired('sql-field', 'SELECT id, ABS(amount) AS value FROM records WHERE id > 0 ORDER BY id', sourceExpected),
  acquired('pipe-field', 'FROM records |> WHERE id > 0 |> SELECT id, ABS(amount) AS value |> ORDER BY id', sourceExpected, {format: 'aql-text'}),
  success('number-parameter', 'SELECT ABS(@n) AS value', [{value: 4}], [column('value')], {
    parameterDeclarations: {n: {type: 'number', nullable: false}}, parameters: {n: -4},
  }),
  success('nullable-parameter', 'SELECT ABS(@n) AS value', [{value: null}], [column('value', true)], {
    parameterDeclarations: {n: {type: 'number', nullable: true}}, parameters: {n: null},
  }),
  success('literal-null', 'SELECT ABS(NULL) AS value, ABS(CAST(NULL AS FLOAT64)) AS typed_value',
    [{value: null, typed_value: null}], [column('value', true), column('typed_value', true)]),
  success('lazy-operand', 'SELECT ABS(IF(TRUE, -9, 1 / 0)) AS value', [{value: 9}], [column('value')]),
  success('lazy-failure', 'SELECT IF(FALSE, ABS(1 / 0), 7) AS value', [{value: 7}], [column('value')]),
  acquired('empty-failure', 'SELECT id, ABS(1 / 0) AS value FROM records WHERE FALSE ORDER BY id', [],
    {columns: [column('id'), column('value')]}),
  success('safe-integer-boundary', 'SELECT ABS(-9007199254740991) AS value',
    [{value: 9007199254740991}], [column('value')]),
  success('quoted-spelling', 'SELECT `AbS`(9) AS value', [{value: 9}], [column('value')]),
];
export const absRefusals = [
  {name: 'zero-arguments', text: 'SELECT ABS() AS value'},
  {name: 'two-arguments', text: 'SELECT ABS(1, 2) AS value'},
  {name: 'string-literal', text: "SELECT ABS('secret-value') AS value"},
  {name: 'boolean-expression', text: 'SELECT ABS(CAST(TRUE AS BOOL)) AS value'},
  {name: 'decimal-overload', text: "SELECT ABS(CAST('4' AS DECIMAL(8,0))) AS value"},
  {name: 'string-parameter', text: 'SELECT ABS(@n) AS value',
    parameterDeclarations: {n: {type: 'string'}}, parameters: {n: 'secret-value'}},
  {name: 'array-domain', text: 'SELECT ABS([1, 2]) AS value'},
  {name: 'undeclared-parameter', text: 'SELECT ABS(@missing) AS value'},
].map(value => ({...value, name: 'abs-' + value.name, format: 'sql', expectedCode: 'ClientProgramInvalidInput'}));
export const absExecutionFailures = [
  {name: 'demanded-operand', text: 'SELECT ABS(1 / 0) AS value', sourceReadSessionCount: 0},
  {name: 'failure-after-valid-row', text: 'SELECT id, ABS(1 / amount) AS value FROM records ORDER BY id',
    sourceRows: [{id: 1, amount: -2}, {id: 2, amount: 0}], sourceReadSessionCount: 1},
].map(value => ({...value, name: 'abs-' + value.name, format: 'sql', resultNames: ['main']}));
