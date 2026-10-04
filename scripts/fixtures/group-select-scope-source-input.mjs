// Independent expectations from SELECT input scope and aggregate output scope.
// WHERE excludes ID 0. Two ID 3 rows remain two COUNT contributions; amount
// retains its nullable contract. No product lowerer computes these fixtures.
const rows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 0, amount: 99}];
const number = (name, nullable = false) => ({name,
  contract: {type: 'number', nullable}});
const globalRows = [{n: 4, one: 1}];
const globalColumns = [number('n'), number('one')];
const program = {version: 'actql/0.1', id: 'fixture.group_select_scope',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', group: {by: [], aggregates: {n: {fn: 'count'}}}},
      {derive: {one: {literal: 1}}}, {select: ['n', 'one'], as: 'summary'}],
    results: {rows: {from: 'summary', fields: ['n', 'one']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, format, text, overrides = {}) => ({
  name: 'group-select-scope-' + name, format, text, sourceRows: rows,
  expected: globalRows, columns: globalColumns, sourceReadSessionCount: 1,
  ...overrides,
});
const sql = 'SELECT COUNT(*) AS n, 1 AS one FROM records WHERE id > 0';
const nextRows = [{n: 4, next: 5}];
const nextColumns = [number('n'), number('next')];
export const groupSelectScopeSuccesses = [
  success('json-control', 'json', JSON.stringify(program)),
  success('sql-global-constant', 'sql', sql),
  success('sql-grouped-input-expression', 'sql', 'SELECT records.id + 1 AS next, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY id HAVING n > 0 ORDER BY next', {
    expected: [{next: 2, n: 1}, {next: 3, n: 1}, {next: 4, n: 2}],
    columns: [number('next'), number('n')],
  }),
  success('sql-next-pipe-scope', 'sql', 'SELECT COUNT(*) AS n FROM records WHERE id > 0 |> SELECT n, n + 1 AS next |> ORDER BY next', {
    expected: nextRows, columns: nextColumns,
  }),
  success('pipe-next-projection-scope', 'aql-text', 'FROM records |> WHERE id > 0 |> AGGREGATE COUNT(*) AS n |> SELECT n, n + 1 AS next |> ORDER BY next', {
    expected: nextRows, columns: nextColumns,
  }),
  success('scoped-join-grouped-input', 'sql', 'WITH a AS (SELECT 1 AS x UNION ALL SELECT 1 AS x), b AS (SELECT 1 AS k), c AS (SELECT 1 AS z) SELECT a.x AS x, COUNT(*) AS n FROM a JOIN b ON a.x = b.k JOIN c ON b.k = c.z GROUP BY a.x HAVING n > 0 ORDER BY n + x', {
    expected: [{x: 1, n: 2}], columns: [number('x'), number('n')],
    sourceReadSessionCount: 0,
  }),
  success('empty-global-constant', 'sql', sql, {
    sourceRows: [], expected: [{n: 0, one: 1}],
  }),
  success('nullable-grouped-input', 'sql', 'SELECT amount, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY amount HAVING n > 0 ORDER BY amount', {
    expected: [{amount: null, n: 1}, {amount: 20, n: 1}, {amount: 30, n: 2}],
    columns: [number('amount', true), number('n')],
  }),
];
export const groupSelectScopeRefusals = [
  'SELECT COUNT(*) AS n, n + 1 AS next FROM records',
  'SELECT n + 1 AS next, COUNT(*) AS n FROM records',
  'SELECT COUNT(*) AS id, id + 1 AS next FROM records',
  'SELECT COUNT(*) AS n, records.n AS next FROM records',
  'WITH a AS (SELECT 1 AS x), b AS (SELECT 1 AS k), c AS (SELECT 1 AS z) SELECT COUNT(*) AS n, n + 1 AS next FROM a JOIN b ON a.x = b.k JOIN c ON b.k = c.z',
].map((text, index) => ({name: 'group-select-scope-invalid-sibling-' + index,
  format: 'sql', text}));
