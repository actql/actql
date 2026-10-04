// Independent rows, full column contracts and a handwritten machine control.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const payload = {type: 'object', nullable: true, fields: {score: number}};
const other = {...payload, nullable: false};
const rows = [{id: 2, payload: {score: 10}, other: {score: 30}},
  {id: 1, payload: {score: 20}, other: {score: 5}},
  {id: 3, payload: null, other: {score: 15}}];
const parameterDeclarations = {a: payload, b: payload, c: payload,
  oa: other, ob: other, oc: other};
const parameters = {a: {score: 10}, b: {score: 20}, c: null,
  oa: {score: 30}, ob: {score: 5}, oc: {score: 15}};
const data = 'DATA objects = SELECT 2 AS id, @a AS payload, @oa AS other '
  + 'UNION ALL SELECT 1 AS id, @b AS payload, @ob AS other '
  + 'UNION ALL SELECT 3 AS id, @c AS payload, @oc AS other; ';
const id = {name: 'id', contract: number};
const previous = {name: 'previous', contract: nullableNumber};
const previousRows = [{id: 1, previous: null}, {id: 2, previous: 20}, {id: 3, previous: 10}];
const textCase = (name, tail, expected = previousRows, extra = {}) => ({
  name: 'analytic-property-' + name, format: 'aql-text', text: data + tail,
  parameterDeclarations, parameters, expected, columns: [id, previous],
  sourceReadCount: 0, ...extra,
});
const frame = 'ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW';
const program = {version: 'actql/0.1', id: 'fixture.analytic_property',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload, other}, rows}, as: 'objects'},
    {from: 'objects', analytic: {partition_by: [],
      order_by: [{field: 'id', dir: 'asc', nulls: 'first'}],
      functions: {previous: {fn: 'lag', expr: {property: {name: 'score', value: {field: 'payload'}}}}}}},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}]},
    {select: ['id', 'previous'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['id', 'previous']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const analyticPropertySuccesses = [
  {name: 'analytic-property-independent-json', format: 'json', text: JSON.stringify(program),
    expected: previousRows, columns: [id, previous], sourceReadCount: 0},
  textCase('sql-lag', 'SELECT id, LAG(payload.score) OVER (ORDER BY id) AS previous FROM objects ORDER BY id'),
  textCase('pipe-quoted-lead',
    'FROM objects AS t |> SELECT id, LEAD(t.`payload`.`score`) OVER (ORDER BY id) AS next |> ORDER BY id',
    [{id: 1, next: 10}, {id: 2, next: null}, {id: 3, next: null}],
    {columns: [id, {name: 'next', contract: nullableNumber}]}),
  textCase('frame-values',
    `SELECT id, FIRST_VALUE(payload.score) OVER (${frame}) AS first, LAST_VALUE(payload.score) OVER (${frame}) AS last FROM objects ORDER BY id`,
    [{id: 1, first: 20, last: 20}, {id: 2, first: 20, last: 10}, {id: 3, first: 20, last: null}],
    {columns: [id, {name: 'first', contract: nullableNumber}, {name: 'last', contract: nullableNumber}]}),
  textCase('select-input-snapshot',
    'SELECT id, other AS payload, LAG(payload.score) OVER (ORDER BY id) AS previous FROM objects ORDER BY id',
    [{id: 1, payload: {score: 5}, previous: null},
      {id: 2, payload: {score: 30}, previous: 20}, {id: 3, payload: {score: 15}, previous: 10}],
    {columns: [id, {name: 'payload', contract: {...other, additional_properties: false}}, previous]}),
  textCase('pipe-set-snapshot',
    'FROM objects AS original |> SET payload = other |> SELECT id, LAG(original.payload.score) OVER (ORDER BY id) AS previous, LEAD(payload.score, 0) OVER (ORDER BY id) AS current |> ORDER BY id',
    [{id: 1, previous: null, current: 5}, {id: 2, previous: 20, current: 30}, {id: 3, previous: 10, current: 15}],
    {columns: [id, previous, {name: 'current', contract: nullableNumber}]}),
  textCase('computed-argument',
    'SELECT id, LAG(payload.score + 1) OVER (ORDER BY id) AS previous FROM objects ORDER BY id',
    [{id: 1, previous: null}, {id: 2, previous: 21}, {id: 3, previous: 11}]),
  textCase('parameter-offset-zero',
    'SELECT id, LAG(payload.score, @n) OVER (ORDER BY id) AS previous FROM objects ORDER BY id',
    [{id: 1, previous: 20}, {id: 2, previous: 10}, {id: 3, previous: null}],
    {parameterDeclarations: {...parameterDeclarations, n: number}, parameters: {...parameters, n: 0}}),
  textCase('nullable-leaf',
    'SELECT id, LAG(payload.score) OVER (ORDER BY id) AS previous FROM objects ORDER BY id',
    [{id: 1, previous: null}, {id: 2, previous: null}, {id: 3, previous: 10}],
    {parameterDeclarations: {...parameterDeclarations,
      a: {...payload, fields: {score: nullableNumber}}, b: {...payload, fields: {score: nullableNumber}},
      c: {...payload, fields: {score: nullableNumber}}},
    parameters: {...parameters, b: {score: null}}}),
  textCase('typed-empty',
    'SELECT id, LAG(payload.score) OVER (ORDER BY id) AS previous FROM objects WHERE id < 0 ORDER BY id', []),
];
export const analyticPropertyRefusals = [
  'SELECT LAG(missing.score) OVER (ORDER BY id) AS previous FROM objects',
  'SELECT LAG(payload.missing) OVER (ORDER BY id) AS previous FROM objects',
  'SELECT LAG(id.score) OVER (ORDER BY id) AS previous FROM objects',
  'FROM objects AS old |> AS current |> SELECT LAG(old.payload.score) OVER (ORDER BY id) AS previous',
  'SELECT other AS invented, LAG(invented.score) OVER (ORDER BY id) AS previous FROM objects',
  'SELECT FIRST_VALUE(payload.score) OVER (ORDER BY id) AS value FROM objects',
  'SELECT LAG(payload.score, -1) OVER (ORDER BY id) AS previous FROM objects',
].map((tail, index) => ({name: 'analytic-property-invalid-' + index,
  format: 'aql-text', text: data + tail, parameterDeclarations, parameters}));
