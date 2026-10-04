// Independent input, full machine control, rows and column contracts. The
// aggregate argument stays inside group/analytic; the harness never patches it.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const string = {type: 'string', nullable: false};
const payload = {type: 'object', nullable: true, fields: {score: nullableNumber}};
const other = {type: 'object', nullable: false, fields: {score: number}};
const rows = [
  {id: 2, bucket: 'A', payload: {score: 10}, other: {score: 100}},
  {id: 1, bucket: 'A', payload: {score: 20}, other: {score: 200}},
  {id: 3, bucket: 'A', payload: null, other: {score: 300}},
  {id: 5, bucket: 'A', payload: {score: 20}, other: {score: 400}},
  {id: 6, bucket: 'A', payload: {score: 30}, other: {score: 500}},
  {id: 4, bucket: 'B', payload: {score: null}, other: {score: 600}},
];
const parameterDeclarations = {a: payload, b: payload, c: payload,
  d: payload, e: payload, f: payload, oa: other, ob: other, oc: other,
  od: other, oe: other, of: other};
const parameters = {a: {score: 10}, b: {score: 20}, c: null,
  d: {score: 20}, e: {score: 30}, f: {score: null},
  oa: {score: 100}, ob: {score: 200}, oc: {score: 300},
  od: {score: 400}, oe: {score: 500}, of: {score: 600}};
const data = 'DATA objects = SELECT 2 AS id, \'A\' AS bucket, @a AS payload, @oa AS other '
  + 'UNION ALL SELECT 1 AS id, \'A\' AS bucket, @b AS payload, @ob AS other '
  + 'UNION ALL SELECT 3 AS id, \'A\' AS bucket, @c AS payload, @oc AS other '
  + 'UNION ALL SELECT 5 AS id, \'A\' AS bucket, @d AS payload, @od AS other '
  + 'UNION ALL SELECT 6 AS id, \'A\' AS bucket, @e AS payload, @oe AS other '
  + 'UNION ALL SELECT 4 AS id, \'B\' AS bucket, @f AS payload, @of AS other; ';
const column = (name, contract = number) => ({name, contract});
const names = ['bucket', 'n', 'd', 'h', 's', 'a', 'lo', 'hi'];
const columns = [column('bucket', string), ...['n', 'd', 'h'].map(name => column(name)),
  ...['s', 'a', 'lo', 'hi'].map(name => column(name, nullableNumber))];
const expected = [
  {bucket: 'A', n: 4, d: 3, h: 3, s: 80, a: 20, lo: 10, hi: 30},
  {bucket: 'B', n: 0, d: 0, h: 0, s: null, a: null, lo: null, hi: null},
];
const property = {property: {name: 'score', value: {field: 'payload'}}};
const program = {version: 'actql/0.1', id: 'fixture.aggregate_property',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, bucket: string, payload, other}, rows}, as: 'objects'},
    {from: 'objects', group: {by: ['bucket'], aggregates: {
      n: {fn: 'count', expr: property}, d: {fn: 'count', expr: property, distinct: true},
      h: {fn: 'count_if', expr: {gte: [property, {literal: 20}]}},
      s: {fn: 'sum', expr: property}, a: {fn: 'avg', expr: property},
      lo: {fn: 'min', expr: property}, hi: {fn: 'max', expr: property},
    }}},
    {select: names},
    {sort: [{field: 'bucket', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: names}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const aggregates = 'COUNT(payload.score) AS n, COUNT(DISTINCT payload.score) AS d, '
  + 'COUNTIF(payload.score >= 20) AS h, SUM(payload.score) AS s, AVG(payload.score) AS a, '
  + 'MIN(payload.score) AS lo, MAX(payload.score) AS hi';
// A common-owner reproduction uses these authored bindings and source. The
// separately saved generated Program is diagnostic material, never an oracle.
export const aggregatePropertyDataReproduction = {
  text: data + 'SELECT bucket, ' + aggregates
    + ' FROM objects GROUP BY bucket ORDER BY bucket',
  parameterDeclarations, parameters, expected, columns,
};
const success = (name, tail, overrides = {}) => ({
  name: 'aggregate-property-' + name, format: 'aql-text', text: data + tail,
  parameterDeclarations, parameters, expected, columns, sourceReadCount: 0, ...overrides,
});
export const aggregatePropertySuccesses = [
  {name: 'aggregate-property-independent-json', format: 'json',
    text: JSON.stringify(program), expected, columns, sourceReadCount: 0},
  success('sql', 'SELECT bucket, ' + aggregates + ' FROM objects GROUP BY bucket ORDER BY bucket'),
  success('pipe', 'FROM objects |> AGGREGATE ' + aggregates + ' GROUP BY bucket '
    + '|> SELECT bucket, n, d, h, s, a, lo, hi |> ORDER BY bucket'),
  success('qualified-computed',
    'SELECT bucket, COUNT(`objects`.`payload`.`score` + 1) AS n, '
    + 'SUM(objects.payload.score + 1) AS s FROM objects GROUP BY bucket ORDER BY bucket', {
      expected: [{bucket: 'A', n: 4, s: 84}, {bucket: 'B', n: 0, s: null}],
      columns: [columns[0], column('n'), column('s', nullableNumber)],
    }),
  success('pipe-receiver-snapshot', 'FROM objects AS before |> SET payload = other '
    + '|> AGGREGATE COUNT(payload.score) AS current_count, COUNT(before.payload.score) AS original_count', {
      expected: [{current_count: 6, original_count: 4}],
      columns: ['current_count', 'original_count'].map(name => column(name)),
    }),
  success('empty-global', 'SELECT COUNT(payload.score) AS n, SUM(payload.score) AS s, '
    + 'AVG(payload.score) AS a, MIN(payload.score) AS lo FROM objects WHERE FALSE', {
      expected: [{n: 0, s: null, a: null, lo: null}],
      columns: [column('n'), ...['s', 'a', 'lo'].map(name => column(name, nullableNumber))],
    }),
  success('select-sibling-alias', 'SELECT COUNT(payload.score) AS payload, COUNT(other.score) AS other FROM objects', {
    expected: [{payload: 4, other: 6}], columns: ['payload', 'other'].map(name => column(name)),
  }),
  success('over-common-argument', 'SELECT id, COUNT(payload.score) OVER '
    + '(ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running '
    + 'FROM objects ORDER BY id', {
      expected: [{id: 1, running: 1}, {id: 2, running: 2}, {id: 3, running: 2},
        {id: 4, running: 2}, {id: 5, running: 3}, {id: 6, running: 4}],
      columns: ['id', 'running'].map(name => column(name)),
    }),
];
export const aggregatePropertyRefusals = [
  'SELECT COUNT(payload.missing) AS n FROM objects',
  'SELECT COUNT(id.score) AS n FROM objects',
  'SELECT COUNTIF(payload.score) AS n FROM objects',
  'FROM objects AS old |> AS current |> AGGREGATE COUNT(old.payload.score) AS n',
].map((tail, index) => ({name: 'aggregate-property-invalid-' + index,
  format: 'aql-text', text: data + tail, parameterDeclarations, parameters}));
