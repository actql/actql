// Independent vectors from the existing finite binary64 SQRT contract.
const column = (name, nullable = false) => ({name, contract: {type: 'number', nullable}});
const sourceRows = [{id: 1, amount: 4}, {id: 2, amount: null},
  {id: 3, amount: 9}, {id: 3, amount: 9}];
const sourceExpected = [{id: 1, value: 2}, {id: 2, value: null},
  {id: 3, value: 3}, {id: 3, value: 3}];
const control = {version: 'actql/0.1', id: 'fixture.sqrt', stages: [{
  id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'seed', derive: {value: {sqrt: {literal: 9}}}},
    {select: ['value'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['value']}},
}], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, columns, extra = {}) => ({
  name: 'sqrt-' + name, format: 'sql', text, expected, columns,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
const acquired = (name, text, expected, extra = {}) => success(name, text, expected,
  [column('id'), column('value', true)], {
    sourceRows, sourceReadCount: undefined, sourceReadSessionCount: 1, ...extra,
  });
export const sqrtSuccesses = [
  success('json-control', JSON.stringify(control), [{value: 3}], [column('value')], {format: 'json'}),
  success('finite-values',
    'SELECT SQRT(0) AS zero, SQRT(0.25) AS fractional, SQRT(2.25) AS exact, SQRT(2) AS irrational',
    [{zero: 0, fractional: 0.5, exact: 1.5, irrational: 1.4142135623730951}],
    ['zero', 'fractional', 'exact', 'irrational'].map(name => column(name))),
  success('finite-extremes',
    'SELECT SQRT(5e-324) AS tiny, SQRT(1.7976931348623157e308) AS large',
    [{tiny: 2.2227587494850775e-162, large: 1.3407807929942596e154}],
    [column('tiny'), column('large')]),
  acquired('sql-field', 'SELECT id, SQRT(amount) AS value FROM records WHERE id > 0 ORDER BY id', sourceExpected),
  acquired('pipe-field', 'FROM records |> WHERE id > 0 |> SELECT id, SQRT(amount) AS value |> ORDER BY id', sourceExpected, {format: 'aql-text'}),
  success('number-parameter', 'SELECT SQRT(@n) AS value', [{value: 2}], [column('value')], {
    parameterDeclarations: {n: {type: 'number', nullable: false}}, parameters: {n: 4},
  }),
  success('nullable-parameter', 'SELECT SQRT(@n) AS value', [{value: null}], [column('value', true)], {
    parameterDeclarations: {n: {type: 'number', nullable: true}}, parameters: {n: null},
  }),
  success('literal-null', 'SELECT SQRT(NULL) AS value, SQRT(CAST(NULL AS FLOAT64)) AS typed_value',
    [{value: null, typed_value: null}], [column('value', true), column('typed_value', true)]),
  success('lazy-operand', 'SELECT SQRT(IF(TRUE, 9, 1 / 0)) AS value', [{value: 3}], [column('value')]),
  success('lazy-negative', 'SELECT IF(FALSE, SQRT(-1), 7) AS value', [{value: 7}], [column('value')]),
  acquired('empty-negative', 'SELECT id, SQRT(-1) AS value FROM records WHERE FALSE ORDER BY id', [],
    {columns: [column('id'), column('value')]}),
  success('quoted-spelling', 'SELECT `SqRt`(9) AS value', [{value: 3}], [column('value')]),
];
export const sqrtRefusals = [
  {name: 'zero-arguments', text: 'SELECT SQRT() AS value'},
  {name: 'two-arguments', text: 'SELECT SQRT(1, 2) AS value'},
  {name: 'string-literal', text: "SELECT SQRT('secret-value') AS value"},
  {name: 'boolean-expression', text: 'SELECT SQRT(CAST(TRUE AS BOOL)) AS value'},
  {name: 'decimal-overload', text: "SELECT SQRT(CAST('4' AS DECIMAL(8,0))) AS value"},
  {name: 'string-parameter', text: 'SELECT SQRT(@n) AS value',
    parameterDeclarations: {n: {type: 'string'}}, parameters: {n: 'secret-value'}},
  {name: 'undeclared-parameter', text: 'SELECT SQRT(@missing) AS value'},
].map(value => ({...value, name: 'sqrt-' + value.name, format: 'sql'}));
export const sqrtExecutionFailures = [
  {name: 'negative-domain', text: 'SELECT SQRT(-1) AS value', sourceReadSessionCount: 0},
  {name: 'demanded-operand', text: 'SELECT SQRT(1 / 0) AS value', sourceReadSessionCount: 0},
  {name: 'negative-after-valid-row', text: 'SELECT id, SQRT(amount) AS value FROM records ORDER BY id',
    sourceRows: [{id: 1, amount: 4}, {id: 2, amount: -1}], sourceReadSessionCount: 1},
].map(value => ({...value, name: 'sqrt-' + value.name, format: 'sql', resultNames: ['main']}));
