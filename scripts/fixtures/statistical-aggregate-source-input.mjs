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
// Groups 1 and 4 both have sample variance 2. Group 2 has variance 8;
// group 3 has no observations. DISTINCT removes the repeated 2, not NULL.
const aliasRows = [{id: 2, amount: 4}, {id: 4, amount: 3},
  {id: 1, amount: 1}, {id: 3, amount: null}, {id: 2, amount: 0},
  {id: 1, amount: 3}, {id: 4, amount: 1}, {id: 0, amount: 99}];
const aliasColumns = [{name: 'v', contract: number}];
const aliasExpected = [{v: 2}, {v: 8}, {v: null}];
// Authored directly from the common operation contract, without compiling SQL.
export const statisticalAliasProgram = {version: 'actql/0.1',
  id: 'fixture.statistical_alias', stages: [
    {id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
        {select: ['amount', 'id'], as: 'captured'}],
      results: {source: {from: 'captured', fields: ['amount', 'id']}}},
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', group: {by: ['id'],
        aggregates: {v: {fn: 'var_samp', field: 'amount'}}}},
      {select: ['v']}, {distinct: ['v']},
      {sort: [{field: 'v', dir: 'asc', nulls: 'last'}], as: 'statistics'}],
      results: {rows: {from: 'statistics', fields: ['v']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const aliasSuccess = (name, text, extra = {}) => success(name, text,
  {sourceRows: aliasRows, expected: aliasExpected, columns: aliasColumns, ...extra});
export const statisticalAggregateSuccesses = [
  success('independent-json', JSON.stringify(statisticalAggregateProgram), {format: 'json'}),
  success('sql-null-exclusion', sql),
  success('quoted-sql',
    'SELECT `vAr_PoP`(amount + 1) AS population, `VAR_SAMP`(amount + 1) AS sample, ' +
    '`STDDEV_POP`(amount + 1) AS population_sd, `STDDEV_SAMP`(amount + 1) AS sample_sd ' +
    'FROM records WHERE id > 0'),
  success('quoted-pipe',
    'FROM records |> WHERE id > 0 |> AGGREGATE `\\x56AR_POP`(amount + 1) AS population, ' +
    '`VAR_SAMP`(amount + 1) AS sample, `STDDEV_POP`(amount + 1) AS population_sd, ' +
    '`STDDEV_SAMP`(amount + 1) AS sample_sd', {format: 'aql-text'}),
  success('quoted-count-empty', 'SELECT `COUNT`(*) AS n WHERE FALSE',
    {sourceReadSessionCount: 0, expected: [{n: 0}],
      columns: [{name: 'n', contract: {type: 'number', nullable: false}}]}),
  success('pipe-expressions', `FROM records |> WHERE id > 0 |> AGGREGATE ${select}`,
    {format: 'aql-text'}),
  success('sample-aliases', 'SELECT VARIANCE(amount) AS sample, STDDEV(amount) AS sample_sd FROM records WHERE id > 0',
    {expected: [{sample: 2, sample_sd: Math.SQRT2}], columns: columns.filter(x => x.name.startsWith('sample'))}),
  aliasSuccess('alias-independent-json', JSON.stringify(statisticalAliasProgram), {format: 'json'}),
  aliasSuccess('variance-order-sample', 'SELECT DISTINCT VARIANCE(amount) AS v FROM records WHERE id > 0 GROUP BY id ORDER BY VAR_SAMP(amount) NULLS LAST'),
  aliasSuccess('sample-order-variance', 'SELECT DISTINCT VAR_SAMP(amount) AS v FROM records WHERE id > 0 GROUP BY id ORDER BY VARIANCE(records.amount) NULLS LAST'),
  aliasSuccess('quoted-variance-order-sample', 'SELECT DISTINCT `vArIaNcE`(amount) AS v FROM records WHERE id > 0 GROUP BY id ORDER BY `VAR_SAMP`(amount) NULLS LAST'),
  aliasSuccess('stddev-order-sample', 'SELECT DISTINCT STDDEV(amount) AS v FROM records WHERE id > 0 GROUP BY id ORDER BY STDDEV_SAMP(amount) NULLS LAST',
    {expected: [{v: Math.SQRT2}, {v: 2 * Math.SQRT2}, {v: null}]}),
  aliasSuccess('sample-order-stddev', 'SELECT DISTINCT STDDEV_SAMP(amount) AS v FROM records WHERE id > 0 GROUP BY id ORDER BY STDDEV(amount) NULLS LAST',
    {expected: [{v: Math.SQRT2}, {v: 2 * Math.SQRT2}, {v: null}]}),
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
  success('quoted-analytic-prefix', 'SELECT id, `VAR_POP`(amount) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM records WHERE id > 0 ORDER BY id',
    {sourceRows: [{id: 3, amount: 3}, {id: 1, amount: null}, {id: 2, amount: 1}],
      expected: [{id: 1, v: null}, {id: 2, v: 0}, {id: 3, v: 1}],
      columns: [{name: 'id', contract: {type: 'number', nullable: false}}, {name: 'v', contract: number}]}),
];
// The selected inline OVER profile requires an explicit ROWS frame. This
// valid GoogleSQL form is an implementation gap, not a malformed input.
const defaultAnalyticFrame = 'SELECT VAR_POP(amount) OVER (ORDER BY id) AS v FROM records';
export const statisticalAggregateRefusals = [
  "SELECT VAR_POP('not a number') AS v FROM records",
  'SELECT VAR_SAMP(DISTINCT amount) AS v FROM records',
  'SELECT STDDEV_POP(amount + @missing) AS v FROM records',
  defaultAnalyticFrame,
  'SELECT VAR_POP(*) AS v FROM records',
  'SELECT `VAR_POP`(*) AS v FROM records',
  "SELECT `VAR_POP`('not a number') AS v FROM records",
  'SELECT `COUNT`(DISTINCT *) AS n FROM records',
  'SELECT DISTINCT VARIANCE(amount) AS v FROM records ORDER BY VAR_POP(amount)',
  'SELECT DISTINCT VARIANCE(amount) AS v FROM records ORDER BY VAR_SAMP(amount + 1)',
].map((text, index) => ({name: 'statistical-aggregate-refuse-' + index, format: 'sql', text,
  ...(text === defaultAnalyticFrame || text.startsWith('SELECT DISTINCT VARIANCE')
    ? {expectedCode: 'ClientProgramImplementationLimit'} : {}),
}));
export const statisticalAggregateExecutionFailures = [{
  name: 'statistical-aggregate-demanded-error', format: 'sql',
  text: 'SELECT VAR_POP(1 / 0) AS v FROM records',
  resultNames: ['main'], sourceReadSessionCount: 1,
}];
