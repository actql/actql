// Independent finite-number examples: population/sample variance of [1,3]
// is 1/2; translating by 1 preserves it. NULL contributes no observation.
const number = {type: 'number', nullable: true};
const names = ['population', 'sample', 'population_sd', 'sample_sd'];
const columns = names.map(name => ({name, contract: number}));
const expected = [{population: 1, sample: 2, population_sd: 1, sample_sd: Math.SQRT2}];
const sourceRows = [{id: 2, amount: 3}, {id: 0, amount: 99},
  {id: 1, amount: 1}, {id: 3, amount: null}];
const expression = {add: [{field: 'amount'}, {literal: 1}]};
const aggregates = Object.fromEntries(['var_pop', 'var_samp', 'stddev_pop', 'stddev_samp']
  .map((fn, index) => [names[index], {fn, expr: expression}]));
export const statisticalAggregateProgram = {version: 'actql/0.1',
  id: 'fixture.statistical_aggregate', stages: [
    {id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
        {select: ['amount', 'id'], as: 'captured'}],
      results: {source: {from: 'captured', fields: ['amount', 'id']}}},
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', group: {by: [], aggregates}},
        {select: names, as: 'statistics'}],
      results: {rows: {from: 'statistics', fields: names}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const select = 'VAR_POP(amount + 1) AS population, VAR_SAMP(amount + 1) AS sample, ' +
  'STDDEV_POP(amount + 1) AS population_sd, STDDEV_SAMP(amount + 1) AS sample_sd';
const sql = `SELECT ${select} FROM records WHERE id > 0`;
const success = (name, text, extra = {}) => ({name: 'statistical-aggregate-' + name,
  format: 'sql', text, sourceRows, expected, columns, sourceReadSessionCount: 1, ...extra});
export const statisticalAggregateSuccesses = [
  success('independent-json', JSON.stringify(statisticalAggregateProgram), {format: 'json'}),
  success('sql-null-exclusion', sql),
  success('pipe-expressions', `FROM records |> WHERE id > 0 |> AGGREGATE ${select}`,
    {format: 'aql-text'}),
  success('sample-aliases', 'SELECT VARIANCE(amount) AS sample, STDDEV(amount) AS sample_sd FROM records WHERE id > 0',
    {expected: [{sample: 2, sample_sd: Math.SQRT2}], columns: columns.filter(x => x.name.startsWith('sample'))}),
  success('duplicates', sql, {sourceRows: [{id: 1, amount: 1}, {id: 2, amount: 1},
    {id: 3, amount: 3}, {id: 4, amount: 3}, {id: 5, amount: null}],
    expected: [{population: 1, sample: 4 / 3, population_sd: 1, sample_sd: Math.sqrt(4 / 3)}]}),
  success('singleton', sql, {sourceRows: [{id: 1, amount: 7}],
    expected: [{population: 0, sample: null, population_sd: 0, sample_sd: null}]}),
  success('all-null', sql, {sourceRows: [{id: 1, amount: null}],
    expected: [Object.fromEntries(names.map(name => [name, null]))]}),
  success('empty-typed', sql, {sourceRows: [],
    expected: [Object.fromEntries(names.map(name => [name, null]))]}),
  success('group-order-limit', 'SELECT id, VAR_POP(amount) AS v FROM records WHERE id > 0 GROUP BY id HAVING v IS NOT NULL ORDER BY v DESC, id LIMIT 1 OFFSET 1',
    {sourceRows: [{id: 2, amount: 4}, {id: 1, amount: 3}, {id: 2, amount: 0},
      {id: 1, amount: 1}, {id: 3, amount: null}], expected: [{id: 1, v: 1}],
      columns: [{name: 'id', contract: {type: 'number', nullable: false}}, {name: 'v', contract: number}]}),
  success('analytic-prefix', 'SELECT id, VAR_POP(amount) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM records WHERE id > 0 ORDER BY id',
    {sourceRows: [{id: 3, amount: 3}, {id: 1, amount: null}, {id: 2, amount: 1}],
      expected: [{id: 1, v: null}, {id: 2, v: 0}, {id: 3, v: 1}],
      columns: [{name: 'id', contract: {type: 'number', nullable: false}}, {name: 'v', contract: number}]}),
];
export const statisticalAggregateRefusals = [
  "SELECT VAR_POP('not a number') AS v FROM records",
  'SELECT VAR_SAMP(DISTINCT amount) AS v FROM records',
  'SELECT STDDEV_POP(amount + @missing) AS v FROM records',
  'SELECT VAR_POP(amount) OVER (ORDER BY id) AS v FROM records',
  'SELECT VAR_POP(*) AS v FROM records',
].map((text, index) => ({name: 'statistical-aggregate-refuse-' + index, format: 'sql', text}));
export const statisticalAggregateExecutionFailures = [{
  name: 'statistical-aggregate-demanded-error', format: 'sql',
  text: 'SELECT VAR_POP(1 / 0) AS v FROM records',
  resultNames: ['answer'], sourceReadSessionCount: 1,
}];
