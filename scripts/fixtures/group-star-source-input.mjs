// Independently authored values and schemas. SQL star expands the input
// columns amount,id, not the GROUP BY order id,amount or the new count slot.
const rows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}];
const number = (name, nullable = false) => ({name,
  contract: {type: 'number', nullable}});
const sourceColumns = [number('amount', true), number('id')];
const countedColumns = [...sourceColumns, number('n')];
const expected = [{amount: null, id: 1, n: 1},
  {amount: 20, id: 2, n: 1}, {amount: 30, id: 3, n: 2}];
const program = {version: 'actql/0.1', id: 'fixture.group_star',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', group: {by: ['id', 'amount'],
      aggregates: {n: {fn: 'count'}}}},
    {select: ['amount', 'id', 'n']},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['amount', 'id', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const sql = 'SELECT *, COUNT(*) AS n FROM records GROUP BY id, amount ORDER BY id';
const success = (name, format, text, overrides = {}) => ({
  name: 'group-star-' + name, format, text, sourceRows: rows,
  expected, columns: countedColumns, sourceReadSessionCount: 1, ...overrides,
});
export const groupStarSuccesses = [
  success('json-control', 'json', JSON.stringify(program)),
  success('sql-input-order', 'sql', 'SELECT * FROM records GROUP BY id, amount ORDER BY id', {
    expected: expected.map(({amount, id}) => ({amount, id})), columns: sourceColumns,
  }),
  success('sql-star-count', 'sql', sql),
  success('sql-count-star', 'sql', 'SELECT COUNT(*) AS n, * FROM records GROUP BY id, amount ORDER BY id', {
    columns: [number('n'), ...sourceColumns],
  }),
  success('cte-input-order', 'sql', 'WITH chosen AS (SELECT id, amount FROM records) SELECT *, COUNT(*) AS n FROM chosen GROUP BY amount, id ORDER BY id', {
    columns: [number('id'), number('amount', true), number('n')],
  }),
  success('scoped-join', 'sql', 'WITH a AS (SELECT 1 AS x, 20 AS y), b AS (SELECT 1 AS k), c AS (SELECT 1 AS z) SELECT *, COUNT(*) AS n FROM a JOIN b ON a.x = b.k JOIN c ON b.k = c.z GROUP BY c.z, b.k, a.y, a.x ORDER BY x', {
    expected: [{x: 1, y: 20, k: 1, z: 1, n: 1}],
    columns: ['x', 'y', 'k', 'z', 'n'].map(name => number(name)),
    sourceReadSessionCount: 0,
  }),
  success('pipe-aggregate-scope', 'aql-text', 'FROM records |> AGGREGATE COUNT(*) AS n GROUP BY id, amount |> SELECT * |> ORDER BY id', {
    columns: [number('id'), number('amount', true), number('n')],
  }),
  success('empty', 'sql', sql, {sourceRows: [], expected: []}),
];
export const groupStarRefusals = [
  'SELECT * FROM records GROUP BY id',
  'SELECT *, COUNT(*) AS amount FROM records GROUP BY id',
  'SELECT *, COUNT(*) AS n FROM records',
].map((text, index) => ({name: 'group-star-ungrouped-' + index,
  format: 'sql', text}));
