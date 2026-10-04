// Independently authored output positions and rows. Sorting a numeric constant
// instead of score puts the NULL row last; sorting the input amount reverses
// the non-NULL score groups. The second ordinal reverses the duplicate group.
const rows = [{id: 3, amount: 2}, {id: 1, amount: 2},
  {id: 2, amount: 1}, {id: 4, amount: null}, {id: 0, amount: 99}];
const columns = [{name: 'score', contract: {type: 'number', nullable: true}},
  {name: 'id', contract: {type: 'number', nullable: false}}];
const expected = [{score: null, id: 4}, {score: -2, id: 3}, {score: -2, id: 1}];
const program = {version: 'actql/0.1', id: 'fixture.order_ordinal',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {selected_value: {negate: {field: 'amount'}}}},
      {select: [{score: 'selected_value'}, 'id']},
      {sort: [{field: 'score', dir: 'asc', nulls: 'first'},
        {field: 'id', dir: 'desc', nulls: 'last'}]},
      {take: {count: 3, offset: 0}, as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['score', 'id']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const sql = 'SELECT -amount AS score, id FROM records WHERE id > 0 ORDER BY 1 ASC NULLS FIRST, 2 DESC LIMIT 3';
const pipe = 'FROM records |> WHERE id > 0 |> SELECT -amount AS score, id |> ORDER BY 1 ASC NULLS FIRST, 2 DESC |> LIMIT 3';
const success = (name, format, text, overrides = {}) => ({
  name: 'order-ordinal-' + name, format, text, sourceRows: rows,
  expected, columns, sourceReadSessionCount: 1, ...overrides,
});
export const orderOrdinalSuccesses = [
  success('json-control', 'json', JSON.stringify(program)),
  success('sql', 'sql', sql),
  success('pipe', 'aql-text', pipe),
  success('cte-join', 'sql', 'WITH chosen AS (SELECT id, amount FROM records WHERE id > 0) SELECT -l.amount AS score, r.id AS id FROM chosen AS l JOIN chosen AS r ON l.id = r.id ORDER BY 1 ASC NULLS FIRST, 2 DESC LIMIT 3'),
  success('set-duplicates', 'sql', 'SELECT 1 AS y, 20 AS x UNION ALL SELECT 2 AS y, 10 AS x UNION ALL SELECT 2 AS y, 10 AS x ORDER BY 2, 1 DESC', {
    expected: [{y: 2, x: 10}, {y: 2, x: 10}, {y: 1, x: 20}],
    columns: ['y', 'x'].map(name => ({name, contract: {type: 'number', nullable: false}})),
    sourceReadSessionCount: 0,
  }),
  success('distinct', 'sql', 'SELECT DISTINCT amount FROM records WHERE id > 0 ORDER BY (1)', {
    expected: [{amount: null}, {amount: 1}, {amount: 2}],
    columns: [{name: 'amount', contract: {type: 'number', nullable: true}}],
  }),
  success('empty', 'sql', sql, {sourceRows: [], expected: []}),
  success('current-pipe-scope', 'aql-text', 'FROM records AS original |> SET id = -id |> DROP amount |> ORDER BY 1', {
    expected: [{id: -4}, {id: -3}, {id: -2}, {id: -1}, {id: 0}],
    columns: [{name: 'id', contract: {type: 'number', nullable: false}}],
  }),
];
export const orderOrdinalRefusals = [
  'SELECT amount, id FROM records ORDER BY 0',
  'SELECT amount, id FROM records ORDER BY -1',
  'SELECT amount, id FROM records ORDER BY 3',
  'SELECT amount, id FROM records ORDER BY 1.0',
  'FROM records AS original |> DROP amount |> ORDER BY 2',
].map((text, index) => ({name: 'order-ordinal-invalid-' + index,
  format: 'aql-text', text}));
