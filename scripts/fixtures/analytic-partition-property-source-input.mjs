// Authored from nullable key equality and input-scoped OVER, not compiler output.
const number = {type: 'number', nullable: false};
const bucket = {type: 'string', nullable: true};
const payload = {type: 'object', nullable: true, fields: {bucket}};
const other = {type: 'object', nullable: false,
  fields: {bucket: {...bucket, nullable: false}}};
const parameterDeclarations = {a: payload, b: payload, none: payload, empty: payload,
  oa: other, ob: other};
const parameters = {a: {bucket: 'A'}, b: {bucket: 'B'}, none: null,
  empty: {bucket: null}, oa: {bucket: 'A'}, ob: {bucket: 'B'}};
const sourceRows = [{id: 4, amount: 40}, {id: 1, amount: 10}, {id: 3, amount: null},
  {id: 2, amount: 20}, {id: 5, amount: 50}, {id: 0, amount: 99}];
const column = (name, contract = number) => ({name, contract});
const columns = [column('id'), column('pos')];
// A has ids 2,4; B has id 1; NULL receiver and NULL member share ids 3,5.
const expected = [{id: 1, pos: 1}, {id: 2, pos: 1}, {id: 3, pos: 1},
  {id: 4, pos: 2}, {id: 5, pos: 2}];
const currentPositions = [1, 1, 2, 2, 3];
const data = 'DATA objects = SELECT id, CASE WHEN id = 3 THEN @none '
  + 'WHEN id = 5 THEN @empty WHEN id = 1 THEN @b ELSE @a END AS payload, '
  + 'CASE WHEN id = 2 OR id = 3 THEN @oa ELSE @ob END AS other '
  + 'FROM records WHERE id > 0; ';
const payloadExpression = {case: {when: [
  {when: {eq: [{field: 'id'}, {literal: 3}]}, then: {$param: 'none'}},
  {when: {eq: [{field: 'id'}, {literal: 5}]}, then: {$param: 'empty'}},
  {when: {eq: [{field: 'id'}, {literal: 1}]}, then: {$param: 'b'}},
], else: {$param: 'a'}}};
const otherExpression = {case: {when: [{when: {or: [
  {eq: [{field: 'id'}, {literal: 2}]}, {eq: [{field: 'id'}, {literal: 3}]},
]}, then: {$param: 'oa'}}], else: {$param: 'ob'}}};
// The complete machine control uses ordinary Source/derive/analytic/SELECT.
// Its private key name and Stage layout are independent of source lowering.
export const analyticPartitionPropertyProgram = {version: 'actql/0.1',
  id: 'fixture.analytic_partition_property', params: parameterDeclarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {payload: payloadExpression, other: otherExpression}},
      {derive: {partition: {property: {value: {field: 'payload'}, name: 'bucket'}}}},
      {analytic: {partition_by: ['partition'],
        order_by: [{field: 'id', dir: 'asc', nulls: 'first'}],
        functions: {pos: {fn: 'row_number'}}}},
      {select: ['id', 'pos']},
      {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'pos']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, tail, extra = {}) => ({name: 'analytic-partition-property-' + name,
  format: 'aql-text', hostProfile: 'analytic-order', text: data + tail,
  parameterDeclarations, parameters, sourceRows, expected, columns,
  sourceReadSessionCount: 1, ...extra});
export const analyticPartitionPropertySuccesses = [
  success('independent-json', '', {format: 'json', parameterDeclarations: undefined,
    text: JSON.stringify(analyticPartitionPropertyProgram)}),
  success('sql-null-keys', 'SELECT id, ROW_NUMBER() OVER '
    + '(PARTITION BY payload.bucket ORDER BY id) AS pos FROM objects ORDER BY id'),
  success('pipe-quoted-shared-keys', 'FROM objects |> SELECT id, ROW_NUMBER() OVER '
    + '(PARTITION BY objects.payload.`bucket`, objects.payload.`bucket` '
    + 'ORDER BY objects.payload.`bucket`, id) AS pos, RANK() OVER '
    + '(PARTITION BY objects.payload.`bucket`, objects.payload.`bucket` '
    + 'ORDER BY objects.payload.`bucket`, id) AS ranking |> ORDER BY id',
  {columns: [...columns, column('ranking')], expected: expected.map(row =>
    ({...row, ranking: row.pos}))}),
  success('select-alias-collision', 'SELECT id, other AS payload, ROW_NUMBER() OVER '
    + '(PARTITION BY payload.bucket ORDER BY id) AS pos FROM objects ORDER BY id',
  {columns: [column('id'), column('payload', {...other, additional_properties: false}), column('pos')],
    expected: [{id: 1, payload: {bucket: 'B'}, pos: 1},
      {id: 2, payload: {bucket: 'A'}, pos: 1}, {id: 3, payload: {bucket: 'A'}, pos: 1},
      {id: 4, payload: {bucket: 'B'}, pos: 2}, {id: 5, payload: {bucket: 'B'}, pos: 2}]}),
  success('pipe-current-and-snapshot', 'FROM objects AS original |> SET payload = other '
    + '|> SELECT id, ROW_NUMBER() OVER (PARTITION BY original.payload.bucket ORDER BY id) AS before, '
    + 'ROW_NUMBER() OVER (PARTITION BY payload.bucket ORDER BY id) AS current |> ORDER BY id',
  {columns: [column('id'), column('before'), column('current')], expected: expected.map((row, index) =>
    ({id: row.id, before: row.pos, current: currentPositions[index]}))}),
  success('typed-empty', 'SELECT id, ROW_NUMBER() OVER '
    + '(PARTITION BY payload.bucket ORDER BY id) AS pos FROM objects ORDER BY id',
  {sourceRows: [], expected: []}),
  success('existing-direct-column', 'FROM objects |> SELECT id, payload.bucket AS bucket '
    + '|> SELECT id, ROW_NUMBER() OVER (PARTITION BY bucket ORDER BY id) AS pos |> ORDER BY id'),
];
export const analyticPartitionPropertyRefusals = [
  ['sibling-alias', 'SELECT other AS sibling, ROW_NUMBER() OVER (PARTITION BY sibling.bucket ORDER BY id) AS pos FROM objects'],
  ['removed-range', 'FROM objects AS old |> AS current |> SELECT ROW_NUMBER() OVER (PARTITION BY old.payload.bucket ORDER BY id) AS pos'],
  ['missing-member', 'SELECT ROW_NUMBER() OVER (PARTITION BY payload.missing ORDER BY id) AS pos FROM objects'],
  ['scalar-receiver', 'SELECT ROW_NUMBER() OVER (PARTITION BY id.bucket ORDER BY id) AS pos FROM objects'],
  ['object-key', 'SELECT ROW_NUMBER() OVER (PARTITION BY payload ORDER BY id) AS pos FROM objects'],
].map(([name, tail]) => ({name: 'analytic-partition-property-refuse-' + name,
  format: 'aql-text', hostProfile: 'analytic-order', text: data + tail,
  parameterDeclarations, parameters}));
