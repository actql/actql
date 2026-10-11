// Independently calculated physical ROWS windows in ascending ID order.
// Short frames have an implicit CURRENT ROW end, never a RANGE peer group.
const number = {type: 'number', nullable: false};
const columns = [{name: 'id', contract: number},
  {name: 'total', contract: {...number, nullable: true}}];
const sourceRows = [{id: 4, amount: 20}, {id: 1, amount: null},
  {id: 3, amount: 10}, {id: 2, amount: 20}, {id: 5, amount: null},
  {id: 0, amount: 999}];
const expected = [{id: 1, total: null}, {id: 2, total: 20}, {id: 3, total: 30},
  {id: 4, total: 30}, {id: 5, total: 20}];
export const shortRowsProgram = {version: 'actql/0.1', id: 'fixture.short_rows',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', analytic: {partition_by: [],
      order_by: [{field: 'id', dir: 'asc', nulls: 'first'}],
      functions: {total: {fn: 'sum', field: 'amount'}},
      frame: {start: {preceding: 1}, end: 'current_row'}}},
      {select: ['id', 'total']},
      {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'total']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const sql = boundary => `SELECT id, SUM(amount) OVER (ORDER BY id ROWS ${boundary}) AS total FROM records WHERE id > 0 ORDER BY id`;
const success = (name, text, extra = {}) => ({name: 'short-rows-' + name,
  format: 'sql', text, sourceRows, columns, expected, sourceReadSessionCount: 1, ...extra});
// Handwritten zero-distance controls: CURRENT ROW selects exactly the physical
// current occurrence, preserving NULL observations and repeated amount values.
const zeroExpected = [{id: 1, total: null}, {id: 2, total: 20},
  {id: 3, total: 10}, {id: 4, total: 20}, {id: 5, total: null}];
export const zeroRowsProgram = {version: 'actql/0.1', id: 'fixture.zero_rows',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', analytic: {partition_by: [],
      order_by: [{field: 'id', dir: 'asc', nulls: 'first'}],
      functions: {total: {fn: 'sum', field: 'amount'}},
      frame: {start: 'current_row', end: 'current_row'}}},
      {select: ['id', 'total']},
      {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'total']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const shortRowsSuccesses = [
  success('zero-independent-json', JSON.stringify(zeroRowsProgram),
    {format: 'json', expected: zeroExpected}),
  success('zero-sql-both-directions', sql('BETWEEN 0 PRECEDING AND 0 FOLLOWING'),
    {expected: zeroExpected}),
  success('zero-pipe-short', 'FROM records |> WHERE id > 0 '
    + '|> SELECT id, SUM(amount) OVER (ORDER BY id ROWS 0 PRECEDING) AS total |> ORDER BY id',
    {format: 'aql-text', expected: zeroExpected}),
  success('zero-named-following', 'SELECT id, SUM(amount) OVER w AS total '
    + 'FROM records WHERE id > 0 WINDOW w AS (ORDER BY id ROWS BETWEEN 0 FOLLOWING AND 1 FOLLOWING) ORDER BY id',
    {expected: [{id: 1, total: 20}, {id: 2, total: 30}, {id: 3, total: 30},
      {id: 4, total: 20}, {id: 5, total: null}]}),
  success('zero-typed-empty', sql('BETWEEN 0 PRECEDING AND 0 PRECEDING'),
    {sourceRows: [], expected: []}),
  success('independent-json', JSON.stringify(shortRowsProgram), {format: 'json'}),
  success('sql-preceding', sql('1 PRECEDING')),
  success('pipe-preceding', 'FROM records |> WHERE id > 0 '
    + '|> SELECT id, SUM(amount) OVER (ORDER BY id ROWS 1 PRECEDING) AS total |> ORDER BY id',
  {format: 'aql-text'}),
  success('unbounded-preceding', sql('UNBOUNDED PRECEDING'),
    {expected: [{id: 1, total: null}, {id: 2, total: 20}, {id: 3, total: 30},
      {id: 4, total: 50}, {id: 5, total: 50}]}),
  success('current-row', sql('CURRENT ROW'),
    {expected: [{id: 1, total: null}, {id: 2, total: 20}, {id: 3, total: 10},
      {id: 4, total: 20}, {id: 5, total: null}]}),
  success('named-window-extension', 'SELECT id, SUM(amount) OVER (w ROWS 1 PRECEDING) AS total '
    + 'FROM records WHERE id > 0 WINDOW w AS (ORDER BY id) ORDER BY id'),
  success('parameter-preceding', sql('@before PRECEDING'),
    {parameterDeclarations: {before: number}, parameters: {before: 2},
      expected: [{id: 1, total: null}, {id: 2, total: 20}, {id: 3, total: 30},
        {id: 4, total: 50}, {id: 5, total: 30}]}),
  success('qualify-private-window', 'SELECT id FROM records WHERE id > 0 '
    + 'QUALIFY SUM(amount) OVER (ORDER BY id ROWS 1 PRECEDING) > 25 ORDER BY id',
  {columns: [columns[0]], expected: [{id: 3}, {id: 4}]}),
  success('typed-empty', sql('1 PRECEDING'), {sourceRows: [], expected: []}),
];
export const shortRowsRefusals = [
  {name: 'zero-parameter', text: sql('@before PRECEDING'),
    parameterDeclarations: {before: number}, parameters: {before: 0}},
  ...['0 FOLLOWING', 'BETWEEN CURRENT ROW AND 0 PRECEDING',
    'BETWEEN 0 FOLLOWING AND CURRENT ROW', 'BETWEEN 0 FOLLOWING AND 0 PRECEDING']
    .map((boundary, index) => ({name: 'zero-category-' + index, text: sql(boundary)})),
  {name: 'following-start', text: sql('1 FOLLOWING')},
  {name: 'unbounded-following-start', text: sql('UNBOUNDED FOLLOWING')},
  {name: 'fractional-parameter', text: sql('@before PRECEDING'),
    parameterDeclarations: {before: number}, parameters: {before: 1.5}},
  {name: 'undeclared-parameter', text: sql('@missing PRECEDING')},
  {name: 'missing-boundary', text: sql('')},
].map(item => ({format: 'sql', ...item, name: 'short-rows-refuse-' + item.name,
  expectedCode: 'ClientProgramInvalidInput'}));
