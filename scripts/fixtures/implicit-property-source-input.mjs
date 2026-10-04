// Authored expectations: public leaf names and common nullable property values.
// Neither the Frontend nor observed Result rows generate this fixture.
const number = {type: 'number', nullable: false};
const risk = {type: 'string', nullable: true, max_utf8_bytes: 4};
const payload = {type: 'object', nullable: true, fields: {
  score: number, inner: {type: 'object', nullable: true, fields: {risk}},
}};
const other = {type: 'object', nullable: false, fields: {score: number}};
const rows = [
  {id: 2, payload: {score: 20, inner: {risk: 'high'}}, other: {score: 5}},
  {id: 1, payload: null, other: {score: 30}},
  {id: 3, payload: {score: 10, inner: null}, other: {score: 15}},
  {id: 4, payload: {score: 10, inner: {risk: null}}, other: {score: 40}},
];
const parameterDeclarations = {p2: payload, p1: payload, p3: payload, p4: payload,
  o2: other, o1: other, o3: other, o4: other};
const parameters = {p2: rows[0].payload, p1: null, p3: rows[2].payload, p4: rows[3].payload,
  o2: rows[0].other, o1: rows[1].other, o3: rows[2].other, o4: rows[3].other};
const data = 'DATA objects = SELECT 2 AS id, @p2 AS payload, @o2 AS other '
  + 'UNION ALL SELECT 1 AS id, @p1 AS payload, @o1 AS other '
  + 'UNION ALL SELECT 3 AS id, @p3 AS payload, @o3 AS other '
  + 'UNION ALL SELECT 4 AS id, @p4 AS payload, @o4 AS other; ';
const columns = [{name: 'score', contract: {...number, nullable: true}},
  {name: 'id', contract: number}];
const expected = [{score: 10, id: 3}, {score: 10, id: 4},
  {score: 20, id: 2}, {score: null, id: 1}];
const textCase = (name, tail, extra = {}) => ({
  name: 'implicit-property-' + name, format: 'aql-text', text: data + tail,
  parameterDeclarations, parameters, expected, columns, sourceReadCount: 0, ...extra,
});
// A complete independent machine control uses the existing property expression.
const program = {version: 'actql/0.1', id: 'fixture.implicit_property', stages: [{
  id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload, other}, rows}, as: 'objects'},
    {from: 'objects', derive: {selected_score: {
      property: {value: {field: 'payload'}, name: 'score'},
    }}},
    {select: [{score: 'selected_score'}, 'id']},
    {sort: [{field: 'score', dir: 'asc', nulls: 'last'},
      {field: 'id', dir: 'asc', nulls: 'first'}], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['score', 'id']}},
}], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const implicitPropertySuccesses = [
  {name: 'implicit-property-independent-json', format: 'json',
    text: JSON.stringify(program), expected, columns, sourceReadCount: 0},
  textCase('sql', 'SELECT payload.score, id FROM objects ORDER BY score NULLS LAST, id'),
  textCase('pipe', 'FROM objects |> SELECT payload.score, id |> ORDER BY score NULLS LAST, id'),
  textCase('qualified-quoted', 'SELECT `objects`.`payload`.`score`, id FROM objects ORDER BY score NULLS LAST, id'),
  textCase('nested-nullable', 'SELECT payload.inner.risk, id FROM objects ORDER BY id', {
    expected: [{risk: null, id: 1}, {risk: 'high', id: 2}, {risk: null, id: 3}, {risk: null, id: 4}],
    columns: [{name: 'risk', contract: risk}, {name: 'id', contract: number}],
  }),
  textCase('typed-empty', 'SELECT payload.score, id FROM objects WHERE FALSE ORDER BY score NULLS LAST, id', {
    expected: [],
  }),
  textCase('select-input-snapshot', 'SELECT payload.score, other AS payload, id FROM objects ORDER BY score NULLS LAST, id', {
    expected: [{score: 10, payload: {score: 15}, id: 3},
      {score: 10, payload: {score: 40}, id: 4}, {score: 20, payload: {score: 5}, id: 2},
      {score: null, payload: {score: 30}, id: 1}],
    columns: [columns[0], {name: 'payload', contract: {...other, additional_properties: false}}, columns[1]],
  }),
  textCase('current-and-snapshot', 'FROM objects AS before |> SET payload = other '
    + '|> SELECT before.payload.score AS original, payload.score, id |> ORDER BY id', {
    expected: [{original: null, score: 30, id: 1}, {original: 20, score: 5, id: 2},
      {original: 10, score: 15, id: 3}, {original: 10, score: 40, id: 4}],
    columns: [{name: 'original', contract: {...number, nullable: true}},
      {name: 'score', contract: number}, columns[1]],
  }),
  textCase('authored-identifier', 'SELECT `ID`, payload.score FROM objects ORDER BY `ID`', {
    expected: [{ID: 1, score: null}, {ID: 2, score: 20}, {ID: 3, score: 10}, {ID: 4, score: 10}],
    columns: [{name: 'ID', contract: number}, columns[0]],
  }),
];
export const implicitPropertyRefusals = [
  'SELECT missing.score FROM objects',
  'SELECT payload.missing FROM objects',
  'SELECT id.score FROM objects',
  'SELECT payload.score, other.score FROM objects',
  'FROM objects AS old |> AS current |> SELECT old.payload.score',
].map((tail, index) => ({name: 'implicit-property-invalid-' + index,
  format: 'aql-text', text: data + tail, parameterDeclarations, parameters}));
