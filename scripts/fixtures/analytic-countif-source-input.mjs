// Authored from TRUE-only counting in explicit ROWS frames. Expected rows and
// complete contracts are independent of the compiler and execution output.
const number = {type: 'number', nullable: false};
const declarations = {threshold: number};
const sourceRows = [{id: 4, amount: 20}, {id: 1, amount: null},
  {id: 3, amount: 10}, {id: 2, amount: 20}, {id: 5, amount: 0},
  {id: 6, amount: 0}, {id: 0, amount: 999}];
const columns = ['id', 'n'].map(name => ({name, contract: number}));
const expected = [{id: 1, n: 1}, {id: 2, n: 1}, {id: 3, n: 2},
  {id: 4, n: 1}, {id: 5, n: 1}, {id: 6, n: 0}];
export const analyticCountifProgram = {version: 'actql/0.1',
  id: 'fixture.analytic_countif', params: declarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', analytic: {partition_by: [],
      order_by: [{field: 'id', dir: 'asc', nulls: 'first'}],
      functions: {n: {fn: 'count_if', expr: {gt: [{field: 'amount'}, {$param: 'threshold'}]}}},
      frame: {start: {preceding: 1}, end: {following: 1}}}},
    {select: ['id', 'n']},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const call = frame => `COUNTIF(amount > @threshold) OVER (${frame}) AS n`;
const frame = 'ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING';
const sql = `SELECT id, ${call(frame)} FROM records WHERE id > 0 ORDER BY id`;
const success = (name, text, extra = {}) => ({name: 'analytic-countif-' + name,
  format: 'sql', text, sourceRows, expected, columns,
  parameterDeclarations: declarations, parameters: {threshold: 10},
  sourceReadSessionCount: 1, ...extra});
export const analyticCountifSuccesses = [
  success('independent-json', JSON.stringify(analyticCountifProgram),
    {format: 'json', parameterDeclarations: undefined}),
  success('sql-true-only', sql),
  success('sql-limit-offset', sql + ' LIMIT 4 OFFSET 1', {expected: expected.slice(1, 5)}),
  success('pipe-following-empty-frame',
    `FROM records |> WHERE id > 0 |> SELECT id, ${call('ORDER BY id ROWS BETWEEN 1 FOLLOWING AND 2 FOLLOWING')} |> ORDER BY id`,
    {format: 'aql-text', expected: [{id: 1, n: 1}, {id: 2, n: 1}, {id: 3, n: 1},
      {id: 4, n: 0}, {id: 5, n: 0}, {id: 6, n: 0}]}),
  success('partition-duplicates',
    `SELECT id, ${call('PARTITION BY amount ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW')} FROM records WHERE id > 0 ORDER BY id`,
    {expected: [{id: 1, n: 0}, {id: 2, n: 1}, {id: 3, n: 0},
      {id: 4, n: 2}, {id: 5, n: 0}, {id: 6, n: 0}]}),
  success('typed-empty', sql, {sourceRows: [], expected: []}),
];
export const analyticCountifRefusals = [
  'SELECT COUNTIF(id) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS n FROM records',
  'SELECT COUNTIF(amount > 10) OVER (ORDER BY id) AS n FROM records',
  'SELECT COUNTIF(amount > @missing) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS n FROM records',
  'SELECT amount > 10 AS invented, COUNTIF(invented) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS n FROM records',
].map((text, index) => ({name: 'analytic-countif-refuse-' + index, format: 'sql', text}));
export const analyticCountifExecutionFailures = [{
  name: 'analytic-countif-demanded-expression-failure', format: 'sql',
  text: 'SELECT COUNTIF(1 / 0 > 0) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS n FROM records',
  resultNames: ['answer'], sourceReadSessionCount: 1,
}];
