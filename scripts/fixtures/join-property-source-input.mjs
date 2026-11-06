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
const data = 'WITH seed AS (SELECT 1 AS unit) '
  + ', objects AS (SELECT 2 AS id, @a AS payload FROM seed '
  + 'UNION ALL SELECT 1 AS id, @b AS payload FROM seed '
  + 'UNION ALL SELECT 3 AS id, @c AS payload FROM seed) '
  + ', others AS (SELECT 1 AS id, @oa AS other FROM seed '
  + 'UNION ALL SELECT 2 AS id, @ob AS other FROM seed '
  + 'UNION ALL SELECT 3 AS id, @oc AS other FROM seed '
  + 'UNION ALL SELECT 2 AS id, @od AS other FROM seed) ';
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
// CTE Results select the single-JOIN connection without adding a WITH scope.
// Parenthesized/computed receivers are Property nodes, unlike dotted paths.
const ctes = 'WITH seed AS (SELECT 1 AS unit), '
  + 'objects AS (SELECT 2 AS id, @a AS payload FROM seed '
  + 'UNION ALL SELECT 1 AS id, @b AS payload FROM seed '
  + 'UNION ALL SELECT 3 AS id, @c AS payload FROM seed), '
  + 'others AS (SELECT 1 AS id, @oa AS other FROM seed '
  + 'UNION ALL SELECT 2 AS id, @ob AS other FROM seed '
  + 'UNION ALL SELECT 3 AS id, @oc AS other FROM seed '
  + 'UNION ALL SELECT 2 AS id, @od AS other FROM seed) ';
// The ordinary Relation control has no JOIN peer: declare only its actual
// producers. The unused-CTE refusal is retained separately in compiler tests.
const ordinaryCtes = 'WITH seed AS (SELECT 1 AS unit), '
  + 'objects AS (SELECT 2 AS id, @a AS payload FROM seed '
  + 'UNION ALL SELECT 1 AS id, @b AS payload FROM seed '
  + 'UNION ALL SELECT 3 AS id, @c AS payload FROM seed) ';
const propertyAliasColumns = [scoreColumn, idColumn];
const propertyAliasRows = [{score: 10, id: 2}, {score: 10, id: 2},
  {score: 20, id: 1}, {score: null, id: 3}];
export const joinImplicitPropertyProgram = {version: 'actql/0.1',
  id: 'fixture.join_implicit_property', stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload}, rows: leftRows}, as: 'objects'},
    {values: {schema: {id: number, other}, rows: rightRows}, as: 'others'},
    {from: 'objects', join: {with: 'others', kind: 'inner',
      on: [{left: 'id', right: 'id'}], max_output_rows: 12,
      select: {id: 'left.id', payload: 'left.payload'}}, as: 'matched'},
    {from: 'matched', derive: {score: {property: {value: {field: 'payload'}, name: 'score'}}}},
    {select: ['score', 'id']},
    {sort: [{field: 'score', dir: 'asc', nulls: 'last'},
      {field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['score', 'id']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const cteCase = (name, tail, extra = {}) => ({
  name: 'join-property-implicit-' + name, format: 'aql-text', text: ctes + tail,
  parameterDeclarations, parameters, expected: propertyAliasRows,
  columns: propertyAliasColumns, sourceReadCount: 0, ...extra,
});
export const joinPrefilterPropertyProgram = {version: 'actql/0.1',
  id: 'fixture.join_prefilter_property', stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload}, rows: leftRows}, as: 'objects'},
    {values: {schema: {id: number, other}, rows: rightRows}, as: 'others'},
    {from: 'objects', filter: {gt: [
      {property: {value: {field: 'payload'}, name: 'score'}}, {literal: 15}]}, as: 'filtered'},
    {from: 'filtered', join: {with: 'others', kind: 'inner',
      on: [{left: 'id', right: 'id'}], max_output_rows: 1,
      select: {id: 'left.id', other: 'right.other'}}, as: 'matched'},
    {from: 'matched', derive: {score: {property: {value: {field: 'other'}, name: 'score'}}}},
    {select: ['id', 'score']},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['id', 'score']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const prefilterColumns = [idColumn, {name: 'score', contract: number}];
const prefilterCase = (name, tail, extra = {}) => ({
  name: 'join-property-prefilter-' + name, format: 'aql-text', text: ctes + tail,
  parameterDeclarations, parameters, expected: [{id: 1, score: 5}],
  columns: prefilterColumns, sourceReadCount: 0, ...extra,
});
const collisionCtes = ctes.trimEnd()
  + ', chosen AS (SELECT id, payload, 90 AS score FROM objects) ';
// Independently authored order control: keep both receivers, derive the
// original score once, sort the input score (then the peer for duplicate IDs),
// and only afterward replace the public payload with the peer object.
export const joinRangeOrderProgram = {version: 'actql/0.1',
  id: 'fixture.join_range_order', stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload}, rows: leftRows}, as: 'objects'},
    {values: {schema: {id: number, other}, rows: rightRows}, as: 'others'},
    {from: 'objects', join: {with: 'others', kind: 'inner',
      on: [{left: 'id', right: 'id'}], max_output_rows: 12,
      select: {id: 'left.id', payload: 'left.payload', other: 'right.other'}}, as: 'matched'},
    {from: 'matched', derive: {
      original_score: {property: {value: {field: 'payload'}, name: 'score'}},
      peer_score: {property: {value: {field: 'other'}, name: 'score'}},
    }},
    {sort: [{field: 'original_score', dir: 'asc', nulls: 'last'},
      {field: 'peer_score', dir: 'asc', nulls: 'first'}]},
    {select: ['id', 'original_score', {payload: 'other'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['id', 'original_score', 'payload']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const rangeCase = (name, tail, extra = {}) => ({
  name: 'join-property-range-' + name, format: 'aql-text', text: ctes + tail,
  parameterDeclarations, parameters, expected: idScoreRows,
  columns: idScoreColumns, sourceReadCount: 0, ...extra,
});
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
    ', filtered AS (FROM others |> WHERE id <> 3 |> SELECT id, other) '
      + 'SELECT l.id, r.other.score FROM objects AS l LEFT JOIN filtered AS r '
      + 'ON l.id = r.id MAX_OUTPUT_ROWS 12 ORDER BY l.id, r.other.score',
    [{id: 1, score: 5}, {id: 2, score: 30}, {id: 2, score: 40}, {id: 3, score: null}]),
  textCase('typed-empty', `SELECT l.id, l.payload.score ${join} WHERE r.other.score < 0 ORDER BY l.id`, []),
  textCase('pre-join-pipe-filter',
    'FROM objects AS l |> WHERE l.payload.score > 15 |> JOIN others AS r '
      + 'ON l.id = r.id MAX_OUTPUT_ROWS 12 |> SELECT l.id, r.other.score',
    [{id: 1, score: 5}], {columns: [idColumn, {name: 'score', contract: number}]}),
  {name: 'join-property-implicit-independent-json', format: 'json',
    text: JSON.stringify(joinImplicitPropertyProgram), expected: propertyAliasRows,
    columns: propertyAliasColumns, sourceReadCount: 0},
  cteCase('sql', `SELECT (l.payload).score, l.id ${join} ORDER BY score NULLS LAST, id`),
  cteCase('pipe-quoted', pipeJoin
    + ' |> SELECT (l.`payload`).`score`, l.id |> ORDER BY score NULLS LAST, id'),
  cteCase('computed-receiver',
    `SELECT (IF(TRUE, l.payload, NULL)).score, l.id ${join} ORDER BY score NULLS LAST, id`),
  cteCase('empty',
    `SELECT (l.payload).score, l.id ${join} WHERE FALSE ORDER BY score NULLS LAST, id`,
    {expected: []}),
  {name: 'join-property-prefilter-independent-json', format: 'json',
    text: JSON.stringify(joinPrefilterPropertyProgram), expected: [{id: 1, score: 5}],
    columns: prefilterColumns, sourceReadCount: 0},
  prefilterCase('range',
    'FROM objects AS l |> WHERE ((l)).payload.score > 15 |> JOIN others AS r '
      + 'ON l.id = r.id MAX_OUTPUT_ROWS 12 |> SELECT l.id, r.other.score |> ORDER BY id'),
  prefilterCase('quoted-parameter-tight-ceiling',
    'FROM objects AS l |> WHERE ((`L`)).`payload`.score > @minimum |> JOIN others AS r '
      + 'ON l.id = r.id MAX_OUTPUT_ROWS 1 |> SELECT l.id, r.other.score |> ORDER BY id',
    {parameterDeclarations: {...parameterDeclarations, minimum: number},
      parameters: {...parameters, minimum: 15}}),
  prefilterCase('input-before-output-alias',
    'FROM objects AS l |> WHERE ((l)).payload.score > 15 |> JOIN others AS r '
      + 'ON l.id = r.id MAX_OUTPUT_ROWS 12 |> SELECT l.id, r.other AS payload |> ORDER BY id',
    {expected: [{id: 1, payload: {score: 5}}], columns: [idColumn, receiverColumns[2]]}),
  prefilterCase('same-named-value', '',
    {text: collisionCtes + 'FROM chosen AS payload |> WHERE (payload.payload).score > 15'
      + ' |> JOIN others AS r ON payload.id = r.id MAX_OUTPUT_ROWS 12'
      + ' |> SELECT payload.id, r.other.score |> ORDER BY id, score'}),
  prefilterCase('same-named-qualified-range', '',
    {text: collisionCtes + 'FROM chosen AS payload |> WHERE payload.score > 15'
      + ' |> JOIN others AS r ON payload.id = r.id MAX_OUTPUT_ROWS 12'
      + ' |> SELECT payload.id, r.other.score |> ORDER BY id, score',
      expected: [{id: 1, score: 5}, {id: 2, score: 30}, {id: 2, score: 40}, {id: 3, score: 15}]}),
  prefilterCase('typed-empty',
    'FROM objects AS l |> WHERE ((l)).payload.score > 100 |> JOIN others AS r '
      + 'ON l.id = r.id MAX_OUTPUT_ROWS 12 |> SELECT l.id, r.other.score |> ORDER BY id',
    {expected: []}),
  {name: 'join-property-range-independent-json', format: 'json',
    text: JSON.stringify(joinRangeOrderProgram),
    expected: [aliasRows[2], aliasRows[3], aliasRows[0], aliasRows[1]],
    columns: receiverColumns, sourceReadCount: 0},
  rangeCase('sql-select', `SELECT l.id, ((l)).payload.score ${join} ORDER BY l.id`),
  rangeCase('pipe-quoted-select', pipeJoin
    + ' |> SELECT l.id, ((`L`)).`payload`.`score` |> ORDER BY id'),
  rangeCase('where-input',
    `SELECT l.id, r.other AS payload ${join} WHERE ((l)).payload.score > 15 ORDER BY payload.score`,
    {expected: [{id: 1, payload: {score: 5}}], columns: [idColumn, receiverColumns[2]]}),
  rangeCase('order-qualified-input',
    `SELECT l.id, l.payload.score AS original_score, r.other AS payload ${join}`
      + ' ORDER BY ((l)).payload.score NULLS LAST, ((r)).other.score',
    {expected: [aliasRows[2], aliasRows[3], aliasRows[0], aliasRows[1]], columns: receiverColumns}),
  rangeCase('order-output-receiver',
    `SELECT l.id, ((l)).payload.score AS original_score, r.other AS payload ${join}`
      + ' ORDER BY (payload).score NULLS LAST',
    {expected: aliasRows, columns: receiverColumns}),
  rangeCase('value-range-collision',
    'SELECT payload.id AS id, (payload.payload).score AS score '
      + 'FROM (SELECT id, payload, 90 AS score FROM objects) AS payload '
      + 'JOIN others AS r ON payload.id = r.id MAX_OUTPUT_ROWS 12 ORDER BY id'),
  rangeCase('dotted-range-collision-control',
    'SELECT payload.id AS id, payload.score AS score '
      + 'FROM (SELECT id, payload, 90 AS score FROM objects) AS payload '
      + 'JOIN others AS r ON payload.id = r.id MAX_OUTPUT_ROWS 12 ORDER BY id',
    {expected: [{id: 1, score: 90}, {id: 2, score: 90}, {id: 2, score: 90}, {id: 3, score: 90}],
      columns: [idColumn, {name: 'score', contract: number}]}),
  rangeCase('typed-empty',
    `SELECT l.id, ((l)).payload.score ${join} WHERE ((r)).other.score < 0 ORDER BY l.id`,
    {expected: []}),
  rangeCase('left-null-extension',
    'SELECT l.id, ((r)).other.score FROM objects AS l '
      + 'LEFT JOIN (SELECT id, other FROM others WHERE id <> 3) AS r '
      + 'ON l.id = r.id MAX_OUTPUT_ROWS 12 ORDER BY l.id, ((r)).other.score',
    {expected: [{id: 1, score: 5}, {id: 2, score: 30}, {id: 2, score: 40}, {id: 3, score: null}]}),
  rangeCase('ordinary-scoped-order',
    'FROM objects |> AS `current` |> ORDER BY ((current)).payload.score NULLS LAST'
      + ' |> SELECT current.id AS id, current.payload.score AS score',
    {text: ordinaryCtes + 'FROM objects |> AS `current`'
      + ' |> ORDER BY ((current)).payload.score NULLS LAST'
      + ' |> SELECT current.id AS id, current.payload.score AS score',
      parameterDeclarations: {a: payload, b: payload, c: payload},
      parameters: {a: parameters.a, b: parameters.b, c: parameters.c},
      expected: [{id: 2, score: 10}, {id: 1, score: 20}, {id: 3, score: null}]}),
  rangeCase('current-range-order', pipeJoin
    + ' |> SELECT l.id, l.payload |> AS `current`'
    + ' |> ORDER BY ((current)).payload.score NULLS LAST, ((current)).id',
    {expected: [{id: 2, payload: {score: 10}}, {id: 2, payload: {score: 10}},
      {id: 1, payload: {score: 20}}, {id: 3, payload: null}],
      columns: [idColumn, {name: 'payload', contract: {...payload, additional_properties: false}}]}),
];
export const joinPropertyRefusals = [
  `SELECT id.score ${join}`,
  `SELECT missing.score ${join}`,
  `SELECT l.payload.missing ${join}`,
  `SELECT l.id.score ${join}`,
  `SELECT DISTINCT l.id ${join} ORDER BY payload.score`,
].map((tail, index) => ({name: 'join-property-invalid-' + index,
  format: 'aql-text', text: data + tail, parameterDeclarations, parameters,
  // DISTINCT removes the unselected payload receiver from ORDER scope.
  ...(index === 4 ? {expectedCode: 'ClientProgramInvalidInput'} : {})})).concat([
  `SELECT (l.payload).score, (l.payload).score ${join}`,
  `SELECT (missing).score ${join}`,
  `SELECT (l.payload).missing ${join}`,
  `SELECT (l.id).score ${join}`,
].map((tail, index) => ({name: 'join-property-implicit-invalid-' + index,
  format: 'aql-text', text: ctes + tail, parameterDeclarations, parameters}))).concat([
  'FROM objects AS l |> WHERE ((r)).other.score > 0 |> JOIN others AS r '
    + 'ON l.id = r.id MAX_OUTPUT_ROWS 12 |> SELECT l.id',
  'FROM objects AS l |> WHERE ((l)).id.score > 0 |> JOIN others AS r '
    + 'ON l.id = r.id MAX_OUTPUT_ROWS 12 |> SELECT l.id',
].map((tail, index) => ({name: 'join-property-prefilter-invalid-' + index,
  format: 'aql-text', text: ctes + tail, parameterDeclarations, parameters,
  expectedCode: 'ClientProgramInvalidInput'}))).concat([
  `SELECT ((l)).missing AS score ${join}`,
  `SELECT ((l)).payload.missing AS score ${join}`,
  `SELECT ((l)).id.score AS score ${join}`,
  pipeJoin + ' |> SELECT l.id, l.payload |> AS current |> ORDER BY ((l)).payload.score',
].map((tail, index) => ({name: 'join-property-range-invalid-' + index,
  format: 'aql-text', text: ctes + tail, parameterDeclarations, parameters,
  expectedCode: 'ClientProgramInvalidInput'})));
