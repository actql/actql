// Independent rows, types and a machine control. No compiler writes these.
const number = {type: 'number', nullable: false};
const payload = {type: 'object', nullable: true, fields: {score: number}};
const other = {...payload, nullable: false};
// language.md Value contracts requires this fixed checked expansion. It is
// absent from author declarations and is not inferred from a returned schema.
const otherColumn = {name: 'payload', contract: {...other, additional_properties: false}};
const columns = [{name: 'id', contract: number}];
const rows = [{id: 2, payload: {score: 10}, other: {score: 30}},
  {id: 1, payload: {score: 20}, other: {score: 5}},
  {id: 3, payload: null, other: {score: 15}}];
const parameterDeclarations = {a: payload, b: payload, c: payload,
  oa: other, ob: other, oc: other};
const parameters = {a: rows[0].payload, b: rows[1].payload, c: null,
  oa: rows[0].other, ob: rows[1].other, oc: rows[2].other};
const data = 'DATA objects = SELECT 2 AS id, @a AS payload, @oa AS other '
  + 'UNION ALL SELECT 1 AS id, @b AS payload, @ob AS other '
  + 'UNION ALL SELECT 3 AS id, @c AS payload, @oc AS other; ';
const inputOrder = [{id: 2}, {id: 1}, {id: 3}];
const aliasOrder = [{id: 1}, {id: 3}, {id: 2}];
// Explicit expectations distinguish SELECT's original input from ORDER's
// output alias. A syntactically identical path does not imply slot identity.
const receiverAliasRows = [
  {id: 1, original_score: 20, payload: {score: 5}},
  {id: 3, original_score: null, payload: {score: 15}},
  {id: 2, original_score: 10, payload: {score: 30}},
];
const receiverInputRows = [receiverAliasRows[2], receiverAliasRows[0], receiverAliasRows[1]];
const receiverColumns = [columns[0],
  {name: 'original_score', contract: {...number, nullable: true}}, otherColumn];
const textCase = (name, tail, expected = inputOrder, extra = {}) => ({
  name: 'order-property-' + name, format: 'aql-text', text: data + tail,
  parameterDeclarations, parameters, expected, columns, sourceReadCount: 0,
  ...extra,
});
const program = {version: 'actql/0.1', id: 'fixture.order_property',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload, other}, rows}, as: 'objects'},
    {from: 'objects', derive: {key: {property: {value: {field: 'payload'}, name: 'score'}}}},
    {sort: [{field: 'key', dir: 'asc', nulls: 'last'}]},
    {select: ['id'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['id']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const orderPropertySuccesses = [
  {name: 'order-property-independent-json', format: 'json',
    text: JSON.stringify(program), expected: inputOrder, columns, sourceReadCount: 0},
  textCase('non-output', 'SELECT id FROM objects ORDER BY payload.score NULLS LAST'),
  textCase('non-output-expression', 'SELECT id FROM objects ORDER BY payload.score + 1 NULLS LAST'),
  textCase('qualified-input', 'SELECT id FROM objects ORDER BY objects.payload.score NULLS LAST'),
  textCase('output-alias-collision', 'SELECT id, other AS payload FROM objects ORDER BY payload.score',
    aliasOrder.map(row => ({...row, payload: rows.find(value => value.id === row.id).other})),
    {columns: [...columns, otherColumn]}),
  textCase('qualified-collision', 'SELECT id, other AS payload FROM objects ORDER BY objects.payload.score NULLS LAST',
    inputOrder.map(row => ({...row, payload: rows.find(value => value.id === row.id).other})),
    {columns: [...columns, otherColumn]}),
  textCase('selected-property-receiver-collision',
    'SELECT id, payload.score AS original_score, other AS payload FROM objects ORDER BY payload.score NULLS LAST',
    receiverAliasRows, {columns: receiverColumns}),
  textCase('selected-property-qualified-control',
    'SELECT id, payload.score AS original_score, other AS payload FROM objects ORDER BY objects.payload.score NULLS LAST',
    receiverInputRows, {columns: receiverColumns}),
  textCase('pipe-control', 'FROM objects |> SELECT id, payload |> ORDER BY payload.score NULLS LAST |> SELECT id'),
];
export const orderPropertyRefusals = [
  'SELECT DISTINCT id FROM objects ORDER BY payload.score',
  'SELECT id FROM objects ORDER BY missing.score',
  'SELECT id FROM objects ORDER BY payload.missing',
  'SELECT id FROM objects ORDER BY id.score',
  'FROM objects AS old |> AS current |> SELECT id |> ORDER BY old.payload.score',
].map((tail, index) => ({name: 'order-property-invalid-' + index,
  format: 'aql-text', text: data + tail, parameterDeclarations, parameters}));
