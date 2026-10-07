// Independent common Program and Result obligations, never compiler output.
const number = {type: 'number', nullable: false};
const nullable = {...number, nullable: true};
const declarations = {minimum: number, take: number};
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}];
const columns = [{name: 'amount', contract: nullable},
  {name: 'key', contract: number}, {name: 'matched', contract: number}];
const expected = [{amount: 30, key: 13, matched: 13}];
export const pipeJoinInputProgram = {version: 'actql/0.1', id: 'fixture.pipe_join_input',
  params: declarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {key: {add: [{field: 'id'}, {literal: 10}]}}},
      {select: ['amount', 'key']},
      {filter: {gte: [{field: 'key'}, {$param: 'minimum'}]}},
      {sort: [{field: 'key', dir: 'asc', nulls: 'first'}]},
      {take: {count: {$param: 'take'}, offset: 0}, as: 'lefts'},
      {values: {schema: {key: number}, rows: [{key: 13}]}, as: 'rights'},
      {from: 'lefts', join: {with: 'rights', kind: 'inner',
        on: [{left: 'key', right: 'key'}], max_output_rows: 10,
        select: {amount: 'left.amount', key: 'left.key', matched: 'right.key'}}, as: 'joined'},
      {sort: [{field: 'key', dir: 'asc', nulls: 'first'},
        {field: 'amount', dir: 'asc', nulls: 'first'}], as: 'out'}],
    results: {rows: {from: 'out', fields: ['amount', 'key', 'matched']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const prefix = 'FROM records AS old |> SELECT id + 10 AS key, amount |> AS l '
  + '|> WHERE l.key >= @minimum |> ORDER BY key |> LIMIT @take ';
const join = '|> JOIN (SELECT 13 AS key) AS r ON l.key = r.key MAX_OUTPUT_ROWS 10 ';
const projection = '|> SELECT l.amount AS amount, l.key AS key, r.key AS matched '
  + '|> ORDER BY key, amount NULLS FIRST';
const source = prefix + join + projection;
const success = (name, text, extra = {}) => ({name: 'pipe-join-input-' + name,
  format: 'aql-text', text, parameterDeclarations: declarations,
  parameters: {minimum: 12, take: 2}, sourceRows, sourceReadSessionCount: 1,
  columns, expected, ...extra});
export const pipeJoinInputSuccesses = [
  success('independent-json', JSON.stringify(pipeJoinInputProgram),
    {format: 'json', parameterDeclarations: undefined}),
  success('projected-prefix', source),
  success('sql-head', source.replace('FROM records AS old |> SELECT id + 10 AS key, amount',
    'SELECT id + 10 AS key, amount FROM records AS old')),
  success('data-body', 'DATA joined = ' + source + '; FROM joined |> RESULT answer'),
  success('empty-typed', source, {sourceRows: [], expected: []}),
  success('nullable-left', prefix + join.replace('JOIN (SELECT 13', 'LEFT JOIN (SELECT 12')
    + projection, {parameters: {minimum: 11, take: 2},
    columns: [...columns.slice(0, 2), {name: 'matched', contract: nullable}],
    expected: [{amount: null, key: 11, matched: null}, {amount: 20, key: 12, matched: 12}]}),
  success('set-then-rebind', source.replace('|> AS l', '|> AS previous |> SET key = key + 1 |> AS l'),
    {expected: [{amount: 20, key: 13, matched: 13}]}),
  success('unqualified-current-row', source.replace(' |> AS l ', ' ')
    .replaceAll('l.', '').replace('SELECT 13 AS key', 'SELECT 13 AS k')
    .replaceAll('r.key', 'r.k')),
  success('where-between-fused-joins', 'FROM records AS l '
    + '|> JOIN (SELECT 3 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 10 '
    + '|> WHERE r.k > 2 |> JOIN (SELECT 3 AS k) AS s ON r.k = s.k MAX_OUTPUT_ROWS 10 '
    + '|> SELECT l.amount AS amount, l.id AS key, s.k AS matched |> ORDER BY key',
    {parameterDeclarations: undefined, parameters: undefined,
    expected: [{amount: 30, key: 3, matched: 3}, {amount: 30, key: 3, matched: 3}]}),
  success('shared-source-keeps-right-complete', 'FROM records AS old |> SELECT amount, id '
    + '|> AS l |> WHERE l.id = 3 |> CROSS JOIN records AS r MAX_OUTPUT_ROWS 10 '
    + '|> SELECT l.amount AS amount, l.id AS key, r.id AS matched |> ORDER BY key, matched',
    {parameterDeclarations: undefined, parameters: undefined, expected: [
      {amount: 30, key: 3, matched: 1}, {amount: 30, key: 3, matched: 1},
      {amount: 30, key: 3, matched: 2}, {amount: 30, key: 3, matched: 2},
      {amount: 30, key: 3, matched: 3}, {amount: 30, key: 3, matched: 3},
      {amount: 30, key: 3, matched: 3}, {amount: 30, key: 3, matched: 3}]}),
  success('aggregate-prefix', 'FROM records |> AGGREGATE COUNT(*) AS n GROUP BY id '
    + '|> AS l |> JOIN (SELECT 3 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 10 '
    + '|> SELECT l.n AS n, l.id AS id |> ORDER BY id',
    {parameterDeclarations: undefined, parameters: undefined,
    columns: ['n', 'id'].map(name => ({name, contract: number})), expected: [{n: 2, id: 3}]}),
];
export const pipeJoinInputRefusals = [
  {name: 'removed-range', expectedCode: 'ClientProgramRejected', text: source.replace('l.key = r.key', 'old.id = r.key')},
  {name: 'removed-column', expectedCode: 'ClientProgramRejected', text: source.replace('l.key = r.key', 'l.id = r.key')},
  {name: 'duplicate-range', expectedCode: 'ClientProgramRejected', text: source.replace('AS r ON l.key = r.key', 'AS l ON l.key = l.key')},
  {name: 'invalid-ceiling', text: source.replace('MAX_OUTPUT_ROWS 10', 'MAX_OUTPUT_ROWS 0')},
  {name: 'undeclared', parameterDeclarations: undefined, parameters: undefined},
  {name: 'missing', parameters: {minimum: 12}},
].map(item => ({format: 'aql-text', text: source,
  parameterDeclarations: declarations, parameters: {minimum: 12, take: 2}, ...item,
  name: 'pipe-join-input-refuse-' + item.name}));
