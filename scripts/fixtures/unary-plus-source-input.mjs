// Independent expectations follow numeric identity, NULL propagation and
// alias-first ORDER resolution. No expected value comes from compiler output.
const column = (name, nullable = false) => ({name, contract: {type: 'number', nullable}});
const sourceRows = [{id: 1, amount: -4}, {id: 2, amount: null},
  {id: 3, amount: 0}, {id: 3, amount: 0}];
const sourceExpected = [{id: 1, value: -4}, {id: 2, value: null},
  {id: 3, value: 0}, {id: 3, value: 0}];
const control = {version: 'actql/0.1', id: 'fixture.unary_plus', stages: [{
  id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'seed', derive: {value: {negate: {negate: {literal: -7}}}}},
    {select: ['value'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['value']}},
}], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, columns, extra = {}) => ({
  name: 'unary-plus-' + name, format: 'sql', text, expected, columns,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
const acquired = (name, text, expected, extra = {}) => success(name, text, expected,
  [column('id'), column('value', true)], {
    sourceRows, sourceReadCount: undefined, sourceReadSessionCount: 1, ...extra,
  });
export const unaryPlusSuccesses = [
  success('json-control', JSON.stringify(control), [{value: -7}], [column('value')], {format: 'json'}),
  acquired('sql-field', 'SELECT id, +amount AS value FROM records WHERE id > 0 ORDER BY id', sourceExpected),
  acquired('pipe-field', 'FROM records |> WHERE id > 0 |> SELECT id, +amount AS value |> ORDER BY id', sourceExpected, {format: 'aql-text'}),
  success('negative-parameter', 'SELECT +@n AS value', [{value: -7}], [column('value')], {
    parameterDeclarations: {n: {type: 'number', nullable: false}}, parameters: {n: -7},
  }),
  success('nullable-parameter', 'SELECT +@n AS value', [{value: null}], [column('value', true)], {
    parameterDeclarations: {n: {type: 'number', nullable: true}}, parameters: {n: null},
  }),
  success('lazy-operand', 'SELECT +IF(TRUE, -7, 1 / 0) AS value', [{value: -7}], [column('value')]),
  acquired('empty', 'SELECT id, +amount AS value FROM records WHERE FALSE ORDER BY id', []),
  acquired('order-output-alias', 'SELECT id, -amount AS amount FROM records ORDER BY +amount NULLS LAST, id',
    [{id: 3, amount: 0}, {id: 3, amount: 0}, {id: 1, amount: 4}, {id: 2, amount: null}], {columns: [column('id'), column('amount', true)]}),
  acquired('order-qualified-input', 'SELECT id, -amount AS amount FROM records ORDER BY +records.amount NULLS LAST, id',
    [{id: 1, amount: 4}, {id: 3, amount: 0}, {id: 3, amount: 0}, {id: 2, amount: null}], {columns: [column('id'), column('amount', true)]}),
];
export const unaryPlusRefusals = [
  {name: 'string-literal', text: "SELECT +'secret-value' AS value"},
  {name: 'boolean-expression', text: 'SELECT +CAST(TRUE AS BOOL) AS value'},
  {name: 'string-parameter', text: 'SELECT +@n AS value',
    parameterDeclarations: {n: {type: 'string'}}, parameters: {n: 'secret-value'}},
  {name: 'undeclared-parameter', text: 'SELECT +@missing AS value'},
].map(value => ({...value, name: 'unary-plus-' + value.name, format: 'sql'}));
export const unaryPlusExecutionFailures = [{
  name: 'unary-plus-demanded-operand', format: 'sql',
  text: 'SELECT +(1 / 0) AS value', resultNames: ['answer'], sourceReadSessionCount: 0,
}];
