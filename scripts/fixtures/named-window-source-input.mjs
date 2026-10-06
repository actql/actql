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
].map((text, index) => ({name: 'named-window-refuse-' + index, format: 'sql', text}));
