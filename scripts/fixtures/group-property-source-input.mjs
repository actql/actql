// Independent grouping keys, multiplicities and ordered type contracts.
// Nullable receivers and nullable fields join one NULL group; duplicates
// contribute separately to COUNT. No lowerer computes these expectations.
const number = {type: 'number', nullable: false};
const payload = {type: 'object', nullable: true,
  fields: {score: {...number, nullable: true}}};
const other = {type: 'object', nullable: false, fields: {score: number}};
const rows = [
  {id: 2, payload: {score: 10}, other: {score: 100}},
  {id: 1, payload: {score: 20}, other: {score: 200}},
  {id: 3, payload: null, other: {score: 300}},
  {id: 4, payload: {score: 20}, other: {score: 400}},
  {id: 5, payload: {score: null}, other: {score: 500}},
];
const parameterDeclarations = {a: payload, b: payload, c: payload,
  d: payload, e: payload, oa: other, ob: other, oc: other, od: other, oe: other};
const parameters = {a: {score: 10}, b: {score: 20}, c: null,
  d: {score: 20}, e: {score: null}, oa: {score: 100}, ob: {score: 200},
  oc: {score: 300}, od: {score: 400}, oe: {score: 500}};
const source = 'DATA objects = SELECT 2 AS id, @a AS payload, @oa AS other '
  + 'UNION ALL SELECT 1 AS id, @b AS payload, @ob AS other '
  + 'UNION ALL SELECT 3 AS id, @c AS payload, @oc AS other '
  + 'UNION ALL SELECT 4 AS id, @d AS payload, @od AS other '
  + 'UNION ALL SELECT 5 AS id, @e AS payload, @oe AS other; ';
const expected = [{score: null, n: 2}, {score: 10, n: 1}, {score: 20, n: 2}];
const columns = [{name: 'score', contract: {...number, nullable: true}},
  {name: 'n', contract: number}];
const json = {version: 'actql/0.1', id: 'fixture.group_property', stages: [
  {id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload, other}, rows}, as: 'objects'},
    {from: 'objects', derive: {key: {property: {name: 'score', value: {field: 'payload'}}}}},
    {group: {by: ['key'], aggregates: {n: {fn: 'count'}}}},
    {sort: [{field: 'key', dir: 'asc', nulls: 'first'}]},
    {select: [{score: 'key'}, 'n'], as: 'summary'},
  ], results: {rows: {from: 'summary', fields: ['score', 'n']}}},
], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const text = (name, tail, extra = {}) => ({
  name: 'group-property-' + name, format: 'aql-text', text: source + tail,
  parameterDeclarations, parameters, expected, columns, sourceReadCount: 0,
  ...extra,
});
export const groupPropertySuccesses = [
  {name: 'group-property-independent-json', format: 'json',
    text: JSON.stringify(json), expected, columns, sourceReadCount: 0},
  text('sql-null-and-duplicate-keys',
    'SELECT payload.score AS score, COUNT(*) AS n FROM objects GROUP BY payload.score ORDER BY score NULLS FIRST'),
  text('sql-qualified-key-reuse',
    'SELECT objects.payload.score AS score, COUNT(*) AS n FROM objects GROUP BY payload.score HAVING score IS NOT NULL ORDER BY score',
    {expected: [{score: 10, n: 1}, {score: 20, n: 2}]}),
  text('pipe-qualified-key',
    'FROM objects AS before |> AGGREGATE COUNT(*) AS n GROUP BY before.payload.score |> ORDER BY score NULLS FIRST'),
  text('pipe-set-retained-receiver',
    'FROM objects AS before |> SET payload = other |> AGGREGATE COUNT(*) AS n GROUP BY before.payload.score |> ORDER BY score NULLS FIRST'),
  text('pipe-set-current-receiver',
    'FROM objects AS before |> SET payload = other |> AGGREGATE COUNT(*) AS n GROUP BY payload.score |> ORDER BY score',
    {expected: [{score: 100, n: 1}, {score: 200, n: 1}, {score: 300, n: 1},
      {score: 400, n: 1}, {score: 500, n: 1}],
    columns: [{name: 'score', contract: number}, {name: 'n', contract: number}]}),
  text('empty-typed-groups',
    'SELECT payload.score AS score, COUNT(*) AS n FROM objects WHERE id > 99 GROUP BY score ORDER BY score',
    {expected: []}),
  text('parameter-predicate-limit',
    'SELECT `objects`.`payload`.`score` AS score, COUNT(*) AS n FROM objects WHERE id > @cut GROUP BY 1 ORDER BY score NULLS LAST LIMIT 2 OFFSET 1',
    {parameterDeclarations: {...parameterDeclarations, cut: number},
      parameters: {...parameters, cut: 1}, expected: [{score: 20, n: 1}, {score: null, n: 2}]}),
];
export const groupPropertyRefusals = [
  'SELECT payload AS value, COUNT(*) AS n FROM objects GROUP BY payload.score',
  'SELECT other.score AS score, COUNT(*) AS n FROM objects GROUP BY payload.score',
  'FROM objects AS old |> AS current |> AGGREGATE COUNT(*) AS n GROUP BY old.payload.score',
  'SELECT COUNT(*) AS n FROM objects GROUP BY payload.missing',
  'SELECT COUNT(*) AS n FROM objects GROUP BY id.score',
].map((tail, index) => ({name: 'group-property-invalid-' + index,
  format: 'aql-text', text: source + tail, parameterDeclarations, parameters}));
