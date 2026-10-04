// Independent grouped values and named-column contracts, not lowerer output.
// GROUP 2,1 denotes amount,id in the SELECT list id,amount,n. WHERE excludes
// ID 0; duplicate ID 3 rows must contribute to n=2, and NULL is a real key.
const rows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 0, amount: 99}];
const number = (name, nullable = false) => ({name,
  contract: {type: 'number', nullable}});
const columns = [number('id'), number('amount', true), number('n')];
const expected = [{id: 1, amount: null, n: 1},
  {id: 2, amount: 20, n: 1}, {id: 3, amount: 30, n: 2}];
const program = {version: 'actql/0.1', id: 'fixture.group_ordinal',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', group: {by: ['amount', 'id'],
      aggregates: {n: {fn: 'count'}}}},
    {select: ['id', 'amount', 'n']},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'amount', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const sql = 'SELECT id, amount, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY 2, 1 ORDER BY id';
const success = (name, format, text, overrides = {}) => ({
  name: 'group-ordinal-' + name, format, text, sourceRows: rows,
  expected, columns, sourceReadSessionCount: 1, ...overrides,
});
export const groupOrdinalSuccesses = [
  success('json-control', 'json', JSON.stringify(program)),
  success('sql', 'sql', sql),
  success('selected-expression-alias-collision', 'sql', 'SELECT -id AS id, -id AS copy, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY (+1) ORDER BY id', {
    expected: [{id: -3, copy: -3, n: 2}, {id: -2, copy: -2, n: 1}, {id: -1, copy: -1, n: 1}],
    columns: ['id', 'copy', 'n'].map(name => number(name)),
  }),
  success('expanded-star', 'sql', 'SELECT COUNT(*) AS n, * FROM records WHERE id > 0 GROUP BY 3, 2 ORDER BY id', {
    columns: [number('n'), number('amount', true), number('id')],
  }),
  success('star-and-literal', 'sql', 'SELECT *, 1 AS one FROM records WHERE id > 0 GROUP BY 2, 1 ORDER BY id', {
    expected: [{amount: null, id: 1, one: 1}, {amount: 20, id: 2, one: 1}, {amount: 30, id: 3, one: 1}],
    columns: [number('amount', true), number('id'), number('one')],
  }),
  success('cte', 'sql', 'WITH chosen AS (SELECT amount, id FROM records WHERE id > 0) SELECT id, amount, COUNT(*) AS n FROM chosen GROUP BY (2), 1 ORDER BY id'),
  success('scoped-join', 'sql', 'WITH a AS (SELECT 1 AS x, 20 AS y), b AS (SELECT 1 AS k), c AS (SELECT 1 AS z) SELECT *, COUNT(*) AS n FROM a JOIN b ON a.x = b.k JOIN c ON b.k = c.z GROUP BY 4, 3, 2, 1 ORDER BY x', {
    expected: [{x: 1, y: 20, k: 1, z: 1, n: 1}],
    columns: ['x', 'y', 'k', 'z', 'n'].map(name => number(name)),
    sourceReadSessionCount: 0,
  }),
  success('ordinary-arithmetic-key', 'sql', 'SELECT COUNT(*) AS n FROM records WHERE id > 0 GROUP BY 1 + 0 ORDER BY n', {
    expected: [{n: 4}], columns: [number('n')],
  }),
  success('empty', 'sql', sql, {sourceRows: [], expected: []}),
];
export const groupOrdinalRefusals = [
  'SELECT id, amount FROM records GROUP BY 0',
  'SELECT *, COUNT(*) AS n FROM records GROUP BY 4',
  'SELECT id, COUNT(*) AS n FROM records GROUP BY 2',
  'SELECT id, amount FROM records GROUP BY 1.0',
  'SELECT id, amount FROM records GROUP BY TRUE',
  'FROM records |> AGGREGATE COUNT(*) AS n GROUP BY 1',
].map((text, index) => ({name: 'group-ordinal-invalid-' + index,
  format: 'aql-text', text}));
