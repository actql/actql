// Independent expectations: JOIN duplicates input rows, DISTINCT collapses
// equal selected amounts, and ORDER negates the evaluated alias a second time.
const sourceRows = [{id: 3, amount: 2}, {id: 1, amount: 2},
  {id: 2, amount: 1}, {id: 4, amount: null}, {id: 0, amount: 99}];
const nullableNumber = {type: 'number', nullable: true};
const columns = [{name: 'amount', contract: nullableNumber}];
const expected = [{amount: null}, {amount: -1}, {amount: -2}];
const joined = 'FROM records AS l JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 25';
const sql = 'SELECT DISTINCT -l.amount AS amount ' + joined + ' WHERE l.id > 0 ORDER BY -amount';
const pipe = 'FROM records AS l |> JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 25'
  + ' |> WHERE l.id > 0 |> SELECT DISTINCT -l.amount AS amount |> ORDER BY -amount';
const cte = 'WITH chosen AS (SELECT id, amount FROM records WHERE id > 0) '
  + 'SELECT DISTINCT -l.amount AS amount FROM chosen AS l JOIN chosen AS r '
  + 'ON l.id = r.id MAX_OUTPUT_ROWS 25 ORDER BY -amount';
// Both consumers use the one retained capture. No frontend Program is edited
// by the acceptance harness; this JSON is authored from ordinary contracts.
const program = {version: 'actql/0.1', id: 'fixture.distinct_join_order',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {
    l: {result: {stage: 'capture', result: 'source'}},
    r: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'l', join: {with: 'r', kind: 'inner',
      on: [{left: 'id', right: 'id'}], max_output_rows: 25,
      select: {input_amount: 'left.amount'}}, as: 'matched'},
    {from: 'matched', derive: {amount: {negate: {field: 'input_amount'}}}},
    {select: ['amount']}, {distinct: ['amount']},
    {derive: {sort_only: {negate: {field: 'amount'}}}},
    {sort: [{field: 'sort_only', dir: 'asc', nulls: 'first'}]},
    {select: ['amount'], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['amount']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, extra = {}) => ({
  name: 'distinct-join-order-' + name, format: 'aql-text', text,
  sourceRows, expected, columns, sourceReadSessionCount: 1, ...extra,
});
export const distinctJoinOrderSuccesses = [
  success('independent-json', JSON.stringify(program), {format: 'json'}),
  success('sql-alias-collision', sql, {format: 'sql'}),
  success('pipe-limit-offset', pipe + ' |> LIMIT 2 OFFSET 1',
    {expected: [{amount: -1}, {amount: -2}]}),
  success('cte-shared-producer', cte),
  success('selected-qualified-input',
    'SELECT DISTINCT l.amount AS score ' + joined + ' WHERE l.id > 0 ORDER BY l.amount + 1 NULLS LAST',
    {expected: [{score: 1}, {score: 2}, {score: null}],
      columns: [{name: 'score', contract: nullableNumber}]}),
  success('selected-expression-reuse',
    'SELECT DISTINCT -l.amount AS a, -l.amount AS b ' + joined + ' WHERE l.id > 0 ORDER BY -l.amount',
    {expected: [{a: null, b: null}, {a: -2, b: -2}, {a: -1, b: -1}],
      columns: [{name: 'a', contract: nullableNumber}, {name: 'b', contract: nullableNumber}]}),
  success('typed-empty', sql, {sourceRows: [], expected: []}),
];
export const distinctJoinOrderRefusals = [
  'SELECT DISTINCT -l.amount AS amount ' + joined + ' ORDER BY l.id + 1',
  'SELECT DISTINCT -l.amount AS amount ' + joined + ' ORDER BY l.amount + 1',
  'WITH chosen AS (SELECT id, amount FROM records) SELECT DISTINCT -l.amount AS amount '
    + 'FROM chosen AS l JOIN chosen AS r ON l.id = r.id MAX_OUTPUT_ROWS 25 ORDER BY r.amount',
].map((text, index) => ({name: 'distinct-join-order-dropped-input-' + index,
  format: 'aql-text', text}));
export const distinctJoinOrderExecutionFailures = [{
  name: 'distinct-join-order-demanded-sort-failure', format: 'sql',
  text: 'SELECT DISTINCT -l.amount AS amount ' + joined
    + ' WHERE l.id > 0 ORDER BY 1 / (amount + 2)',
  sourceRows, sourceReadSessionCount: 1, resultNames: ['answer'],
}];
