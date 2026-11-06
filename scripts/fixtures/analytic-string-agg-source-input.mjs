// Explicit ROWS frames, non-NULL concatenation and occurrence multiplicity.
// Programs, values and complete contracts are authored independently.
const number = {type: 'number', nullable: false};
const string = {type: 'string', nullable: true};
const columns = [{name: 'id', contract: number}, {name: 'names', contract: string}];
const sourceRows = [{id: 4, amount: 20}, {id: 1, amount: null},
  {id: 3, amount: 10}, {id: 2, amount: 20}, {id: 5, amount: null},
  {id: 0, amount: 999}];
const expected = [{id: 1, names: null}, {id: 2, names: 'b'},
  {id: 3, names: 'b|a'}, {id: 4, names: 'b|a|b'}, {id: 5, names: 'b|a|b'}];
const argument = {case: {when: [
  {when: {eq: [{field: 'amount'}, {literal: 20}]}, then: {literal: 'b'}},
  {when: {eq: [{field: 'amount'}, {literal: 10}]}, then: {literal: 'a'}},
], else: {literal: null}}};
export const analyticStringAggProgram = {version: 'actql/0.1',
  id: 'fixture.analytic_string_agg', stages: [
    {id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
        {select: ['amount', 'id'], as: 'captured'}],
      results: {source: {from: 'captured', fields: ['amount', 'id']}}},
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', analytic: {partition_by: [],
        order_by: [{field: 'id', dir: 'asc', nulls: 'first'}],
        functions: {names: {fn: 'string_agg', expr: argument, max_bytes: 65536, delimiter: '|'}},
        frame: {start: 'unbounded_preceding', end: 'current_row'}}},
      {select: ['id', 'names']},
      {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
      results: {rows: {from: 'ordered', fields: ['id', 'names']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const expression = prefix => `CASE WHEN ${prefix}amount = 20 THEN 'b' WHEN ${prefix}amount = 10 THEN 'a' ELSE NULL END`;
const frame = 'ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW';
const call = (options = {}) => `${options.function ?? 'STRING_AGG'}(${expression(options.prefix ?? '')}${options.delimiter ?? ", '|'"}) OVER (${options.frame ?? frame}) AS names`;
const sql = `SELECT id, ${call()} FROM records WHERE id > 0 ORDER BY id`;
const success = (name, text, extra = {}) => ({name: 'analytic-string-agg-' + name,
  format: 'sql', text, sourceRows, expected, columns, sourceReadSessionCount: 1, ...extra});
export const analyticStringAggSuccesses = [
  success('independent-json', JSON.stringify(analyticStringAggProgram), {format: 'json'}),
  success('sql-prefix-null-duplicates', sql),
  success('sql-limit-offset', sql + ' LIMIT 2 OFFSET 2', {expected: expected.slice(2, 4)}),
  success('pipe-following-empty-frame',
    `FROM records |> WHERE id > 0 |> SELECT id, ${call({frame: 'ORDER BY id ROWS BETWEEN 1 FOLLOWING AND 2 FOLLOWING'})} |> ORDER BY id`,
    {format: 'aql-text', expected: [{id: 1, names: 'b|a'}, {id: 2, names: 'a|b'},
      {id: 3, names: 'b'}, {id: 4, names: null}, {id: 5, names: null}]}),
  success('partition-duplicate-values',
    `SELECT id, ${call({frame: 'PARTITION BY amount ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW'})} FROM records WHERE id > 0 ORDER BY id`,
    {expected: [{id: 1, names: null}, {id: 2, names: 'b'}, {id: 3, names: 'a'},
      {id: 4, names: 'b|b'}, {id: 5, names: null}]}),
  success('default-comma-quoted-call',
    `SELECT id, ${call({function: '`sTrInG_aGg`', delimiter: ''})} FROM records WHERE id > 0 ORDER BY id`,
    {expected: [{id: 1, names: null}, {id: 2, names: 'b'}, {id: 3, names: 'b,a'},
      {id: 4, names: 'b,a,b'}, {id: 5, names: 'b,a,b'}]}),
  success('pipe-input-snapshot',
    `FROM records AS before |> WHERE id > 0 |> SET amount = 0 |> SELECT id, ${call({prefix: 'before.'})} |> ORDER BY id`,
    {format: 'aql-text'}),
  success('typed-empty', sql, {sourceRows: [], expected: []}),
  success('all-null', sql, {sourceRows: [{id: 2, amount: null}, {id: 1, amount: null}],
    expected: [{id: 1, names: null}, {id: 2, names: null}]}),
];
export const analyticStringAggRefusals = [
  `SELECT STRING_AGG(amount) OVER (${frame}) AS names FROM records`,
  `SELECT STRING_AGG(DISTINCT 'b') OVER (${frame}) AS names FROM records`,
  `SELECT STRING_AGG('b' WHERE id > 0) OVER (${frame}) AS names FROM records`,
  `SELECT STRING_AGG('b' ORDER BY id) OVER (${frame}) AS names FROM records`,
  "SELECT STRING_AGG('b') OVER (ORDER BY id) AS names FROM records",
  `SELECT STRING_AGG(@missing) OVER (${frame}) AS names FROM records`,
  `SELECT 'b' AS invented, STRING_AGG(invented) OVER (${frame}) AS names FROM records`,
  `FROM records AS old |> AS current |> SELECT STRING_AGG(CAST(old.amount AS STRING)) OVER (${frame}) AS names`,
].map((text, index) => ({name: 'analytic-string-agg-refuse-' + index, format: 'sql', text,
  // These sources fail in the already-pinned UnsupportedAnalytic branch.
  // Keep its public projection explicit rather than widening generic codes.
  ...(index >= 1 && index <= 4 ? {expectedCode: 'ClientProgramImplementationLimit'} : {})}));
export const analyticStringAggExecutionFailures = [{
  name: 'analytic-string-agg-demanded-expression-error', format: 'sql',
  text: `SELECT STRING_AGG(IF(1 / 0 > 0, 'a', 'b')) OVER (${frame}) AS names FROM records`,
  resultNames: ['main'], sourceReadSessionCount: 1,
}];


analyticStringAggSuccesses.push(success('grouped-delimiter',
  `SELECT id, ${call({delimiter: ", (('|'))"})} FROM records WHERE id > 0 ORDER BY id`));
