// Independent extrema and multiplicity expectations. Removing duplicate input
// rows globally would change SUM and COUNT alongside the duplicate-insensitive
// MIN/MAX, so this is not satisfied by a pre-aggregation DISTINCT rewrite.
const number = {type: 'number', nullable: false};
const nullable = {...number, nullable: true};
const names = ['low', 'high', 'total', 'observed'];
const columns = names.map(name => ({name, contract: name === 'observed' ? number : nullable}));
const sourceRows = [{id: 0, amount: 99}, {id: 1, amount: 1}, {id: 1, amount: 1},
  {id: 2, amount: 3}, {id: 3, amount: null}];
const expected = [{low: 2, high: 4, total: 5, observed: 4}];
const shifted = {add: [{field: 'amount'}, {literal: 1}]};
export const minMaxDistinctProgram = {version: 'actql/0.1', id: 'fixture.min_max_distinct',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', group: {by: [], aggregates: {
      low: {fn: 'min', expr: shifted}, high: {fn: 'max', expr: shifted},
      total: {fn: 'sum', field: 'amount'}, observed: {fn: 'count'},
    }}}, {select: names, as: 'extrema'}],
    results: {rows: {from: 'extrema', fields: names}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const list = 'MIN(DISTINCT amount + 1) AS low, MAX(DISTINCT amount + 1) AS high, '
  + 'SUM(amount) AS total, COUNT(*) AS observed';
const sql = `SELECT ${list} FROM records WHERE id > 0`;
const success = (name, text, extra = {}) => ({name: 'min-max-distinct-' + name,
  format: 'sql', text, sourceRows, expected, columns, sourceReadSessionCount: 1, ...extra});
export const minMaxDistinctSuccesses = [
  success('independent-json', JSON.stringify(minMaxDistinctProgram), {format: 'json'}),
  success('sql-duplicates-and-null', sql),
  success('pipe-duplicates-and-null', `FROM records |> WHERE id > 0 |> AGGREGATE ${list}`, {format: 'aql-text'}),
  success('quoted-functions', 'SELECT `\\x4dIN`(DISTINCT amount + 1) AS low, `mAx`(DISTINCT amount + 1) AS high, '
    + 'SUM(amount) AS total, COUNT(*) AS observed FROM records WHERE id > 0'),
  success('per-call-filter', 'SELECT MIN(DISTINCT amount + 1 WHERE id > 1) AS low, '
    + 'MAX(DISTINCT amount + 1 WHERE id > 1) AS high, SUM(amount) AS total, COUNT(*) AS observed '
    + 'FROM records WHERE id > 0', {expected: [{low: 4, high: 4, total: 5, observed: 4}]}),
  success('group-having-order-limit', `SELECT id, ${list} FROM records WHERE id > 0 `
    + 'GROUP BY id HAVING high IS NOT NULL ORDER BY high DESC, id LIMIT 1 OFFSET 1',
    {expected: [{id: 1, low: 2, high: 2, total: 2, observed: 2}],
      columns: [{name: 'id', contract: number}, ...columns]}),
  success('all-null', sql, {sourceRows: [{id: 1, amount: null}],
    expected: [{low: null, high: null, total: null, observed: 1}]}),
  success('typed-empty', sql, {sourceRows: [], expected: [{low: null, high: null, total: null, observed: 0}]}),
  success('parameter-preservation', 'SELECT MIN(DISTINCT amount + @increment) AS low, '
    + 'MAX(DISTINCT amount + @increment) AS high, SUM(amount) AS total, COUNT(*) AS observed '
    + 'FROM records WHERE id >= @minimum', {parameterDeclarations: {increment: number, minimum: number},
      parameters: {increment: -1, minimum: 2}, expected: [{low: 2, high: 2, total: 3, observed: 2}]}),
  success('empty-coalesce', 'SELECT COALESCE(MIN(DISTINCT amount), 0) AS value FROM records WHERE FALSE',
    {expected: [{value: 0}], columns: [{name: 'value', contract: number}]}),
  success('source-free', 'SELECT MIN(DISTINCT 1) AS low, MAX(DISTINCT 2) AS high',
    {expected: [{low: 1, high: 2}], columns: columns.slice(0, 2), sourceReadCount: 0, sourceReadSessionCount: 0}),
];
export const minMaxDistinctRefusals = [
  {text: 'SELECT MIN(DISTINCT *) AS value FROM records'},
  {text: 'SELECT MAX(DISTINCT *) AS value FROM records'},
  {text: 'SELECT MIN(DISTINCT) AS value FROM records'},
  {text: 'SELECT MAX(DISTINCT amount, id) AS value FROM records'},
  {text: 'SELECT MIN(DISTINCT amount + @missing) AS value FROM records'},
  {text: "SELECT MIN(DISTINCT JSON 'null') AS value FROM records"},
  {text: 'SELECT MIN(DISTINCT amount) OVER () AS value FROM records', expectedCode: 'ClientProgramImplementationLimit'},
].map((item, index) => ({name: 'min-max-distinct-refuse-' + index, format: 'sql', ...item}));
