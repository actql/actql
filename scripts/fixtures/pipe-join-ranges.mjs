// Independent common IR and public obligations for immutable Pipe ranges.
const number = {type: 'number', nullable: false};
const nullable = {...number, nullable: true};
const sourceRows = [{id: 2, amount: 20}, {id: 1, amount: null}, {id: 2, amount: 20}];
const columns = [{name: 'current', contract: number}, {name: 'original', contract: number},
  {name: 'amount', contract: nullable}, {name: 'matched', contract: number}];
const expected = [{current: 12, original: 2, amount: 20, matched: 2},
  {current: 12, original: 2, amount: 20, matched: 2}];
export const pipeJoinRangesProgram = {version: 'actql/0.1', id: 'fixture.pipe_join_ranges',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}}, {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {replacement: {add: [{field: 'id'}, {literal: 10}]}}, as: 'lefts'},
      {values: {schema: {k: number}, rows: [{k: 2}]}, as: 'rights'},
      {from: 'lefts', join: {with: 'rights', kind: 'inner', on: [{left: 'id', right: 'k'}],
        max_output_rows: 10, select: {current: 'left.replacement', original: 'left.id',
          amount: 'left.amount', matched: 'right.k'}}, as: 'joined'},
      {sort: [{field: 'original', dir: 'asc', nulls: 'first'}], as: 'out'}],
    results: {rows: {from: 'out', fields: ['current', 'original', 'amount', 'matched']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const prefix = 'FROM records |> AS l |> SET id = id + 10 ';
const join = '|> JOIN (SELECT 2 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 10 ';
const projection = '|> SELECT id AS current, l.id AS original, amount, r.k AS matched |> ORDER BY original';
const source = prefix + join + projection;
const success = (name, text, extra = {}) => ({name: 'pipe-join-ranges-' + name,
  format: 'aql-text', text, sourceRows, sourceReadSessionCount: 1, columns, expected, ...extra});
export const pipeJoinRangesSuccesses = [
  success('independent-json', JSON.stringify(pipeJoinRangesProgram), {format: 'json'}),
  success('set-original-key', source),
  success('drop-original-key', 'FROM records |> AS l |> DROP id ' + join
    + projection.replace('id AS current', 'amount AS current'),
  {columns: [{name: 'current', contract: nullable}, ...columns.slice(1)],
    expected: [{current: 20, original: 2, amount: 20, matched: 2},
      {current: 20, original: 2, amount: 20, matched: 2}]}),
  success('rename-original-key', 'FROM records |> AS l |> RENAME id AS current ' + join
    + projection.replace('id AS current', 'current'),
  {expected: [{current: 2, original: 2, amount: 20, matched: 2},
    {current: 2, original: 2, amount: 20, matched: 2}]}),
  success('quoted-range', source.replaceAll('AS l', 'AS `L`').replaceAll('l.id', '`L`.id')),
  success('empty-typed', source, {sourceRows: [], expected: []}),
  success('nullable-left', prefix + join.replace('|> JOIN', '|> LEFT JOIN') + projection,
  {columns: [...columns.slice(0, 3), {name: 'matched', contract: nullable}],
    expected: [{current: 11, original: 1, amount: null, matched: null}, ...expected]}),
  success('multiple-ranges', 'FROM records AS l '
    + '|> JOIN (SELECT 2 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 10 '
    + '|> SET id = id + 10 |> JOIN (SELECT 2 AS k) AS s ON r.k = s.k MAX_OUTPUT_ROWS 10 '
    + projection),
  success('shared-source', 'FROM records |> AS l |> SET id = id + 10 '
    + '|> WHERE l.id = 2 |> CROSS JOIN (SELECT id AS k FROM records) AS r MAX_OUTPUT_ROWS 10 '
    + '|> SELECT id AS current, l.id AS original, l.amount AS amount, r.k AS matched '
    + '|> ORDER BY matched', {expected: [
    {current: 12, original: 2, amount: 20, matched: 1}, {current: 12, original: 2, amount: 20, matched: 1},
    {current: 12, original: 2, amount: 20, matched: 2}, {current: 12, original: 2, amount: 20, matched: 2},
    {current: 12, original: 2, amount: 20, matched: 2}, {current: 12, original: 2, amount: 20, matched: 2}]}),
];
export const pipeJoinRangesRefusals = [
  {name: 'dropped-current', text: 'FROM records |> AS l |> DROP id ' + join.replace('l.id', 'id') + projection},
  {name: 'renamed-current', text: 'FROM records |> AS l |> RENAME id AS current ' + join.replace('l.id', 'id') + projection},
  {name: 'displaced-range', text: source.replace('SET id = id + 10', 'SET id = id + 10 |> AS fresh')},
  {name: 'authored-cte-range', text: 'WITH chosen AS (FROM records |> AS l |> SET id = id + 10) FROM chosen ' + join + projection},
].map(item => ({format: 'aql-text', expectedCode: 'ClientProgramRejected', ...item,
  name: 'pipe-join-ranges-refuse-' + item.name}));
