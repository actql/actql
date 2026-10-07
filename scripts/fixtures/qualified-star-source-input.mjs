// Independent rows, contracts and machine control: a range binds its original
// physical values; star expansion keeps that range's column order.
const number = {type: 'number', nullable: false};
const amount = {type: 'number', nullable: true};
const column = (name, contract = number) => ({name, contract});
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 0, amount: 99}];
const expected = [{amount: null}, {amount: 20}, {amount: 30}, {amount: 30}];
const columns = [column('amount', amount)];
export const qualifiedStarProgram = {version: 'actql/0.1', id: 'fixture.qualified_star',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', sort: [{field: 'id', dir: 'asc', nulls: 'first'}]},
      {select: ['amount'], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['amount']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const sql = 'SELECT r.* EXCEPT (id) FROM records AS r WHERE r.id > 0 ORDER BY r.id';
const success = (name, text, extra = {}) => ({name: 'qualified-star-' + name,
  format: 'aql-text', text, sourceRows, expected, columns,
  sourceReadSessionCount: 1, ...extra});
export const qualifiedStarSuccesses = [
  success('independent-json', JSON.stringify(qualifiedStarProgram), {format: 'json'}),
  success('complete-range', 'SELECT r.* FROM records AS r WHERE id > 0 ORDER BY id', {
    columns: [...columns, column('id')],
    expected: [{amount: null, id: 1}, {amount: 20, id: 2},
      {amount: 30, id: 3}, {amount: 30, id: 3}],
  }),
  success('sql-hidden-order', sql, {format: 'sql'}),
  success('quoted-range', 'SELECT `A.B`.* EXCEPT (id) FROM records AS `a.b` WHERE id > 0 ORDER BY id'),
  success('pipe-original-values', 'FROM records AS before |> WHERE id > 0 '
    + '|> SET amount = -amount |> SELECT before.* EXCEPT (id) |> ORDER BY amount'),
  success('pipe-replaced-alias', 'FROM records AS before |> WHERE id > 0 '
    + '|> AS current |> SELECT current.* EXCEPT (id) |> ORDER BY amount'),
  success('left-join-nullability', 'SELECT seed.*, r.id AS id FROM records AS r '
    + 'LEFT JOIN (SELECT 1 AS k) AS seed ON r.id = seed.k MAX_OUTPUT_ROWS 10 '
    + 'WHERE r.id > 0 ORDER BY r.id', {
    columns: [column('k', amount), column('id')],
    expected: [{k: 1, id: 1}, {k: null, id: 2}, {k: null, id: 3}, {k: null, id: 3}],
  }),
  success('grouped-ordinal', 'SELECT r.* EXCEPT (id), COUNT(*) AS n FROM records AS r '
    + 'WHERE r.id > 0 GROUP BY 1 ORDER BY amount NULLS LAST', {
    columns: [...columns, column('n')],
    expected: [{amount: 20, n: 1}, {amount: 30, n: 2}, {amount: null, n: 1}],
  }),
  success('cte-scope', 'WITH chosen AS (SELECT id, amount AS price FROM records WHERE id > 0) '
    + 'SELECT c.* EXCEPT (id) FROM chosen AS c ORDER BY price NULLS LAST', {
    columns: [column('price', amount)],
    expected: [{price: 20}, {price: 30}, {price: 30}, {price: null}],
  }),
  success('typed-empty', sql, {sourceRows: [], expected: []}),
];
export const qualifiedStarRefusals = [
  'SELECT q.* FROM records AS q JOIN (SELECT 1 AS k) AS q ON id = k MAX_OUTPUT_ROWS 10',
  'SELECT missing.* FROM records',
  'SELECT records.* FROM records AS r',
  'FROM records AS old |> AS current |> SELECT old.*',
  'FROM records AS old |> SELECT amount |> SELECT old.*',
  'SELECT r.* FROM records AS r GROUP BY id',
  'SELECT r.* EXCEPT (missing) FROM records AS r',
  'SELECT r.payload.* FROM records AS r',
].map((text, index) => ({name: 'qualified-star-refuse-' + index, format: 'aql-text', text}));
