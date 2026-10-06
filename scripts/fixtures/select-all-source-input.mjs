// Authored from duplicate-preserving projection, not compiler output.
// Excluding id=0 and then taking offset 1 must retain both copies of 1.
const rows = [{id: 3, amount: 2}, {id: 1, amount: 1},
  {id: 2, amount: 1}, {id: 4, amount: null}, {id: 0, amount: -100}];
const columns = [{name: 'amount', contract: {type: 'number', nullable: true}}];
const limited = [{amount: 1}, {amount: 1}, {amount: 2}];
const full = [{amount: null}, {amount: 1}, {amount: 1}, {amount: 2}];
const sql = 'SELECT ALL amount FROM records WHERE id > 0 ORDER BY amount NULLS FIRST';
const pipe = 'FROM records |> WHERE id > 0 |> SELECT ALL amount |> ORDER BY amount NULLS FIRST';
const program = {version: 'actql/0.1', id: 'fixture.select_all',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount']}, {sort: [{field: 'amount', dir: 'asc', nulls: 'first'}]},
      {take: {count: 3, offset: 1}, as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['amount']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, format, text, expected, sourceRows = rows) => ({
  name: 'select-all-' + name, format, text, expected, columns, sourceRows,
  sourceReadSessionCount: 1,
});
export const selectAllSuccesses = [
  success('json-control', 'json', JSON.stringify(program), limited),
  success('sql-limited', 'sql', sql + ' LIMIT 3 OFFSET 1', limited),
  success('pipe-limited', 'aql-text', pipe + ' |> LIMIT 3 OFFSET 1', limited),
  success('sql-full', 'sql', sql, full),
  success('sql-default-control', 'sql', sql.replace('SELECT ALL', 'SELECT'), full),
  success('sql-distinct-control', 'sql', sql.replace('SELECT ALL', 'SELECT DISTINCT'),
    [{amount: null}, {amount: 1}, {amount: 2}]),
  success('sql-empty', 'sql', sql, [], []),
  {...success('sql-alias-column-order', 'sql',
    'SELECT ALL amount AS id, id AS original_id FROM records WHERE id > 0 ORDER BY id, original_id',
    [{id: null, original_id: 4}, {id: 1, original_id: 1},
      {id: 1, original_id: 2}, {id: 2, original_id: 3}]),
    columns: [{name: 'id', contract: {type: 'number', nullable: true}},
      {name: 'original_id', contract: {type: 'number', nullable: false}}]},
  {...success('source-free-star-tail', 'aql-text',
    'SELECT ALL 2 AS id |> SELECT ALL * |> ORDER BY id', [{id: 2}]),
    sourceReadCount: 0, sourceReadSessionCount: 0,
    columns: [{name: 'id', contract: {type: 'number', nullable: false}}]},
];
export const selectAllRefusals = [
  ['sql', 'SELECT ALL DISTINCT amount FROM records'],
  ['sql', 'SELECT DISTINCT ALL amount FROM records'],
  ['sql', 'SELECT ALL ALL amount FROM records'],
  ['aql-text', 'FROM records |> SELECT ALL DISTINCT amount'],
  ['aql-text', 'FROM records |> SELECT ALL amount |> WHERE id > 0'],
].map(([format, text], index) => ({name: 'select-all-invalid-' + index, format, text}));
