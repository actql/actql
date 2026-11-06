// Independently authored from ordered, lazy two-argument coalesce semantics.
// No lowerer or product canonicalizer supplies Programs or expected rows.
const rows = [{id: 2, amount: 2}, {id: 1, amount: 1}, {id: 3, amount: 2},
  {id: 4, amount: 3}, {id: 5, amount: null}, {id: 0, amount: 99}];
const number = (name, nullable = false) => ({name, contract: {type: 'number', nullable}});
const grouped = [{value: 0, n: 1}, {value: 1, n: 1}, {value: 2, n: 2}, {value: 3, n: 1}];
const distinct = [{value: 0}, {value: 1}, {value: 2}, {value: 3}];
const key = {coalesce: [{field: 'amount'}, {literal: 0}]};
function control(name, expression, groupedOutput, params) {
  return {version: 'actql/0.1', id: 'fixture.coalesce_reuse_' + name,
    ...(params ? {params} : {}),
    stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
        {select: ['amount', 'id'], as: 'captured'}],
      results: {source: {from: 'captured', fields: ['amount', 'id']}}},
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', derive: {computed: expression}},
        ...(groupedOutput
          ? [{group: {by: ['computed'], aggregates: {n: {fn: 'count'}}}},
            {select: [{value: 'computed'}, 'n']}]
          : [{select: [{value: 'computed'}]}, {distinct: ['value']}]),
        {sort: [{field: 'value', dir: 'asc', nulls: 'first'}], as: 'selected'}],
      results: {rows: {from: 'selected', fields: groupedOutput ? ['value', 'n'] : ['value']}}}],
    results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}
const success = (name, text, expected = grouped, columns = [number('value'), number('n')], extra = {}) => ({
  name: 'ifnull-coalesce-reuse-' + name, format: 'sql', text, expected, columns,
  sourceRows: rows, sourceReadSessionCount: 1, ...extra,
});
const params = {p: {type: 'number', nullable: true}};
const parameterKey = {coalesce: [{field: 'amount'}, {$param: 'p'}]};
const parameterRows = [{value: 1, n: 1}, {value: 2, n: 3}, {value: 3, n: 1}];
const parameterColumns = [number('value', true), number('n')];
const lazyKey = {coalesce: [{literal: 1}, {divide: [{literal: 1}, {literal: 0}]}]};
const lazyRows = [{value: 1, n: 5}];
export const ifnullCoalesceReuseSuccesses = [
  success('group-json-control', JSON.stringify(control('group', key, true)), grouped,
    [number('value'), number('n')], {format: 'json'}),
  success('distinct-json-control', JSON.stringify(control('distinct', key, false)), distinct,
    [number('value')], {format: 'json'}),
  success('parameter-json-control', JSON.stringify(control('parameter', parameterKey, true, params)), parameterRows,
    parameterColumns, {format: 'json', parameters: {p: 2}}),
  success('lazy-json-control', JSON.stringify(control('lazy', lazyKey, true)), lazyRows,
    [number('value'), number('n')], {format: 'json'}),
  success('sql-group', 'SELECT IFNULL(amount, 0) AS value, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY COALESCE(records.amount, 0) ORDER BY value'),
  success('reverse-group', 'SELECT COALESCE(amount, 0) AS value, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY IFNULL(records.amount, 0) ORDER BY value'),
  success('quoted-group', 'SELECT `ifnull`(amount, 0) AS value, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY `CoAlEsCe`((records.amount), 0) ORDER BY value'),
  success('sql-distinct', 'SELECT DISTINCT IFNULL(amount, 0) AS value FROM records WHERE id > 0 ORDER BY COALESCE(records.amount, 0)', distinct, [number('value')]),
  success('reverse-distinct', 'SELECT DISTINCT COALESCE(amount, 0) AS value FROM records WHERE id > 0 ORDER BY IFNULL(records.amount, 0)', distinct, [number('value')]),
  success('pipe-distinct', 'FROM records |> WHERE id > 0 |> SELECT DISTINCT `CoAlEsCe`(amount, 0) AS value |> ORDER BY `IfNuLl`((amount), 0)', distinct,
    [number('value')], {format: 'aql-text'}),
  success('empty', 'SELECT IFNULL(amount, 0) AS value, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY COALESCE(amount, 0) ORDER BY value', [],
    [number('value'), number('n')], {sourceRows: []}),
  success('nullable-value', 'SELECT DISTINCT IFNULL(amount, CAST(NULL AS FLOAT64)) AS value FROM records WHERE id > 0 ORDER BY COALESCE(records.amount, CAST(NULL AS FLOAT64)) NULLS LAST',
    [{value: 1}, {value: 2}, {value: 3}, {value: null}], [number('value', true)]),
  success('parameter-value', 'SELECT IFNULL(amount, @p) AS value, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY COALESCE(amount, @p) ORDER BY value',
    parameterRows, parameterColumns, {parameterDeclarations: params, parameters: {p: 2}}),
  success('parameter-null', 'SELECT COALESCE(amount, @p) AS value, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY IFNULL(amount, @p) ORDER BY value',
    [{value: null, n: 1}, {value: 1, n: 1}, {value: 2, n: 2}, {value: 3, n: 1}],
    parameterColumns, {parameterDeclarations: params, parameters: {p: null}}),
  success('lazy-fallback', 'SELECT IFNULL(1, 1 / 0) AS value, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY COALESCE(1, 1 / 0) ORDER BY value', lazyRows),
];
// Input amount and the output alias -amount deliberately reverse the ordering.
// Matching call names is insufficient: each operand must resolve in its scope.
const aliasRows = [{id: 4, original: 3, amount: -3},
  {id: 2, original: 2, amount: -2}, {id: 3, original: 2, amount: -2},
  {id: 1, original: 1, amount: -1}, {id: 5, original: 0, amount: null}];
const aliasColumns = [number('id'), number('original'), number('amount', true)];
const aliasSelect = 'SELECT DISTINCT id, IFNULL(amount, 0) AS original, -amount AS amount FROM records WHERE id > 0 ORDER BY ';
ifnullCoalesceReuseSuccesses.push(
  success('output-alias', aliasSelect + 'COALESCE(amount, 0), id', aliasRows, aliasColumns),
  success('qualified-input', aliasSelect + 'COALESCE(records.amount, 0), id',
    [aliasRows[4], aliasRows[3], aliasRows[1], aliasRows[2], aliasRows[0]], aliasColumns),
);
export const ifnullCoalesceReuseRefusals = [
  'COALESCE(amount, 1)', 'COALESCE(0, amount)', 'COALESCE(id, 0)',
  'COALESCE(amount)', 'COALESCE(amount, 0, 1)', 'NULLIF(amount, 0)',
  'ACTQL.COALESCE(amount, 0)',
].map((ordered, index) => ({name: 'ifnull-coalesce-reuse-order-refusal-' + index, format: 'sql',
  text: 'SELECT DISTINCT IFNULL(amount, 0) AS value FROM records ORDER BY ' + ordered,
  expectedCode: 'ClientProgramImplementationLimit'})).concat([
  {name: 'ifnull-coalesce-reuse-invalid-types', format: 'sql',
    text: "SELECT IFNULL(amount, 'bad') AS value, COUNT(*) AS n FROM records GROUP BY COALESCE(amount, 'bad')",
    expectedCode: 'ClientProgramInvalidInput'},
  {name: 'ifnull-coalesce-reuse-undeclared-parameter', format: 'sql',
    text: 'SELECT IFNULL(amount, @missing) AS value FROM records'},
]);
export const ifnullCoalesceReuseExecutionFailures = [{
  name: 'ifnull-coalesce-reuse-demanded-fallback', format: 'sql',
  text: 'SELECT DISTINCT IFNULL(CAST(NULL AS FLOAT64), 1 / 0) AS value FROM records WHERE id > 0 ORDER BY COALESCE(CAST(NULL AS FLOAT64), 1 / 0)',
  resultNames: ['main'], sourceRows: rows, sourceReadSessionCount: 1,
}];
