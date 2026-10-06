// Independently authored LEFT commutation and public SQL RIGHT expectations.
const number = {type: 'number', nullable: false};
const nullable = {...number, nullable: true};
const column = (name, contract = number) => ({name, contract});
const rows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}];
const columns = [column('original', nullable), column('preserved'), column('amount', nullable)];
const missing = [{original: null, preserved: 4, amount: null}];
export const rightJoinProgram = {version: 'actql/0.1', id: 'fixture.right_join',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}}, {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{values: {schema: {id: number}, rows: [{id: 4}]}, as: 'preserved'},
      {from: 'preserved', join: {with: 'records', kind: 'left',
        on: [{left: 'id', right: 'id'}], max_output_rows: 10,
        select: {original: 'right.id', preserved: 'left.id', amount: 'right.amount'}}, as: 'joined'},
      {sort: [{field: 'preserved', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['original', 'preserved', 'amount']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const sql = 'SELECT l.id AS original, r.id AS preserved, l.amount FROM records AS l '
  + 'RIGHT OUTER JOIN (SELECT 4 AS id) AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 ORDER BY preserved';
const success = (name, text, extra = {}) => ({name: 'right-join-' + name,
  format: 'sql', text, sourceRows: rows, sourceReadSessionCount: 1,
  expected: missing, columns, ...extra});
const negative = [{id: -3, amount: 30}, {id: -3, amount: 30},
  {id: -3, amount: 30}, {id: -3, amount: 30}, {id: -2, amount: 20}, {id: -1, amount: null}];
export const rightJoinSuccesses = [
  success('independent-json', JSON.stringify(rightJoinProgram), {format: 'json'}),
  success('unmatched-left-null', sql),
  success('duplicate-matches', sql.replace('SELECT 4 AS id', 'SELECT 3 AS id'), {
    expected: [{original: 3, preserved: 3, amount: 30}, {original: 3, preserved: 3, amount: 30}],
  }),
  success('empty-left', sql, {sourceRows: [], expected: missing}),
  success('using-star-order', 'SELECT * FROM records AS l RIGHT JOIN (SELECT 4 AS id) AS r '
    + 'USING (id) MAX_OUTPUT_ROWS 10 ORDER BY id', {
    columns: [column('id'), column('amount', nullable)], expected: [{id: 4, amount: null}],
  }),
  success('using-qualified-sides', 'SELECT id, l.id AS original, r.id AS preserved, l.amount '
    + 'FROM records AS l RIGHT JOIN (SELECT 4 AS id) AS r USING (id) MAX_OUTPUT_ROWS 10 ORDER BY id', {
    columns: [column('id'), ...columns], expected: [{id: 4, ...missing[0]}],
  }),
  success('alias-order-collision', 'SELECT -r.id AS id, l.amount FROM records AS l '
    + 'RIGHT JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 ORDER BY id + 1', {
    columns: [column('id'), column('amount', nullable)], expected: negative,
  }),
  success('qualified-order-control', 'SELECT -r.id AS id, l.amount FROM records AS l '
    + 'RIGHT JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 ORDER BY r.id + 1', {
    columns: [column('id'), column('amount', nullable)],
    expected: [negative[5], negative[4], ...negative.slice(0, 4)],
  }),
  success('where-after-outer-join', sql.replace('ORDER BY preserved', 'WHERE l.id > 0 ORDER BY preserved'), {expected: []}),
  success('cte-current-scope', 'WITH chosen AS (SELECT id, amount FROM records) '
    + 'SELECT l.id AS original, r.id AS preserved, l.amount FROM chosen AS l '
    + 'RIGHT JOIN (SELECT 4 AS id) AS r ON r.id = l.id MAX_OUTPUT_ROWS 10 ORDER BY preserved'),
  success('null-key-does-not-match', sql.replace('SELECT 4 AS id', 'SELECT CAST(NULL AS FLOAT64) AS id'), {
    columns: [column('original', nullable), column('preserved', nullable), column('amount', nullable)],
    expected: [{original: null, preserved: null, amount: null}],
  }),
  success('empty-right', 'SELECT l.id AS original, r.id AS preserved, l.amount FROM records AS l '
    + 'RIGHT JOIN (SELECT id FROM records WHERE FALSE) AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 ORDER BY preserved', {expected: []}),
];
export const rightJoinRefusals = [
  'SELECT id FROM records AS l RIGHT JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 10',
  'SELECT l.id FROM records AS l RIGHT JOIN records AS l ON l.id = l.id MAX_OUTPUT_ROWS 10',
  'SELECT l.id FROM records AS l RIGHT JOIN records AS r ON l.id > r.id MAX_OUTPUT_ROWS 10',
  'SELECT l.id FROM records AS l RIGHT JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 0',
  'SELECT l.id FROM records AS l RIGHT JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS @missing',
].map((text, index) => ({name: 'right-join-refuse-' + index, format: 'sql', text}));
