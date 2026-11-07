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

// The ordinary JSON control independently fixes the capture, numeric key,
// multiplicity, NULL group, column contracts and output order.
const groupColumns = [column('bucket', true), column('n')];
const groupExpected = [{bucket: -3, n: 1}, {bucket: 1, n: 2}, {bucket: null, n: 1}];
const groupRows = [...sourceRows, {id: 0, amount: 100}];
const groupControl = {version: 'actql/0.1', id: 'fixture.group_signed_literal', stages: [
  {id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {key: {add: [{field: 'amount'}, {literal: 1}]}}},
      {group: {by: ['key'], aggregates: {n: {fn: 'count'}}}},
      {sort: [{field: 'key', dir: 'asc', nulls: 'last'}]},
      {select: [{bucket: 'key'}, 'n'], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['bucket', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const grouped = (name, text, extra = {}) => acquired('group-' + name, text,
  groupExpected, {columns: groupColumns, sourceRows: groupRows, ...extra});
// Preserve the former refusal's implicit ordinary source rows explicitly.
// Signed expression zero normalizes to +0, so both equal GROUP expressions
// preserve amount, NULL and multiplicity. No ORDER BY promises a row order.
const signedZeroSourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}];
const signedZeroGroups = [{bucket: 20, n: 1}, {bucket: 30, n: 2}, {bucket: null, n: 1}];
export const signedLiteralSuccesses = [
  grouped('json-control', JSON.stringify(groupControl), {format: 'json'}),
  grouped('selected-plus', 'SELECT amount + +1 AS bucket, COUNT(*) AS n FROM records '
    + 'WHERE id > 0 GROUP BY amount + 1 ORDER BY bucket NULLS LAST'),
  grouped('key-plus-repeated', 'SELECT amount + 1 AS bucket, COUNT(*) AS n FROM records '
    + 'WHERE id > 0 GROUP BY amount + +(1.0), records.amount + 1e0 ORDER BY bucket NULLS LAST'),
  grouped('sql-pipe-tail', 'SELECT amount + +(-(-1)) AS bucket, COUNT(*) AS n FROM records '
    + 'WHERE id > 0 GROUP BY amount + 1 |> WHERE n > 1 |> ORDER BY bucket |> LIMIT 1',
  {expected: [{bucket: 1, n: 2}]}),
  grouped('empty', 'SELECT amount + +1 AS bucket, COUNT(*) AS n FROM records '
    + 'GROUP BY amount + 1 ORDER BY bucket NULLS LAST', {sourceRows: [], expected: []}),
  success('signed-literal-negative-zero-key', 'SELECT amount + -(-0) AS bucket, COUNT(*) AS n FROM records '
    + 'GROUP BY amount + -(-0)', signedZeroGroups, groupColumns, {
    sourceRows: signedZeroSourceRows, sourceReadCount: undefined, sourceReadSessionCount: 1,
    results: {main: {rows: signedZeroGroups, columns: groupColumns, unordered: true}},
  }),
  acquired('distinct-signed-literal', 'SELECT DISTINCT amount + +1 AS value FROM records '
    + 'ORDER BY records.amount + 1 NULLS LAST', [{value: -3}, {value: 1}, {value: null}],
  {columns: [column('value', true)]}),
  acquired('distinct-pipe-signed-literal', 'FROM records |> SELECT DISTINCT amount + 1 AS value '
    + '|> ORDER BY records.amount + +(1.0) NULLS LAST', [{value: -3}, {value: 1}, {value: null}],
  {format: 'aql-text', columns: [column('value', true)]}),
  acquired('signed-literal-alias-receiver', 'SELECT DISTINCT -amount + +1 AS amount FROM records '
    + 'ORDER BY -amount + 1 NULLS LAST', [{amount: 5}, {amount: 1}, {amount: null}],
  {columns: [column('amount', true)]}),
];
unaryPlusSuccesses.push(...signedLiteralSuccesses);
export const unaryPlusRefusals = [
  {name: 'string-literal', text: "SELECT +'secret-value' AS value"},
  {name: 'boolean-expression', text: 'SELECT +CAST(TRUE AS BOOL) AS value'},
  {name: 'string-parameter', text: 'SELECT +@n AS value',
    parameterDeclarations: {n: {type: 'string'}}, parameters: {n: 'secret-value'}},
  {name: 'undeclared-parameter', text: 'SELECT +@missing AS value'},
].map(value => ({...value, name: 'unary-plus-' + value.name, format: 'sql'}));
export const signedLiteralRefusals = [
  {name: 'different-key', text: 'SELECT amount + +2 AS bucket, COUNT(*) AS n FROM records '
    + 'GROUP BY amount + 1', expectedCode: 'ClientProgramInvalidInput'},
  {name: 'removed-input', text: 'SELECT DISTINCT amount + +1 AS value FROM records ORDER BY id',
    expectedCode: 'ClientProgramImplementationLimit'},
].map(value => ({...value, name: 'unary-plus-signed-literal-' + value.name, format: 'sql'}));
unaryPlusRefusals.push(...signedLiteralRefusals);
export const unaryPlusExecutionFailures = [{
  name: 'unary-plus-demanded-operand', format: 'sql',
  text: 'SELECT +(1 / 0) AS value', resultNames: ['main'], sourceReadSessionCount: 0,
}];

// GROUP validates the original unary-plus key, then reuses its numeric value.
// The independently authored Program retains both negations and never restores
// an ungrouped input. ID 0 must be excluded; duplicate zero and NULL keys remain.
const groupedRows = [...sourceRows, {id: 0, amount: 100}];
const groupedColumns = [column('bucket', true), column('n')];
const groupedExpected = [{bucket: -4, n: 1}, {bucket: 0, n: 2}, {bucket: null, n: 1}];
const groupedControl = {version: 'actql/0.1', id: 'fixture.group_unary_plus', stages: [
  {id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}}, steps: [
    {from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
    {select: ['amount', 'id'], as: 'captured'},
  ], results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}}, steps: [
    {from: 'records', derive: {key: {negate: {negate: {field: 'amount'}}}}},
    {group: {by: ['key'], aggregates: {n: {fn: 'count'}}}},
    {select: [{bucket: 'key'}, 'n']},
    {sort: [{field: 'bucket', dir: 'asc', nulls: 'last'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['bucket', 'n']}}},
], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const groupedValue = (name, text, extra = {}) => success('group-value-' + name, text,
  groupedExpected, groupedColumns, {sourceRows: groupedRows,
    sourceReadCount: undefined, sourceReadSessionCount: 1, ...extra});
export const groupedUnaryPlusSuccesses = [
  groupedValue('json-control', JSON.stringify(groupedControl), {format: 'json'}),
  groupedValue('sql-key-operand', 'SELECT amount AS bucket, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY +amount ORDER BY bucket NULLS LAST'),
  groupedValue('nested-repeated-key', 'SELECT records.amount AS bucket, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY +(+records.amount), amount ORDER BY bucket NULLS LAST'),
  groupedValue('head-pipe-consumer', 'SELECT amount AS bucket, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY +(records.amount) |> WHERE n > 1 |> ORDER BY bucket NULLS LAST |> LIMIT 1',
    {expected: [{bucket: 0, n: 2}], format: 'aql-text'}),
  groupedValue('empty', 'SELECT amount AS bucket, COUNT(*) AS n FROM records GROUP BY +amount ORDER BY bucket NULLS LAST',
    {sourceRows: [], expected: []}),
  groupedValue('order-output-alias', 'SELECT -amount AS amount, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY +records.amount ORDER BY amount NULLS LAST',
    {expected: [{amount: 0, n: 2}, {amount: 4, n: 1}, {amount: null, n: 1}],
      columns: [column('amount', true), column('n')]}),
  groupedValue('order-qualified-input', 'SELECT -amount AS amount, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY +records.amount ORDER BY records.amount NULLS LAST',
    {expected: [{amount: 4, n: 1}, {amount: 0, n: 2}, {amount: null, n: 1}],
      columns: [column('amount', true), column('n')]}),
];
export const groupedUnaryPlusRefusals = [
  {name: 'nonnumeric-key', text: "SELECT CAST('value' AS STRING) AS label, COUNT(*) AS n FROM records GROUP BY +CAST('value' AS STRING)"},
  {name: 'ungrouped-input', text: 'SELECT id, COUNT(*) AS n FROM records GROUP BY +amount'},
  {name: 'expired-range', text: 'SELECT amount AS kept, COUNT(*) AS n FROM records GROUP BY +amount |> SELECT records.amount', format: 'aql-text'},
].map(item => ({format: 'sql', ...item, name: 'unary-plus-group-' + item.name,
  code: 'ClientProgramInvalidInput'}));
unaryPlusSuccesses.push(...groupedUnaryPlusSuccesses);
unaryPlusRefusals.push(...groupedUnaryPlusRefusals);
unaryPlusExecutionFailures.push({name: 'unary-plus-group-demanded-key', format: 'sql',
  text: 'SELECT 1 / 0 AS value, COUNT(*) AS n GROUP BY +(1 / 0)',
  resultNames: ['main'], sourceReadSessionCount: 0});
