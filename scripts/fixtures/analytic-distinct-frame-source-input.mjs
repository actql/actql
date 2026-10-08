// Independent SQL analytic restrictions and cumulative COUNT/SUM/AVG.
// Repeated observations distinguish grouped DISTINCT from ordinary ROWS.
const number = {type: 'number', nullable: false};
const nullable = {...number, nullable: true};
const columns = [{name: 'id', contract: number}, {name: 'n', contract: number},
  {name: 'total', contract: nullable}, {name: 'average', contract: nullable}];
const sourceRows = [{id: 4, amount: 8}, {id: 2, amount: 2},
  {id: 0, amount: 999}, {id: 1, amount: null}, {id: 3, amount: 2}];
const expected = [{id: 1, n: 0, total: null, average: null},
  {id: 2, n: 1, total: 2, average: 2}, {id: 3, n: 2, total: 4, average: 2},
  {id: 4, n: 3, total: 12, average: 4}];
export const analyticDistinctFrameProgram = {version: 'actql/0.1', id: 'fixture.analytic_distinct_frame',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', analytic: {partition_by: [],
      order_by: [{field: 'id', dir: 'asc', nulls: 'first'}],
      functions: {n: {fn: 'count', field: 'amount'},
        total: {fn: 'sum', field: 'amount'}, average: {fn: 'avg', field: 'amount'}},
      frame: {start: 'unbounded_preceding', end: 'current_row'}}},
      {select: ['id', 'n', 'total', 'average']},
      {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'n', 'total', 'average']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const frame = 'ORDER BY id ROWS UNBOUNDED PRECEDING';
const list = over => `id, COUNT(amount) OVER ${over} AS n, SUM(amount) OVER ${over} AS total, AVG(amount) OVER ${over} AS average`;
const sql = `SELECT ${list(`(${frame})`)} FROM records WHERE id > 0 ORDER BY id`;
const success = (name, text, extra = {}) => ({name: 'analytic-distinct-frame-' + name,
  format: 'sql', text, sourceRows, expected, columns, sourceReadSessionCount: 1, ...extra});
export const analyticDistinctFrameSuccesses = [
  success('independent-json', JSON.stringify(analyticDistinctFrameProgram), {format: 'json'}),
  success('ordinary-sql', sql),
  success('ordinary-pipe', `FROM records |> WHERE id > 0 |> SELECT ${list(`(${frame})`)} |> ORDER BY id`, {format: 'aql-text'}),
  success('ordinary-named-window', `SELECT ${list('w')} FROM records WHERE id > 0 WINDOW w AS (${frame}) ORDER BY id`),
  success('ordinary-empty', sql, {sourceRows: [], expected: []}),
  success('grouped-distinct', 'SELECT COUNT(DISTINCT amount) AS n, SUM(DISTINCT amount) AS total, '
    + 'AVG(DISTINCT amount) AS average FROM records WHERE id > 0',
    {columns: columns.slice(1), expected: [{n: 2, total: 10, average: 5}]}),
];
const invalid = [
  ...['COUNT', 'SUM', 'AVG'].map(name => ({name: name.toLowerCase() + '-ordered-frame',
    text: `SELECT ${name}(DISTINCT amount) OVER (${frame}) AS n FROM records`})),
  {name: 'named-order-frame', text: `SELECT COUNT(DISTINCT amount) OVER w AS n FROM records WINDOW w AS (${frame})`},
  {name: 'inherited-order-frame', text: 'SELECT COUNT(DISTINCT amount) OVER (w ROWS CURRENT ROW) AS n FROM records WINDOW w AS (ORDER BY id)'},
  {name: 'qualify', text: `SELECT id FROM records QUALIFY SUM(DISTINCT amount) OVER (${frame}) > 0`},
  {name: 'query-order', text: `SELECT id FROM records ORDER BY AVG(DISTINCT amount) OVER (${frame})`},
  {name: 'pipe-select', format: 'aql-text', text: `FROM records |> SELECT AVG(DISTINCT amount) OVER (${frame}) AS n`},
  {name: 'frame-without-order', text: 'SELECT COUNT(DISTINCT amount) OVER (ROWS CURRENT ROW) AS n FROM records'},
  // Valid GoogleSQL; the default/unordered DISTINCT profile is unconnected.
  // This is a coverage gap, separate from the forbidden clauses above.
  {name: 'default-profile-gap', text: 'SELECT COUNT(DISTINCT amount) OVER () AS n FROM records'},
];
export const analyticDistinctFrameRefusals = invalid.map(item => ({format: 'sql', ...item,
  name: 'analytic-distinct-frame-refuse-' + item.name,
  expectedCode: 'ClientProgramImplementationLimit'}));
