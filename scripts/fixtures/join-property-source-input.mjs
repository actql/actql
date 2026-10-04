// Independent Program, values and full column contracts; no compiler oracle.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const payload = {type: 'object', nullable: true, fields: {score: number}};
const other = {...payload, nullable: false};
const leftRows = [{id: 2, payload: {score: 10}},
  {id: 1, payload: {score: 20}}, {id: 3, payload: null}];
const rightRows = [{id: 1, other: {score: 5}},
  {id: 2, other: {score: 30}}, {id: 3, other: {score: 15}},
  {id: 2, other: {score: 40}}];
const parameterDeclarations = {a: payload, b: payload, c: payload,
  oa: other, ob: other, oc: other, od: other};
const parameters = {a: {score: 10}, b: {score: 20}, c: null,
  oa: {score: 5}, ob: {score: 30}, oc: {score: 15}, od: {score: 40}};
// One explicit logical unit producer keeps this authored corpus within the
// standard 32-task admission ceiling. All seven rows and their multiplicity
// remain unchanged; no compiler output or resource limit is patched.
const data = 'DATA seed = SELECT 1 AS unit; '
  + 'DATA objects = SELECT 2 AS id, @a AS payload FROM seed '
  + 'UNION ALL SELECT 1 AS id, @b AS payload FROM seed '
  + 'UNION ALL SELECT 3 AS id, @c AS payload FROM seed; '
  + 'DATA others = SELECT 1 AS id, @oa AS other FROM seed '
  + 'UNION ALL SELECT 2 AS id, @ob AS other FROM seed '
  + 'UNION ALL SELECT 3 AS id, @oc AS other FROM seed '
  + 'UNION ALL SELECT 2 AS id, @od AS other FROM seed; ';
const join = 'FROM objects AS l JOIN others AS r ON l.id = r.id MAX_OUTPUT_ROWS 12';
const pipeJoin = 'FROM objects AS l |> JOIN others AS r ON l.id = r.id MAX_OUTPUT_ROWS 12';
const idColumn = {name: 'id', contract: number};
const scoreColumn = {name: 'score', contract: nullableNumber};
const idScoreColumns = [idColumn, scoreColumn];
const idScoreRows = [{id: 1, score: 20}, {id: 2, score: 10},
  {id: 2, score: 10}, {id: 3, score: null}];
const aliasRows = [
  {id: 1, original_score: 20, payload: {score: 5}},
  {id: 3, original_score: null, payload: {score: 15}},
  {id: 2, original_score: 10, payload: {score: 30}},
  {id: 2, original_score: 10, payload: {score: 40}},
];
const receiverColumns = [idColumn,
  {name: 'original_score', contract: nullableNumber},
  {name: 'payload', contract: {...other, additional_properties: false}}];
const textCase = (name, tail, expected = idScoreRows, extra = {}) => ({
  name: 'join-property-' + name, format: 'aql-text', text: data + tail,
  parameterDeclarations, parameters, expected, columns: idScoreColumns,
  sourceReadCount: 0, ...extra,
});
const program = {version: 'actql/0.1', id: 'fixture.join_property',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload}, rows: leftRows}, as: 'objects'},
    {values: {schema: {id: number, other}, rows: rightRows}, as: 'others'},
    {from: 'objects', join: {with: 'others', kind: 'inner',
      on: [{left: 'id', right: 'id'}], max_output_rows: 12,
      select: {id: 'left.id', payload: 'left.payload'}}, as: 'matched'},
    {from: 'matched', derive: {score: {property: {value: {field: 'payload'}, name: 'score'}}}},
    {select: ['id', 'score']}, {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['id', 'score']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const joinPropertySuccesses = [
  {name: 'join-property-independent-json', format: 'json', text: JSON.stringify(program),
    expected: idScoreRows, columns: idScoreColumns, sourceReadCount: 0},
  textCase('sql-implicit-projection', `SELECT l.id, l.payload.score ${join} ORDER BY l.id`),
  textCase('pipe-quoted-projection',
    pipeJoin + ' |> SELECT l.id, l.`payload`.`score` |> ORDER BY id'),
  textCase('where-input-snapshot',
    `SELECT l.id, r.other AS payload ${join} WHERE payload.score > 15 ORDER BY payload.score`,
    [{id: 1, payload: {score: 5}}], {columns: [idColumn, receiverColumns[2]]}),
  textCase('selected-receiver-alias',
    `SELECT l.id, payload.score AS original_score, r.other AS payload ${join} ORDER BY payload.score NULLS LAST`,
    aliasRows, {columns: receiverColumns}),
  textCase('qualified-receiver-control',
    `SELECT l.id, payload.score AS original_score, r.other AS payload ${join} ORDER BY l.payload.score NULLS LAST, r.other.score`,
    [aliasRows[2], aliasRows[3], aliasRows[0], aliasRows[1]], {columns: receiverColumns}),
  textCase('distinct-selected-expression',
    `SELECT DISTINCT l.payload.score AS a, l.payload.score AS b ${join} ORDER BY l.payload.score NULLS LAST`,
    [{a: 10, b: 10}, {a: 20, b: 20}, {a: null, b: null}],
    {columns: [{name: 'a', contract: nullableNumber}, {name: 'b', contract: nullableNumber}]}),
  textCase('left-null-extension',
    'DATA filtered = FROM others |> WHERE id <> 3 |> SELECT id, other; '
      + 'SELECT l.id, r.other.score FROM objects AS l LEFT JOIN filtered AS r '
      + 'ON l.id = r.id MAX_OUTPUT_ROWS 12 ORDER BY l.id, r.other.score',
    [{id: 1, score: 5}, {id: 2, score: 30}, {id: 2, score: 40}, {id: 3, score: null}]),
  textCase('typed-empty', `SELECT l.id, l.payload.score ${join} WHERE r.other.score < 0 ORDER BY l.id`, []),
  textCase('pre-join-pipe-filter',
    'FROM objects AS l |> WHERE l.payload.score > 15 |> JOIN others AS r '
      + 'ON l.id = r.id MAX_OUTPUT_ROWS 12 |> SELECT l.id, r.other.score',
    [{id: 1, score: 5}], {columns: [idColumn, {name: 'score', contract: number}]}),
];
export const joinPropertyRefusals = [
  `SELECT id.score ${join}`,
  `SELECT missing.score ${join}`,
  `SELECT l.payload.missing ${join}`,
  `SELECT l.id.score ${join}`,
  `SELECT DISTINCT l.id ${join} ORDER BY payload.score`,
].map((tail, index) => ({name: 'join-property-invalid-' + index,
  format: 'aql-text', text: data + tail, parameterDeclarations, parameters}));
