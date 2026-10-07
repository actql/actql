// Authored from the selected finite-number ceiling law, not compiler output.
const column = (name, nullable = false) => ({name, contract: {type: 'number', nullable}});
const sourceRows = [{id: 1, amount: 2.3}, {id: 2, amount: null},
  {id: 3, amount: -2.3}, {id: 3, amount: -2.3}];
const sourceExpected = [{id: 1, value: 3}, {id: 2, value: null},
  {id: 3, value: -2}, {id: 3, value: -2}];
const control = {version: 'actql/0.1', id: 'fixture.ceiling', stages: [{
  id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'seed', derive: {value: {negate: {floor: {subtract: [{literal: 0}, {literal: -2.3}]}}}}},
    {select: ['value'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['value']}},
}], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, columns, extra = {}) => ({
  name: 'ceiling-' + name, format: 'sql', text, expected, columns,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
const acquired = (name, text, expected, extra = {}) => success(name, text, expected,
  [column('id'), column('value', true)], {
    sourceRows, sourceReadCount: undefined, sourceReadSessionCount: 1, ...extra,
  });
export const ceilingSuccesses = [
  success('json-control', JSON.stringify(control), [{value: -2}], [column('value')], {format: 'json'}),
  success('fractional-and-integral',
    'SELECT CEIL(2.3) AS positive, CEILING(-2.3) AS negative, CEIL(2) AS integral, CEILING(-0.1) AS zero',
    [{positive: 3, negative: -2, integral: 2, zero: 0}],
    ['positive', 'negative', 'integral', 'zero'].map(name => column(name))),
  acquired('sql-field', 'SELECT id, CEIL(amount) AS value FROM records WHERE id > 0 ORDER BY id', sourceExpected),
  acquired('pipe-field', 'FROM records |> WHERE id > 0 |> SELECT id, CEILING(amount) AS value |> ORDER BY id', sourceExpected, {format: 'aql-text'}),
  success('negative-parameter', 'SELECT CEILING(@n) AS value', [{value: -2}], [column('value')], {
    parameterDeclarations: {n: {type: 'number', nullable: false}}, parameters: {n: -2.3},
  }),
  success('nullable-parameter', 'SELECT CEIL(@n) AS value', [{value: null}], [column('value', true)], {
    parameterDeclarations: {n: {type: 'number', nullable: true}}, parameters: {n: null},
  }),
  success('literal-null', 'SELECT CEIL(NULL) AS value, CEILING(CAST(NULL AS FLOAT64)) AS typed_value',
    [{value: null, typed_value: null}], [column('value', true), column('typed_value', true)]),
  success('finite-extremes', 'SELECT CEIL(5e-324) AS tiny, CEILING(1.7976931348623157e308) AS large',
    [{tiny: 1, large: 1.7976931348623157e308}], [column('tiny'), column('large')]),
  success('lazy-operand', 'SELECT CEIL(IF(TRUE, 2.3, 1 / 0)) AS value', [{value: 3}], [column('value')]),
  acquired('empty', 'SELECT id, CEILING(amount) AS value FROM records WHERE FALSE ORDER BY id', []),
  acquired('order-output-alias', 'SELECT id, -amount AS amount FROM records ORDER BY CEIL(amount) NULLS LAST, id',
    [{id: 1, amount: -2.3}, {id: 3, amount: 2.3}, {id: 3, amount: 2.3}, {id: 2, amount: null}], {columns: [column('id'), column('amount', true)]}),
  acquired('order-qualified-input', 'SELECT id, -amount AS amount FROM records ORDER BY CEILING(records.amount) NULLS LAST, id',
    [{id: 3, amount: 2.3}, {id: 3, amount: 2.3}, {id: 1, amount: -2.3}, {id: 2, amount: null}], {columns: [column('id'), column('amount', true)]}),
];
export const ceilingRefusals = [
  {name: 'zero-arguments', text: 'SELECT CEIL() AS value'},
  {name: 'two-arguments', text: 'SELECT CEILING(1, 2) AS value'},
  {name: 'string-literal', text: "SELECT CEIL('secret-value') AS value"},
  {name: 'boolean-expression', text: 'SELECT CEILING(CAST(TRUE AS BOOL)) AS value'},
  {name: 'decimal-overload', text: "SELECT CEIL(CAST('1.25' AS DECIMAL(8,3))) AS value"},
  {name: 'string-parameter', text: 'SELECT CEIL(@n) AS value',
    parameterDeclarations: {n: {type: 'string'}}, parameters: {n: 'secret-value'}},
  {name: 'undeclared-parameter', text: 'SELECT CEILING(@missing) AS value'},
].map(value => ({...value, name: 'ceiling-' + value.name, format: 'sql'}));
export const ceilingExecutionFailures = [{
  name: 'ceiling-demanded-operand', format: 'sql',
  text: 'SELECT CEIL(1 / 0) AS value', resultNames: ['answer'], sourceReadSessionCount: 0,
}];
