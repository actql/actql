// Independent Program and rows: named specifications change no analytic law.
const number = {type: 'number', nullable: false};
const nullable = {...number, nullable: true};
const column = (name, contract = number) => ({name, contract});
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 0, amount: 99}];
const expected = [{id: 2, n: 1}, {id: 3, n: 2}, {id: 3, n: 3}, {id: 1, n: 4}];
export const namedWindowProgram = {version: 'actql/0.1', id: 'fixture.named_window',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', analytic: {partition_by: [], order_by: [
      {field: 'amount', dir: 'asc', nulls: 'last'}, {field: 'id', dir: 'asc', nulls: 'first'}],
      functions: {n: {fn: 'row_number'}}}}, {select: ['id', 'n']},
    {sort: [{field: 'n', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const sql = 'SELECT id, ROW_NUMBER() OVER w AS n FROM records WHERE id > 0 '
  + 'WINDOW w AS (ORDER BY amount NULLS LAST, id) ORDER BY n';
const success = (name, text, extra = {}) => ({name: 'named-window-' + name,
  format: 'sql', text, sourceRows, sourceReadSessionCount: 1, expected,
  columns: [column('id'), column('n')], ...extra});
const one = [{id: 1, n: 1}, {id: 2, n: 1}, {id: 3, n: 1}, {id: 3, n: 1}];
// Independently authored grouped control: counts are 1,1,2 for id 1,2,3.
export const namedAggregateWindowProgram = structuredClone(namedWindowProgram);
namedAggregateWindowProgram.id = 'fixture.named_aggregate_window';
namedAggregateWindowProgram.stages[1].steps = [
  {from: 'records', group: {by: ['id'], aggregates: {counted: {fn: 'count'}}}},
  {analytic: {partition_by: [], order_by: [
    {field: 'counted', dir: 'desc', nulls: 'last'}, {field: 'id', dir: 'asc', nulls: 'first'}],
    functions: {n: {fn: 'row_number'}}}},
  {select: ['id', 'n']}, {sort: [{field: 'n', dir: 'asc', nulls: 'first'}], as: 'ordered'},
];
const groupedExpected = [{id: 3, n: 1}, {id: 1, n: 2}, {id: 2, n: 3}];
const aggregateSql = 'SELECT records.id, ROW_NUMBER() OVER w AS n FROM records WHERE id > 0 '
  + 'GROUP BY records.id WINDOW w AS (ORDER BY COUNT(*) DESC, records.id) ORDER BY n';
export const namedWindowSuccesses = [
  success('independent-json', JSON.stringify(namedWindowProgram), {format: 'json'}),
  success('bare-reference', sql),
  success('quoted-case-fold', 'SELECT id, ROW_NUMBER() OVER (`By Amount`) AS n '
    + 'FROM records WHERE id > 0 WINDOW `by amount` AS (ORDER BY amount NULLS LAST, id) ORDER BY n'),
  success('declaration-inheritance', 'SELECT id, ROW_NUMBER() OVER final AS n FROM records WHERE id > 0 '
    + 'WINDOW base AS (PARTITION BY id), ordered AS (base ORDER BY amount NULLS LAST), final AS ordered ORDER BY id, n', {
    expected: [{id: 1, n: 1}, {id: 2, n: 1}, {id: 3, n: 1}, {id: 3, n: 2}],
  }),
  success('inline-frame-extension', 'SELECT id, COUNT(*) OVER (w ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS n '
    + 'FROM records WHERE id > 0 WINDOW w AS (ORDER BY id) ORDER BY id', {expected: one}),
  success('framed-alias', 'SELECT id, COUNT(*) OVER final AS n FROM records WHERE id > 0 '
    + 'WINDOW ordered AS (ORDER BY id), framed AS (ordered ROWS BETWEEN CURRENT ROW AND CURRENT ROW), final AS framed ORDER BY id', {expected: one}),
  success('hidden-qualify', 'SELECT id FROM records WHERE id > 0 QUALIFY ROW_NUMBER() OVER w = 1 '
    + 'WINDOW w AS (ORDER BY amount NULLS LAST, id) ORDER BY id', {columns: [column('id')], expected: [{id: 2}]}),
  success('qualify-alias-collision', 'SELECT amount, ROW_NUMBER() OVER w AS id FROM records WHERE id > 0 '
    + 'QUALIFY id = 1 WINDOW w AS (ORDER BY records.amount NULLS LAST, records.id) ORDER BY id', {
    columns: [column('amount', nullable), column('id')], expected: [{amount: 20, id: 1}],
  }),
  success('qualify-qualified-control', 'SELECT amount, ROW_NUMBER() OVER w AS id FROM records WHERE id > 0 '
    + 'QUALIFY records.id = 1 WINDOW w AS (ORDER BY records.amount NULLS LAST, records.id) ORDER BY id', {
    columns: [column('amount', nullable), column('id')], expected: [{amount: null, id: 4}],
  }),
  success('group-having', 'SELECT id, COUNT(*) AS total, ROW_NUMBER() OVER w AS n '
    + 'FROM records WHERE id > 0 GROUP BY id HAVING total > 0 QUALIFY n <= 2 '
    + 'WINDOW w AS (ORDER BY id DESC) ORDER BY id', {
    columns: [column('id'), column('total'), column('n')],
    expected: [{id: 2, total: 1, n: 2}, {id: 3, total: 2, n: 1}],
  }),
  success('cte-and-pipe', 'WITH chosen AS (SELECT id FROM records WHERE id > 0 '
    + 'QUALIFY ROW_NUMBER() OVER w = 1 WINDOW w AS (ORDER BY amount NULLS LAST, id)) '
    + 'FROM chosen |> SELECT id |> ORDER BY id', {format: 'aql-text', columns: [column('id')], expected: [{id: 2}]}),
  success('unused-specification-no-evaluation', 'SELECT id, ROW_NUMBER() OVER w AS n FROM records WHERE id > 0 '
    + 'WINDOW unused AS (ORDER BY 1 / 0), w AS (ORDER BY amount NULLS LAST, id) ORDER BY n'),
  success('typed-empty', sql, {sourceRows: [], expected: []}),
  success('aggregate-independent-json', JSON.stringify(namedAggregateWindowProgram),
    {format: 'json', expected: groupedExpected}),
  success('aggregate-order-key', aggregateSql, {expected: groupedExpected}),
  success('aggregate-partition-inheritance', 'SELECT id, ROW_NUMBER() OVER final AS n FROM records '
    + 'WHERE id > 0 GROUP BY id WINDOW base AS (PARTITION BY COUNT(*)), '
    + 'ordered AS (base ORDER BY id), final AS ordered ORDER BY id',
    {expected: [{id: 1, n: 1}, {id: 2, n: 2}, {id: 3, n: 1}]}),
  success('aggregate-nullable-count', 'SELECT records.id, ROW_NUMBER() OVER (`W`) AS n FROM records '
    + 'WHERE id > 0 GROUP BY records.id WINDOW w AS (ORDER BY COUNT(amount) + 1 DESC, records.id) ORDER BY n',
    {expected: [{id: 3, n: 1}, {id: 2, n: 2}, {id: 1, n: 3}]}),
  success('aggregate-reused-alias-collision', 'SELECT records.id AS original, COUNT(*) AS id, '
    + 'ROW_NUMBER() OVER w AS n FROM records WHERE id > 0 GROUP BY records.id '
    + 'WINDOW w AS (ORDER BY COUNT(*) DESC, records.id) ORDER BY n',
    {columns: [column('original'), column('id'), column('n')],
      expected: [{original: 3, id: 2, n: 1}, {original: 1, id: 1, n: 2}, {original: 2, id: 1, n: 3}]}),
  success('aggregate-hidden-qualify', 'SELECT id FROM records WHERE id > 0 GROUP BY id '
    + 'QUALIFY ROW_NUMBER() OVER w = 1 WINDOW w AS (ORDER BY SUM(amount) DESC NULLS LAST, id) ORDER BY id',
    {columns: [column('id')], expected: [{id: 3}]}),
  success('aggregate-global-having', 'SELECT ROW_NUMBER() OVER w AS n FROM records WHERE id > 0 '
    + 'HAVING TRUE WINDOW w AS (ORDER BY COUNT(*))',
    {columns: [column('n')], expected: [{n: 1}]}),
  success('aggregate-global-empty', 'SELECT ROW_NUMBER() OVER w AS n FROM records WHERE id > 0 '
    + 'WINDOW w AS (ORDER BY COUNT(*))', {sourceRows: [], columns: [column('n')], expected: [{n: 1}]}),
  success('aggregate-typed-empty', aggregateSql, {sourceRows: [], expected: []}),
  success('aggregate-unused-no-evaluation', 'SELECT id, ROW_NUMBER() OVER w AS n FROM records WHERE id > 0 '
    + 'WINDOW unused AS (ORDER BY SUM(1 / 0)), w AS (ORDER BY amount NULLS LAST, id) ORDER BY n'),
  success('aggregate-having-before-window', 'SELECT id, COUNT(*) AS total, ROW_NUMBER() OVER w AS n '
    + 'FROM records WHERE id > 0 GROUP BY id HAVING total > 1 '
    + 'WINDOW w AS (ORDER BY COUNT(*) DESC, id) ORDER BY n',
    {columns: [column('id'), column('total'), column('n')], expected: [{id: 3, total: 2, n: 1}]}),
  success('aggregate-multiple-consumers', 'SELECT id, ROW_NUMBER() OVER w AS n, RANK() OVER other AS ranking '
    + 'FROM records WHERE id > 0 GROUP BY id WINDOW w AS (ORDER BY COUNT(*) DESC, id), '
    + 'other AS (ORDER BY COUNT(*) DESC, id) ORDER BY n',
    {columns: [column('id'), column('n'), column('ranking')],
      expected: [{id: 3, n: 1, ranking: 1}, {id: 1, n: 2, ranking: 2}, {id: 2, n: 3, ranking: 3}]}),
];
export const namedWindowRefusals = [
  'SELECT ROW_NUMBER() OVER absent AS n FROM records',
  'SELECT ROW_NUMBER() OVER w AS n FROM records WINDOW w AS later, later AS (ORDER BY id)',
  'SELECT ROW_NUMBER() OVER w AS n FROM records WINDOW w AS w',
  'SELECT ROW_NUMBER() OVER w AS n FROM records WINDOW w AS (ORDER BY id), `W` AS (ORDER BY amount)',
  'SELECT ROW_NUMBER() OVER (w ORDER BY amount) AS n FROM records WINDOW w AS (ORDER BY id)',
  'SELECT ROW_NUMBER() OVER (w PARTITION BY id) AS n FROM records WINDOW w AS (ORDER BY id)',
  'SELECT COUNT(*) OVER (w ORDER BY id) AS n FROM records WINDOW w AS (ROWS BETWEEN CURRENT ROW AND CURRENT ROW)',
  'WITH chosen AS (SELECT ROW_NUMBER() OVER w AS n FROM records WINDOW w AS (ORDER BY id)) SELECT ROW_NUMBER() OVER w AS n FROM chosen',
  'SELECT -id AS changed, ROW_NUMBER() OVER w AS n FROM records WINDOW w AS (ORDER BY changed)',
  'SELECT COUNT(*) OVER w AS n FROM records WINDOW w AS (ORDER BY id ROWS BETWEEN @missing PRECEDING AND CURRENT ROW)',
  'SELECT id AS invented, ROW_NUMBER() OVER w AS n FROM records GROUP BY id WINDOW w AS (ORDER BY COUNT(invented), id)',
  'SELECT id, ROW_NUMBER() OVER w AS n FROM records GROUP BY id WINDOW w AS (ORDER BY COUNT(*) OVER (ORDER BY id))',
  'SELECT ROW_NUMBER() OVER w AS n FROM records HAVING TRUE WINDOW unused AS (ORDER BY COUNT(*)), w AS (ORDER BY id)',
  'SELECT id, ROW_NUMBER() OVER w AS n FROM records GROUP BY id WINDOW w AS (ORDER BY SUM(records.amount), records.amount)',
].map((text, index) => ({name: 'named-window-refuse-' + index, format: 'sql', text}));
