// Independent input multiplicity, inferred keys, values and ordered contracts.
// The JSON control uses ordinary group/derive; no compiler generates expectations.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const columns = names => names.map(name => ({name, contract: number}));
const sourceRows = [{id: 3, amount: 20}, {id: 1, amount: null},
  {id: 2, amount: 10}, {id: 3, amount: 20}, {id: 4, amount: 0},
  {id: 1, amount: null}, {id: 0, amount: 999}];
const groupedRows = [{id: 1, n: 2}, {id: 2, n: 1}, {id: 3, n: 2}, {id: 4, n: 1}];
export const groupByAllProgram = {version: 'actql/0.1', id: 'fixture.group_by_all',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', group: {by: ['id'], aggregates: {n: {fn: 'count'}}}},
      {sort: [{field: 'id', dir: 'asc', nulls: 'first'}]},
      {select: ['id', 'n'], as: 'output'}],
    results: {rows: {from: 'output', fields: ['id', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, names, extra = {}) => ({
  name: 'group-by-all-' + name, format: 'sql', text, sourceRows, expected,
  columns: columns(names), sourceReadSessionCount: 1, ...extra,
});
export const groupByAllSuccesses = [
  success('independent-json', JSON.stringify(groupByAllProgram), groupedRows, ['id', 'n'], {format: 'json'}),
  success('input-key', 'SELECT id, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY ALL ORDER BY id',
    groupedRows, ['id', 'n']),
  success('shorter-path-selected-later', 'SELECT id + 1 AS bucket, id, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY ALL ORDER BY id',
    [{bucket: 2, id: 1, n: 2}, {bucket: 3, id: 2, n: 1}, {bucket: 4, id: 3, n: 2}, {bucket: 5, id: 4, n: 1}], ['bucket', 'id', 'n']),
  success('input-output-alias-collision', 'SELECT -id AS id, records.id AS original, COUNT(*) AS n FROM records WHERE records.id > 0 GROUP BY ALL ORDER BY id',
    [{id: -4, original: 4, n: 1}, {id: -3, original: 3, n: 2}, {id: -2, original: 2, n: 1}, {id: -1, original: 1, n: 2}], ['id', 'original', 'n']),
  success('aggregate-alias-collision', 'SELECT COUNT(*) AS id, records.id AS original FROM records WHERE records.id > 0 GROUP BY ALL HAVING id > 1 ORDER BY original',
    [{id: 2, original: 1}, {id: 2, original: 3}], ['id', 'original']),
  success('nullable-key', 'SELECT amount, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY ALL ORDER BY amount',
    [{amount: null, n: 2}, {amount: 0, n: 1}, {amount: 10, n: 1}, {amount: 20, n: 2}], ['amount', 'n'],
    {columns: [{name: 'amount', contract: nullableNumber}, ...columns(['n'])]}),
  success('embedded-aggregate-parameter-limit', 'SELECT id, COUNT(*) + id AS n, @marker AS marker FROM records WHERE id > @minimum GROUP BY ALL ORDER BY id DESC LIMIT @take',
    [{id: 4, n: 5, marker: 9}, {id: 3, n: 5, marker: 9}], ['id', 'n', 'marker'],
    {parameterDeclarations: {marker: number, minimum: number, take: number}, parameters: {marker: 9, minimum: 0, take: 2}}),
  success('array-covered-by-input-key', 'SELECT [id, records.id + 1] AS coordinates, id FROM records WHERE id > 0 GROUP BY ALL ORDER BY id',
    [{coordinates: [1, 2], id: 1}, {coordinates: [2, 3], id: 2}, {coordinates: [3, 4], id: 3}, {coordinates: [4, 5], id: 4}], ['coordinates', 'id'],
    {columns: [{name: 'coordinates', contract: {type: 'array', nullable: false, max_items: 2, items: number}}, ...columns(['id'])]}),
  success('nullable-property-prefix', 'DATA objects = SELECT @a AS payload UNION ALL SELECT @b AS payload UNION ALL SELECT @a AS payload; '
    + 'SELECT (objects.payload).score AS score, payload.score + 1 AS next, COUNT(*) AS n FROM objects GROUP BY ALL ORDER BY score',
    [{score: null, next: null, n: 1}, {score: 10, next: 11, n: 2}], ['score', 'next', 'n'],
    {format: 'aql-text', parameterDeclarations: {a: {type: 'object', nullable: true, fields: {score: nullableNumber}}, b: {type: 'object', nullable: true, fields: {score: nullableNumber}}},
      parameters: {a: {score: 10}, b: null}, sourceReadCount: 0, sourceReadSessionCount: 0,
      columns: [{name: 'score', contract: nullableNumber}, {name: 'next', contract: nullableNumber}, ...columns(['n'])]}),
  success('star-except', 'SELECT * EXCEPT (amount), COUNT(*) AS n FROM records WHERE id > 0 GROUP BY ALL ORDER BY id',
    groupedRows, ['id', 'n']),
  success('window-excluded', 'SELECT id, ROW_NUMBER() OVER (ORDER BY id) + 1 AS rank FROM records WHERE id > 0 GROUP BY ALL ORDER BY id',
    [{id: 1, rank: 2}, {id: 2, rank: 3}, {id: 3, rank: 4}, {id: 4, rank: 5}], ['id', 'rank']),
  success('inline-order-window', 'SELECT id, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY ALL ORDER BY ROW_NUMBER() OVER (ORDER BY n DESC, id)',
    [{id: 1, n: 2}, {id: 3, n: 2}, {id: 2, n: 1}, {id: 4, n: 1}], ['id', 'n']),
  success('cte-pipe-tail', 'WITH summary AS (SELECT id, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY ALL) SELECT id, n FROM summary |> WHERE n > 1 |> ORDER BY id',
    [{id: 1, n: 2}, {id: 3, n: 2}], ['id', 'n'], {format: 'aql-text'}),
  success('empty-keys-empty-input', 'SELECT COUNT(*) AS n, 1 AS marker FROM records WHERE FALSE GROUP BY ALL',
    [{n: 0, marker: 1}], ['n', 'marker']),
  success('no-aggregate-empty-input', 'SELECT 1 AS marker FROM records WHERE FALSE GROUP BY ALL',
    [{marker: 1}], ['marker']),
  success('typed-empty-groups', 'SELECT id, COUNT(*) AS n FROM records WHERE FALSE GROUP BY ALL ORDER BY id',
    [], ['id', 'n']),
];
export const groupByAllRefusals = [
  'SELECT missing FROM records GROUP BY ALL',
  'SELECT COUNT(*) AS n, n + 1 AS next FROM records GROUP BY ALL',
  'SELECT records.id FROM records AS current GROUP BY ALL',
  'SELECT id, COUNT(*) AS n FROM records GROUP BY ALL ORDER BY amount',
  'SELECT id, @missing AS marker FROM records GROUP BY ALL',
  'SELECT id FROM records GROUP BY ALL, id',
].map((text, index) => ({name: 'group-by-all-refuse-' + index, format: 'sql', text,
  expectedCode: 'ClientProgramInvalidInput'}));
