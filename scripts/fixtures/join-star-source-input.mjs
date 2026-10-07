// Public rows/schema/order and JSON control are authored from JOIN semantics.
const number = {type: 'number', nullable: false};
const nullable = {...number, nullable: true};
const column = (name, contract = number) => ({name, contract});
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}];
const sourceColumns = [column('amount', nullable), column('id')];
export const joinStarProgram = {version: 'actql/0.1', id: 'fixture.join_star',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}}, {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{values: {schema: {k: number}, rows: [{k: 2}]}, as: 'keys'},
      {from: 'records', join: {with: 'keys', kind: 'inner',
        on: [{left: 'id', right: 'k'}], max_output_rows: 10,
        select: {amount: 'left.amount', id: 'left.id', k: 'right.k'}}, as: 'joined'},
      {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['amount', 'id', 'k']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const sql = 'SELECT * FROM records AS l JOIN (SELECT 2 AS k) AS r '
  + 'ON l.id = r.k MAX_OUTPUT_ROWS 10 ORDER BY id';
const success = (name, text, extra = {}) => ({name: 'join-star-' + name,
  format: 'sql', text, sourceRows, sourceReadSessionCount: 1,
  columns: [...sourceColumns, column('k')], expected: [{amount: 20, id: 2, k: 2}], ...extra});
const usingColumns = [column('id'), column('amount', nullable)];
const preserved = [{id: 1, amount: null}, {id: 2, amount: 20},
  {id: 3, amount: 30}, {id: 3, amount: 30}];
export const joinStarSuccesses = [
  success('independent-json', JSON.stringify(joinStarProgram), {format: 'json'}),
  success('on-unique-columns', sql),
  success('left-on-nullability', 'SELECT * FROM records AS l LEFT JOIN (SELECT 3 AS k) AS r '
    + 'ON l.id = r.k MAX_OUTPUT_ROWS 10 ORDER BY id', {
    columns: [...sourceColumns, column('k', nullable)],
    expected: [{amount: null, id: 1, k: null}, {amount: 20, id: 2, k: null},
      {amount: 30, id: 3, k: 3}, {amount: 30, id: 3, k: 3}],
  }),
  success('inner-using-key-first', 'SELECT * FROM records AS l JOIN (SELECT 2 AS id) AS r '
    + 'USING (id) MAX_OUTPUT_ROWS 10 ORDER BY id', {columns: usingColumns, expected: [{id: 2, amount: 20}]}),
  success('left-using-key-first', 'SELECT * FROM records AS l LEFT JOIN (SELECT 2 AS id) AS r '
    + 'USING (id) MAX_OUTPUT_ROWS 10 ORDER BY id', {columns: usingColumns, expected: preserved}),
  success('using-qualified-null-control', 'SELECT *, l.id AS original, r.id AS joined '
    + 'FROM records AS l LEFT JOIN (SELECT 2 AS id) AS r USING (id) MAX_OUTPUT_ROWS 10 ORDER BY id', {
    columns: [...usingColumns, column('original'), column('joined', nullable)],
    expected: preserved.map(row => ({...row, original: row.id, joined: row.id === 2 ? 2 : null})),
  }),
  success('declared-using-order', 'SELECT * FROM records AS l JOIN records AS r '
    + 'USING (id, amount) MAX_OUTPUT_ROWS 10 ORDER BY id', {
    columns: usingColumns, expected: [{id: 2, amount: 20},
      {id: 3, amount: 30}, {id: 3, amount: 30}, {id: 3, amount: 30}, {id: 3, amount: 30}],
  }),
  success('except-preserves-input-order', 'SELECT * EXCEPT (k) FROM records AS l JOIN (SELECT 2 AS k) AS r '
    + 'ON l.id = r.k MAX_OUTPUT_ROWS 10 ORDER BY id', {columns: sourceColumns, expected: [{amount: 20, id: 2}]}),
  success('cte-using-current-row', 'WITH chosen AS (SELECT amount, id FROM records) '
    + 'SELECT * FROM chosen AS l LEFT JOIN (SELECT 2 AS id) AS r USING (id) MAX_OUTPUT_ROWS 10 ORDER BY id', {
    columns: usingColumns, expected: preserved,
  }),
  success('empty-typed-result', sql, {sourceRows: [], expected: []}),
];
export const joinStarRefusals = [
  'SELECT * FROM records AS l JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 10',
  'SELECT * FROM records AS l JOIN records AS r USING (id, `ID`) MAX_OUTPUT_ROWS 10',
  'SELECT * FROM records AS l JOIN (SELECT 2 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 0',
  'SELECT * EXCEPT (missing) FROM records AS l JOIN (SELECT 2 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 10',
].map((text, index) => ({name: 'join-star-refuse-' + index, format: 'sql', text}));
