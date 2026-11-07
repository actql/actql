// Authored from QUALIFY's window -> filter -> DISTINCT -> order/limit rules.
// The ordinary JSON control and result contracts do not use compiler output.
const number = {type: 'number', nullable: false};
const nullable = {...number, nullable: true};
const column = (name, contract = number) => ({name, contract});
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 0, amount: 99}];
export const qualifyProgram = {version: 'actql/0.1', id: 'fixture.qualify',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', analytic: {partition_by: [], order_by: [
      {field: 'amount', dir: 'asc', nulls: 'last'},
      {field: 'id', dir: 'asc', nulls: 'first'}], functions: {n: {fn: 'row_number'}}}},
    {filter: {lte: [{field: 'n'}, {literal: 2}]}}, {select: ['id', 'n']},
    {sort: [{field: 'n', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const sql = 'SELECT id, ROW_NUMBER() OVER (ORDER BY amount NULLS LAST, id) AS n '
  + 'FROM records WHERE id > 0 QUALIFY n <= 2 ORDER BY n';
const success = (name, text, extra = {}) => ({name: 'qualify-' + name,
  format: 'aql-text', text, sourceRows, sourceReadSessionCount: 1,
  expected: [{id: 2, n: 1}, {id: 3, n: 2}], columns: [column('id'), column('n')], ...extra});
export const qualifySuccesses = [
  success('independent-json', JSON.stringify(qualifyProgram), {format: 'json'}),
  success('window-alias', sql, {format: 'sql'}),
  success('alias-collision', 'SELECT amount, ROW_NUMBER() OVER (ORDER BY amount NULLS LAST, id) AS id '
    + 'FROM records WHERE id > 0 QUALIFY id = 1 ORDER BY id', {
    columns: [column('amount', nullable), column('id')], expected: [{amount: 20, id: 1}],
  }),
  success('qualified-input-control', 'SELECT amount, ROW_NUMBER() OVER (ORDER BY amount NULLS LAST, id) AS id '
    + 'FROM records WHERE id > 0 QUALIFY records.id = 1 ORDER BY id', {
    columns: [column('amount', nullable), column('id')], expected: [{amount: null, id: 4}],
  }),
  success('scalar-alias-reuse', 'SELECT -id AS id, ROW_NUMBER() OVER (ORDER BY id) AS n '
    + 'FROM records WHERE id > 0 QUALIFY id < -1 ORDER BY id, n', {
    expected: [{id: -3, n: 3}, {id: -3, n: 4}, {id: -2, n: 2}],
  }),
  success('hidden-window', 'SELECT id FROM records WHERE id > 0 '
    + 'QUALIFY ROW_NUMBER() OVER (ORDER BY amount NULLS LAST, id) = 1 ORDER BY id', {
    columns: [column('id')], expected: [{id: 2}],
  }),
  success('quoted-hidden-window', 'SELECT id FROM records WHERE id > 0 '
    + 'QUALIFY `rOw_NuMbEr`() OVER (ORDER BY amount NULLS LAST, id) = 1 ORDER BY id', {
    columns: [column('id')], expected: [{id: 2}],
  }),
  success('escaped-hidden-window', 'SELECT id FROM records WHERE id > 0 '
    + 'QUALIFY `\\x52OW_NUMBER`() OVER (ORDER BY amount NULLS LAST, id) = 1 ORDER BY id', {
    columns: [column('id')], expected: [{id: 2}],
  }),
  success('quoted-rank-duplicates', 'SELECT id FROM records WHERE id > 0 '
    + 'QUALIFY `RANK`() OVER (ORDER BY amount NULLS LAST, id) <= 2 ORDER BY id', {
    columns: [column('id')], expected: [{id: 2}, {id: 3}, {id: 3}],
  }),
  success('quoted-window-name-is-column', 'SELECT id AS `ROW_NUMBER`, '
    + 'ROW_NUMBER() OVER (ORDER BY id) AS n FROM records WHERE id > 0 '
    + 'QUALIFY `ROW_NUMBER` = 2 ORDER BY n', {
    columns: [column('ROW_NUMBER'), column('n')], expected: [{ROW_NUMBER: 2, n: 2}],
  }),
  success('nullable-filter-and-duplicates', 'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n '
    + 'FROM records WHERE id > 0 QUALIFY amount > 25 AND n > 0 ORDER BY n', {
    expected: [{id: 3, n: 3}, {id: 3, n: 4}],
  }),
  success('null-predicate', 'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n '
    + 'FROM records WHERE id > 0 QUALIFY CAST(NULL AS BOOL) AND n > 0 ORDER BY n', {expected: []}),
  success('distinct-order-limit', 'SELECT DISTINCT amount FROM records WHERE id > 0 '
    + 'QUALIFY ROW_NUMBER() OVER (ORDER BY id) <= 4 ORDER BY amount NULLS LAST LIMIT 1 OFFSET 1', {
    columns: [column('amount', nullable)], expected: [{amount: 30}],
  }),
  success('group-having-hidden-aggregate', 'SELECT id, COUNT(*) AS total, '
    + 'ROW_NUMBER() OVER (ORDER BY id DESC) AS n FROM records WHERE id > 0 '
    + 'GROUP BY id HAVING total > 0 QUALIFY n <= 2 AND COUNT(*) > 0 ORDER BY id', {
    columns: [column('id'), column('total'), column('n')],
    expected: [{id: 2, total: 1, n: 2}, {id: 3, total: 2, n: 1}],
  }),
  success('cte-and-pipe', 'WITH chosen AS (SELECT id FROM records WHERE id > 0 '
    + 'QUALIFY ROW_NUMBER() OVER (ORDER BY amount NULLS LAST, id) = 1) '
    + 'FROM chosen |> SELECT id |> ORDER BY id', {columns: [column('id')], expected: [{id: 2}]}),
  success('join', 'SELECT l.id, ROW_NUMBER() OVER (ORDER BY l.id) AS n FROM records AS l '
    + 'JOIN (SELECT 2 AS k UNION ALL SELECT 3 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 10 '
    + 'QUALIFY n <= 2 ORDER BY n', {expected: [{id: 2, n: 1}, {id: 3, n: 2}]}),
  success('undemanded-select-error', 'SELECT 1 / (id - 1) AS ratio, '
    + 'ROW_NUMBER() OVER (ORDER BY id) AS n FROM records WHERE id > 0 QUALIFY n > 1 ORDER BY n', {
    columns: [column('ratio'), column('n')],
    expected: [{ratio: 1, n: 2}, {ratio: 0.5, n: 3}, {ratio: 0.5, n: 4}],
  }),
  success('qualified-range-does-not-demand-alias', 'SELECT 1 / (id - 1) AS records, '
    + 'ROW_NUMBER() OVER (ORDER BY id) AS n FROM records WHERE id > 0 '
    + 'QUALIFY records.id > 1 ORDER BY n', {
    columns: [column('records'), column('n')],
    expected: [{records: 1, n: 2}, {records: 0.5, n: 3}, {records: 0.5, n: 4}],
  }),
  success('qualified-object-does-not-demand-alias',
    'WITH objects AS (SELECT 2 AS id, @a AS payload UNION ALL SELECT 1 AS id, @b AS payload '
    + 'UNION ALL SELECT 3 AS id, @c AS payload) '
    + 'SELECT 1 / (id - 1) AS objects, ROW_NUMBER() OVER (ORDER BY id) AS n FROM objects '
    + 'QUALIFY objects.id > 1 AND objects.payload.score > 5 ORDER BY n', {
    hostProfile: 'analytic-property', sourceReadCount: 0, sourceReadSessionCount: 0,
    parameterDeclarations: Object.fromEntries(['a', 'b', 'c'].map(name => [name,
      {type: 'object', nullable: true, fields: {score: number}}])),
    parameters: {a: {score: 10}, b: {score: 20}, c: null},
    columns: [column('objects'), column('n')], expected: [{objects: 1, n: 2}],
  }),
  success('typed-empty', sql, {sourceRows: [], expected: []}),
];

// GROUP retains the original key but COUNT is a different evaluated value.
// These controls use authored public names, not compiler-private slot names.
export const groupedQualifyProgram = {version: 'actql/0.1', id: 'fixture.grouped_qualify',
  stages: [structuredClone(qualifyProgram.stages[0]),
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', group: {by: ['id'], aggregates: {counted: {fn: 'count'}}}},
        {analytic: {partition_by: [], order_by: [{field: 'id', dir: 'asc', nulls: 'first'}],
          functions: {rn: {fn: 'row_number'}}}},
        {filter: {gt: [{field: 'counted'}, {literal: 1}]}},
        {sort: [{field: 'id', dir: 'asc', nulls: 'first'}]},
        {select: [{original: 'id'}, {id: 'counted'}, 'rn'], as: 'summary'}],
      results: {rows: {from: 'summary', fields: ['original', 'id', 'rn']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const nullableGroupedQualifyProgram = structuredClone(groupedQualifyProgram);
nullableGroupedQualifyProgram.id = 'fixture.nullable_grouped_qualify';
nullableGroupedQualifyProgram.stages[1].steps = [
  {from: 'records', group: {by: ['amount'], aggregates: {counted: {fn: 'count'}}}},
  {analytic: {partition_by: [], order_by: [{field: 'amount', dir: 'asc', nulls: 'first'}],
    functions: {rn: {fn: 'row_number'}}}},
  {filter: {gt: [{field: 'counted'}, {literal: 1}]}},
  {sort: [{field: 'amount', dir: 'asc', nulls: 'first'}]},
  {select: [{original: 'amount'}, {amount: 'counted'}, 'rn'], as: 'summary'},
];
nullableGroupedQualifyProgram.stages[1].results.rows.fields = ['original', 'amount', 'rn'];
export const groupedOrderWindowProgram = structuredClone(groupedQualifyProgram);
groupedOrderWindowProgram.id = 'fixture.grouped_order_window';
groupedOrderWindowProgram.stages[1].steps = [
  {from: 'records', group: {by: ['id'], aggregates: {counted: {fn: 'count'}}}},
  {analytic: {partition_by: [], order_by: [{field: 'counted', dir: 'desc', nulls: 'last'},
    {field: 'id', dir: 'asc', nulls: 'first'}], functions: {position: {fn: 'row_number'}}}},
  {sort: [{field: 'position', dir: 'asc', nulls: 'first'},
    {field: 'id', dir: 'asc', nulls: 'first'}]},
  {select: [{original: 'id'}, {id: 'counted'}], as: 'summary'},
];
groupedOrderWindowProgram.stages[1].results.rows.fields = ['original', 'id'];
// Independent GROUP -> ANALYTIC control for an ordinary aggregate in OVER.
// The shared capture still filters id > 0 once; duplicate id=3 gives count 2.
export const aggregateWindowKeyProgram = structuredClone(qualifyProgram);
aggregateWindowKeyProgram.id = 'fixture.aggregate_window_key';
aggregateWindowKeyProgram.stages[1].steps = [
  {from: 'records', group: {by: ['id'], aggregates: {counted: {fn: 'count'}}}},
  {analytic: {partition_by: [], order_by: [{field: 'counted', dir: 'desc', nulls: 'last'},
    {field: 'id', dir: 'asc', nulls: 'first'}], functions: {n: {fn: 'row_number'}}}},
  {select: ['id', 'n']},
  {sort: [{field: 'n', dir: 'asc', nulls: 'first'}], as: 'ordered'},
];
const aggregateWindowHead = 'SELECT records.id, ROW_NUMBER() OVER (ORDER BY ';
const aggregateWindowTail = ' DESC, records.id) AS n FROM records WHERE id > 0 GROUP BY records.id ORDER BY n';
const aggregateWindowExpected = [{id: 3, n: 1}, {id: 1, n: 2}, {id: 2, n: 3}];
qualifySuccesses.push(
  success('aggregate-window-key-json', JSON.stringify(aggregateWindowKeyProgram), {
    format: 'json', expected: aggregateWindowExpected,
  }),
  success('aggregate-window-key-count', aggregateWindowHead + 'COUNT(*)' + aggregateWindowTail, {
    expected: aggregateWindowExpected,
  }),
  success('aggregate-window-key-expression', aggregateWindowHead + 'COUNT(*) + 1' + aggregateWindowTail, {
    expected: aggregateWindowExpected,
  }),
  success('aggregate-window-key-nullable-count', aggregateWindowHead + 'COUNT(amount)' + aggregateWindowTail, {
    expected: [{id: 3, n: 1}, {id: 2, n: 2}, {id: 1, n: 3}],
  }),
  success('aggregate-window-key-partition', 'SELECT records.id, ROW_NUMBER() OVER '
    + '(PARTITION BY COUNT(*) ORDER BY records.id) AS n FROM records WHERE id > 0 '
    + 'GROUP BY records.id ORDER BY records.id', {
    expected: [{id: 1, n: 1}, {id: 2, n: 2}, {id: 3, n: 1}],
  }),
  success('aggregate-window-key-reuse', 'SELECT records.id, COUNT(*) AS total, ROW_NUMBER() OVER '
    + '(ORDER BY COUNT(*) DESC, records.id) AS n FROM records WHERE id > 0 '
    + 'GROUP BY records.id ORDER BY n', {
    columns: [column('id'), column('total'), column('n')],
    expected: [{id: 3, total: 2, n: 1}, {id: 1, total: 1, n: 2}, {id: 2, total: 1, n: 3}],
  }),
  success('aggregate-window-key-qualify', 'SELECT records.id FROM records WHERE id > 0 GROUP BY records.id '
    + 'QUALIFY ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC, records.id) = 1 ORDER BY records.id', {
    columns: [column('id')], expected: [{id: 3}],
  }),
  success('aggregate-window-key-query-order', 'SELECT records.id FROM records WHERE id > 0 GROUP BY records.id '
    + 'ORDER BY ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC, records.id)', {
    columns: [column('id')], expected: [{id: 3}, {id: 1}, {id: 2}],
  }),
  success('aggregate-window-key-empty', aggregateWindowHead + 'COUNT(*)' + aggregateWindowTail, {
    sourceRows: [], expected: [],
  }),
  success('aggregate-window-key-order-argument-alias', 'SELECT records.id AS original, -records.id AS id '
    + 'FROM records WHERE id > 0 GROUP BY records.id '
    + 'ORDER BY ROW_NUMBER() OVER (ORDER BY SUM(id), original)', {
    columns: [column('original'), column('id')],
    expected: [{original: 3, id: -3}, {original: 2, id: -2}, {original: 1, id: -1}],
  }),
  success('aggregate-window-key-order-argument-qualified', 'SELECT records.id AS original, -records.id AS id '
    + 'FROM records WHERE id > 0 GROUP BY records.id '
    + 'ORDER BY ROW_NUMBER() OVER (ORDER BY SUM(records.id), original)', {
    columns: [column('original'), column('id')],
    expected: [{original: 1, id: -1}, {original: 2, id: -2}, {original: 3, id: -3}],
  }),
);
const groupedHead = 'SELECT records.id AS original, COUNT(*) AS id, '
  + 'ROW_NUMBER() OVER (ORDER BY records.id) AS rn FROM records WHERE id > 0 GROUP BY records.id ';
const groupedColumns = [column('original'), column('id'), column('rn')];
const groupedExpected = [{original: 3, id: 2, rn: 3}];
const nullableGroupedHead = 'SELECT records.amount AS original, COUNT(*) AS amount, '
  + 'ROW_NUMBER() OVER (ORDER BY records.amount) AS rn FROM records WHERE id > 0 GROUP BY records.amount ';
const nullableGroupedColumns = [column('original', nullable), column('amount'), column('rn')];
const nullableGroupedExpected = [{original: 30, amount: 2, rn: 3}];
const orderHead = 'SELECT records.id AS original, COUNT(*) AS id FROM records '
  + 'WHERE id > 0 GROUP BY records.id ORDER BY ROW_NUMBER() OVER (ORDER BY ';
const orderColumns = [column('original'), column('id')];
const orderExpected = [{original: 3, id: 2}, {original: 1, id: 1}, {original: 2, id: 1}];
qualifySuccesses.push(
  success('grouped-alias-json', JSON.stringify(groupedQualifyProgram), {
    format: 'json', columns: groupedColumns, expected: groupedExpected,
  }),
  success('grouped-alias-collision', groupedHead + 'QUALIFY id > 1 ORDER BY original', {
    columns: groupedColumns, expected: groupedExpected,
  }),
  success('grouped-quoted-alias', groupedHead + 'QUALIFY `ID` > 1 ORDER BY original', {
    columns: groupedColumns, expected: groupedExpected,
  }),
  success('grouped-qualified-input', groupedHead + 'QUALIFY records.id > 1 ORDER BY original', {
    columns: groupedColumns, expected: [{original: 2, id: 1, rn: 2}, {original: 3, id: 2, rn: 3}],
  }),
  success('grouped-nullable-json', JSON.stringify(nullableGroupedQualifyProgram), {
    format: 'json', columns: nullableGroupedColumns, expected: nullableGroupedExpected,
  }),
  success('grouped-nullable-collision', nullableGroupedHead + 'QUALIFY amount > 1 ORDER BY original', {
    columns: nullableGroupedColumns, expected: nullableGroupedExpected,
  }),
  success('grouped-count-is-not-null', nullableGroupedHead + 'QUALIFY amount IS NULL ORDER BY original', {
    columns: nullableGroupedColumns, expected: [],
  }),
  success('grouped-typed-empty', groupedHead + 'QUALIFY id > 1 ORDER BY original', {
    sourceRows: [], columns: groupedColumns, expected: [],
  }),
  success('grouped-order-window-json', JSON.stringify(groupedOrderWindowProgram), {
    format: 'json', columns: orderColumns, expected: orderExpected,
  }),
  success('grouped-order-window-alias', orderHead + 'id DESC, original), original', {
    columns: orderColumns, expected: orderExpected,
  }),
  success('grouped-order-window-quoted-alias', orderHead + '`ID` DESC, original), original', {
    columns: orderColumns, expected: orderExpected,
  }),
  success('grouped-order-window-qualified-input', orderHead + 'records.id DESC), original', {
    columns: orderColumns, expected: [{original: 3, id: 2}, {original: 2, id: 1}, {original: 1, id: 1}],
  }),
);
export const qualifyRefusals = [
  'SELECT id FROM records QUALIFY id > 0',
  'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n FROM records QUALIFY missing > 0',
  'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n FROM records QUALIFY n',
  'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n FROM records QUALIFY @missing > 0',
  'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n FROM records QUALIFY SUM(n) > 0',
  'SELECT id FROM records QUALIFY `ROW_NUMBER`() = 1',
].map((text, index) => ({name: 'qualify-refuse-' + index, format: 'aql-text', text})).concat([
  {name: 'qualify-invalid-ranking-arguments', format: 'aql-text',
    text: 'SELECT id FROM records QUALIFY `ROW_NUMBER`(id) OVER (ORDER BY id) = 1',
    expectedCode: 'ClientProgramInvalidInput'},
  {name: 'qualify-unsupported-lag-default', format: 'aql-text',
    text: 'SELECT id FROM records QUALIFY `LAG`(id, 1, 2) OVER (ORDER BY id) IS NOT NULL',
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'qualify-grouped-discarded-input', format: 'sql',
    text: groupedHead + 'QUALIFY records.amount > 0', expectedCode: 'ClientProgramInvalidInput'},
  {name: 'qualify-grouped-order-discarded-input', format: 'sql',
    text: orderHead + 'records.amount), original', expectedCode: 'ClientProgramInvalidInput'},
  {name: 'qualify-aggregate-window-key-sibling', format: 'sql',
    text: 'SELECT records.id AS invented, ROW_NUMBER() OVER (ORDER BY COUNT(invented), records.id) AS n '
      + 'FROM records GROUP BY records.id', expectedCode: 'ClientProgramInvalidInput'},
  {name: 'qualify-aggregate-window-key-nested-window', format: 'sql',
    text: 'SELECT records.id, ROW_NUMBER() OVER (ORDER BY COUNT(*) OVER (ORDER BY records.id)) AS n '
      + 'FROM records GROUP BY records.id', expectedCode: 'ClientProgramInvalidInput'},
]);
export const qualifyExecutionFailures = [{name: 'qualify-demanded-error', format: 'aql-text',
  text: 'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n FROM records WHERE id > 0 '
    + 'QUALIFY 1 / (id - 1) > 0 AND n > 0 ORDER BY n',
  resultNames: ['main'], sourceReadSessionCount: 1}];
