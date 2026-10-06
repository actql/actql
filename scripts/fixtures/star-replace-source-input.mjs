// Expected rows/contracts and the ordinary Program are authored independently
// from the replacement snapshot rule. No compiler output generates the oracle.
const number = {type: 'number', nullable: false};
const nullable = {...number, nullable: true};
const column = (name, contract = number) => ({name, contract});
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 0, amount: 99}];
const swapped = [{amount: 2, id: 20}, {amount: 3, id: 30},
  {amount: 3, id: 30}, {amount: 1, id: null}];
const swapColumns = [column('amount'), column('id', nullable)];
export const starReplaceProgram = {version: 'actql/0.1', id: 'fixture.star_replace',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', select: [{amount: 'id'}, {id: 'amount'}]},
      {sort: [{field: 'id', dir: 'asc', nulls: 'last'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['amount', 'id']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const sql = 'SELECT * REPLACE (id AS amount, amount AS id) FROM records WHERE id > 0 ORDER BY id NULLS LAST';
const success = (name, text, extra = {}) => ({name: 'star-replace-' + name,
  format: 'aql-text', text, sourceRows, sourceReadSessionCount: 1,
  expected: swapped, columns: swapColumns, ...extra});
const originalColumns = [column('amount', nullable), column('id')];
const negative = [{amount: null, id: -1}, {amount: 20, id: -2},
  {amount: 30, id: -3}, {amount: 30, id: -3}];
export const starReplaceSuccesses = [
  success('independent-json', JSON.stringify(starReplaceProgram), {format: 'json'}),
  success('sql-swap-and-null', sql, {format: 'sql'}),
  success('pipe-simultaneous-expression', 'FROM records |> WHERE id > 0 '
    + '|> SELECT * REPLACE (amount + id AS amount, -amount AS id) |> ORDER BY id NULLS LAST', {
    columns: [column('amount', nullable), column('id', nullable)],
    expected: [{amount: 33, id: -30}, {amount: 33, id: -30}, {amount: 22, id: -20}, {amount: null, id: null}],
  }),
  success('order-alias-collision', 'SELECT * REPLACE (-id AS id) FROM records WHERE id > 0 ORDER BY -id',
    {columns: originalColumns, expected: negative}),
  success('order-qualified-control', 'SELECT r.* REPLACE (-r.id AS id) FROM records AS r '
    + 'WHERE r.id > 0 ORDER BY -r.id', {columns: originalColumns,
    expected: [negative[2], negative[3], negative[1], negative[0]]}),
  success('except-and-nullability', 'SELECT * EXCEPT (id) REPLACE (IFNULL(amount, 0) AS amount), '
    + 'id AS original FROM records WHERE id > 0 ORDER BY original', {
    columns: [column('amount'), column('original')],
    expected: [{amount: 0, original: 1}, {amount: 20, original: 2},
      {amount: 30, original: 3}, {amount: 30, original: 3}],
  }),
  success('group-ordinal-having-alias', 'SELECT * REPLACE (id + 1 AS id) FROM records '
    + 'WHERE id > 0 GROUP BY 1, 2 HAVING id > 1 ORDER BY id', {
    columns: originalColumns,
    expected: [{amount: null, id: 2}, {amount: 20, id: 3}, {amount: 30, id: 4}],
  }),
  success('group-aggregate', 'SELECT * REPLACE (COUNT(*) AS id) FROM records '
    + 'WHERE id > 0 GROUP BY amount ORDER BY amount NULLS LAST', {
    columns: originalColumns,
    expected: [{amount: 20, id: 1}, {amount: 30, id: 2}, {amount: null, id: 1}],
  }),
  success('analytic-output', 'SELECT * REPLACE (ROW_NUMBER() OVER (ORDER BY id) AS id) '
    + 'FROM records WHERE id > 0 ORDER BY id', {
    columns: originalColumns,
    expected: [{amount: null, id: 1}, {amount: 20, id: 2}, {amount: 30, id: 3}, {amount: 30, id: 4}],
  }),
  success('range-snapshot', 'FROM records AS before |> WHERE id > 0 |> SET amount = -amount '
    + '|> SELECT before.* REPLACE (id AS id) |> ORDER BY id', {
    columns: originalColumns,
    expected: [{amount: null, id: 1}, {amount: 20, id: 2}, {amount: 30, id: 3}, {amount: 30, id: 3}],
  }),
  success('cte-range', 'WITH chosen AS (SELECT amount, id FROM records WHERE id > 0) '
    + 'SELECT c.* REPLACE (-c.id AS id) FROM chosen AS c ORDER BY -id', {
    columns: originalColumns, expected: negative,
  }),
  success('left-join-nullability', 'SELECT r.* REPLACE (IFNULL(r.k, 0) AS k), l.id AS original '
    + 'FROM records AS l LEFT JOIN (SELECT 1 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 10 '
    + 'WHERE l.id > 0 ORDER BY original', {
    columns: [column('k'), column('original')],
    expected: [{k: 1, original: 1}, {k: 0, original: 2}, {k: 0, original: 3}, {k: 0, original: 3}],
  }),
  success('typed-empty', sql, {sourceRows: [], expected: []}),
];
export const starReplaceRefusals = [
  'SELECT * REPLACE (1 AS absent) FROM records',
  'SELECT * EXCEPT (id) REPLACE (1 AS id) FROM records',
  'SELECT * REPLACE (1 AS id, 2 AS `ID`) FROM records',
  'FROM records |> DROP id |> SELECT * REPLACE (1 AS id)',
  'FROM records |> RENAME id AS original |> SELECT * REPLACE (1 AS id)',
  'FROM records AS old |> AS current |> SELECT * REPLACE (old.id AS id)',
  'SELECT * REPLACE (@missing AS id) FROM records',
  'SELECT * REPLACE () FROM records',
].map((text, index) => ({name: 'star-replace-refuse-' + index, format: 'aql-text', text}));
