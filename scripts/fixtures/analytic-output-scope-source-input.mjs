// Authored input/rank expectations: descending amount with id as a tie key
// ranks ids 3,4,1,2, while ascending input amount orders ids 1,3,4,2.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const column = (name, contract = number) => ({name, contract});
const sourceRows = [{id: 3, amount: 20}, {id: 1, amount: 10},
  {id: 2, amount: null}, {id: 4, amount: 20}, {id: 0, amount: 99}];
const rank = 'ROW_NUMBER() OVER (ORDER BY amount DESC NULLS LAST, id)';
const expected = [{id: 3, amount: 1, original: 20}, {id: 4, amount: 2, original: 20},
  {id: 1, amount: 3, original: 10}, {id: 2, amount: 4, original: null}];
const columns = [column('id'), column('amount'), column('original', nullableNumber)];
export const analyticOutputScopeProgram = {version: 'actql/0.1', id: 'fixture.analytic-output-scope',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', analytic: {partition_by: [], order_by: [
      {field: 'amount', dir: 'desc', nulls: 'last'}, {field: 'id', dir: 'asc', nulls: 'first'}],
      functions: {rank: {fn: 'row_number'}}}},
      {select: ['id', {amount: 'rank'}, {original: 'amount'}]},
      {sort: [{field: 'amount', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'amount', 'original']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, rows = expected, fields = columns, extra = {}) => ({
  name: 'analytic-output-scope-' + name, hostProfile: 'analytic-order', format: 'sql',
  text, expected: rows, columns: fields, sourceRows, sourceReadSessionCount: 1, ...extra,
});
export const analyticOutputScopeSuccesses = [
  success('json-control', JSON.stringify(analyticOutputScopeProgram), expected, columns, {format: 'json'}),
  success('sql-collision', `SELECT id, ${rank} AS amount, amount AS original FROM records WHERE id > 0 ORDER BY amount`),
  success('sql-qualified-input', `SELECT id, ${rank} AS amount, amount AS original FROM records WHERE id > 0 ORDER BY records.amount NULLS LAST, id`,
    [expected[2], expected[0], expected[1], expected[3]]),
  success('pipe-current-input', `FROM records |> WHERE id > 0 |> AS original_source |> SELECT id, ${rank} AS amount, original_source.amount AS original |> ORDER BY amount + 1`,
    expected, columns, {format: 'aql-text'}),
  success('star', `SELECT *, ${rank} AS pos FROM records WHERE id > 0 ORDER BY id`,
    [{amount: 10, id: 1, pos: 3}, {amount: null, id: 2, pos: 4}, {amount: 20, id: 3, pos: 1}, {amount: 20, id: 4, pos: 2}],
    [column('amount', nullableNumber), column('id'), column('pos')]),
  success('later-select', `FROM records |> WHERE id > 0 |> SELECT ${rank} AS amount |> SELECT amount AS rank_value |> ORDER BY rank_value`,
    [{rank_value: 1}, {rank_value: 2}, {rank_value: 3}, {rank_value: 4}], [column('rank_value')], {format: 'aql-text'}),
  success('empty', `SELECT ${rank} AS amount FROM records WHERE FALSE ORDER BY amount`, [], [column('amount')]),
];
export const analyticOutputScopeRefusals = [
  {name: 'analytic-output-scope-refusal-sibling', format: 'sql', hostProfile: 'analytic-order',
    text: `SELECT ${rank} AS pos, pos + 1 AS later FROM records`},
  {name: 'analytic-output-scope-refusal-qualified-alias', format: 'sql', hostProfile: 'analytic-order',
    text: `SELECT ${rank} AS pos FROM records ORDER BY records.pos`},
  {name: 'analytic-output-scope-refusal-duplicate', format: 'sql', hostProfile: 'analytic-order',
    text: `SELECT ${rank} AS amount, RANK() OVER (ORDER BY id) AS amount FROM records`},
];
