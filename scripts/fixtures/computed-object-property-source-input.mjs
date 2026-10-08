// Authored from the common typed-access contract. The compiler and returned
// Results do not generate these Programs, rows or column contracts.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const nested = {type: 'object', nullable: true, fields: {score: nullableNumber}};
const payload = {type: 'object', nullable: true, fields: {score: nullableNumber, nested}};
const other = {...payload, nullable: false};
const column = (name, contract = number) => ({name, contract});
const sourceRows = [{id: 2, amount: 10}, {id: 1, amount: 20},
  {id: 3, amount: null}, {id: 4, amount: 40}, {id: 2, amount: 10},
  {id: 0, amount: 99}];
const parameterDeclarations = {p1: payload, p2: payload, p3: payload, p4: payload,
  o1: other, o2: other, o3: other, o4: other};
const parameters = {p1: {score: 20, nested: {score: 11}},
  p2: {score: 10, nested: null}, p3: null, p4: {score: null, nested: {score: null}},
  o1: {score: 5, nested: null}, o2: {score: 30, nested: {score: 22}},
  o3: {score: 15, nested: {score: 33}}, o4: {score: 25, nested: null}};
const suppliedParameters = names => ({
  parameterDeclarations: Object.fromEntries(names.map(name => [name, parameterDeclarations[name]])),
  parameters: Object.fromEntries(names.map(name => [name, parameters[name]])),
});
const data = 'DATA objects = SELECT id, '
  + 'CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, '
  + 'CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other '
  + 'FROM records WHERE id > 0; ';
const expected = [{id: 1, score: 20}, {id: 2, score: 10}, {id: 2, score: 10},
  {id: 3, score: 15}, {id: 4, score: null}];
const columns = [column('id'), column('score', nullableNumber)];
const parameterCase = prefix => ({case: {when: [
  {when: {eq: [{field: 'id'}, {literal: 1}]}, then: {$param: prefix + '1'}},
  {when: {eq: [{field: 'id'}, {literal: 2}]}, then: {$param: prefix + '2'}},
  {when: {eq: [{field: 'id'}, {literal: 3}]}, then: {$param: prefix + '3'}},
], else: {$param: prefix + '4'}}});
export const computedObjectPropertyProgram = {version: 'actql/0.1',
  id: 'fixture.computed_object_property', params: parameterDeclarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {payload: parameterCase('p'), other: parameterCase('o')}},
      {select: ['id', 'payload', 'other']},
      {derive: {score: {property: {name: 'score',
        value: {coalesce: [{field: 'payload'}, {field: 'other'}]}}}}},
      {select: ['id', 'score']},
      {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'score']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, tail, extra = {}) => ({name: 'computed-object-property-' + name,
  format: 'aql-text', text: data + tail, parameterDeclarations, parameters,
  sourceRows, sourceReadSessionCount: 1, expected, columns, ...extra});
// A NULL member of a non-NULL payload does not select the fallback object.
const collisionRows = [
  {id: 1, original_score: 20, payload: parameters.o1},
  {id: 3, original_score: 15, payload: parameters.o3},
  {id: 4, original_score: null, payload: parameters.o4},
  {id: 2, original_score: 10, payload: parameters.o2},
  {id: 2, original_score: 10, payload: parameters.o2},
];
const collisionColumns = [column('id'), column('original_score', nullableNumber),
  column('payload', {...other, additional_properties: false,
    fields: {...other.fields, nested: {...nested, additional_properties: false}}})];
export const computedObjectPropertySuccesses = [
  success('independent-json', JSON.stringify(computedObjectPropertyProgram),
    {format: 'json', text: JSON.stringify(computedObjectPropertyProgram), parameterDeclarations: undefined}),
  success('sql-coalesce', 'SELECT id, COALESCE(payload, other).score AS score FROM objects ORDER BY id'),
  success('pipe-case-and-parameter', 'FROM objects |> SELECT id, '
    + '(CASE WHEN payload IS NULL THEN other ELSE payload END).`score`, '
    + '(@p1).nested.score AS nested_score |> ORDER BY id', {
    expected: [{id: 1, score: 20, nested_score: 11}, {id: 2, score: 10, nested_score: 11},
      {id: 2, score: 10, nested_score: 11}, {id: 3, score: 15, nested_score: 11},
      {id: 4, score: null, nested_score: 11}],
    columns: [...columns, column('nested_score', nullableNumber)],
  }),
  success('order-receiver-alias', 'SELECT id, COALESCE(payload, other).score AS original_score, '
    + 'other AS payload FROM objects ORDER BY COALESCE(payload, other).score NULLS LAST, id',
  {expected: collisionRows, columns: collisionColumns}),
  success('member-case-order-alias', 'SELECT id, COALESCE(payload, other).SCORE AS original_score, '
    + 'other AS payload FROM objects ORDER BY COALESCE(payload, other).SCORE NULLS LAST, id',
  {expected: collisionRows, columns: collisionColumns}),
  success('order-qualified-control', 'SELECT id, COALESCE(payload, other).score AS original_score, '
    + 'other AS payload FROM objects ORDER BY COALESCE(objects.payload, objects.other).score NULLS LAST, id',
  {expected: [collisionRows[3], collisionRows[4], collisionRows[1], collisionRows[0], collisionRows[2]],
    columns: collisionColumns}),
  success('member-case-qualified-reuse', 'SELECT id, COALESCE(payload, other).SCORE AS original_score, '
    + 'other AS payload FROM objects ORDER BY COALESCE(`objects`.`payload`, `objects`.`other`).`score` NULLS LAST, id',
  {expected: [collisionRows[3], collisionRows[4], collisionRows[1], collisionRows[0], collisionRows[2]],
    columns: collisionColumns}),
  success('current-and-snapshot', 'FROM objects AS before |> SET payload = other '
    + '|> SELECT id, COALESCE(before.payload, before.other).score AS original_score, '
    + 'COALESCE(payload, other).score AS score |> ORDER BY id', {
    expected: [{id: 1, original_score: 20, score: 5}, {id: 2, original_score: 10, score: 30},
      {id: 2, original_score: 10, score: 30}, {id: 3, original_score: 15, score: 15},
      {id: 4, original_score: null, score: 25}],
    columns: [column('id'), column('original_score', nullableNumber), columns[1]],
  }),
  success('join-receiver-inputs', 'SELECT l.id AS id, COALESCE(l.payload, r.other).score AS score '
    + 'FROM objects AS l JOIN objects AS r ON l.id = r.id ORDER BY id', {
    expected: [{id: 1, score: 20}, {id: 2, score: 10}, {id: 2, score: 10},
      {id: 2, score: 10}, {id: 2, score: 10}, {id: 3, score: 15}, {id: 4, score: null}],
  }),
  success('empty-typed', 'SELECT id, COALESCE(payload, other).score AS score FROM objects ORDER BY id',
    {sourceRows: [], expected: []}),
  success('lazy-case-receiver', '', {...suppliedParameters(['o1', 'p1', 'p2']),
    text: 'SELECT id, (CASE WHEN id > 0 THEN @o1 '
    + 'ELSE (CASE WHEN id / (id - id) = 0 THEN @p1 ELSE @p2 END) END).score AS score '
    + 'FROM records WHERE id > 0 ORDER BY id',
  expected: [{id: 1, score: 5}, {id: 2, score: 5}, {id: 2, score: 5},
    {id: 3, score: 5}, {id: 4, score: 5}]}),
];
export const computedObjectPropertyRefusals = [
  'SELECT COALESCE(payload, other).missing AS value FROM objects',
  'SELECT COALESCE(id, id).score AS value FROM objects',
  'FROM objects AS old |> AS current |> SELECT COALESCE(old.payload, other).score AS value',
  'SELECT other AS renamed, COALESCE(renamed, payload).score AS value FROM objects',
  'SELECT COALESCE(payload, other).score, (payload).score FROM objects',
].map((tail, index) => ({name: 'computed-object-property-refuse-' + index,
  format: 'aql-text', text: data + tail, parameterDeclarations, parameters}));
export const computedObjectPropertyExecutionFailures = [{
  name: 'computed-object-property-demanded-receiver-failure', format: 'sql',
  text: 'SELECT id, (CASE WHEN id / (id - id) = 0 THEN @p1 ELSE @p2 END).score AS score FROM records',
  ...suppliedParameters(['p1', 'p2']), resultNames: ['answer'], sourceReadSessionCount: 1,
}];

// Independent original-source column control; parentheses do not create a row
// evaluator or change predicate, nullable arithmetic, duplicate rows or order.
export const parenthesizedSourceRangeProgram = {version: 'actql/0.1',
  id: 'fixture.parenthesized_source_range', stages: [{id: 'capture',
    inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['id', 'amount'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['id', 'amount']}}},
  {id: 'main', inputs: {source: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'source', derive: {value: {add: [{field: 'amount'}, {literal: 0}]}}},
      {sort: [{field: 'value', dir: 'asc', nulls: 'last'}, {field: 'id', dir: 'asc', nulls: 'first'}]},
      {select: ['id', 'value'], as: 'selected'}],
    results: {rows: {from: 'selected', fields: ['id', 'value']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const rangeExpected = [{id: 2, value: 10}, {id: 2, value: 10},
  {id: 1, value: 20}, {id: 4, value: 40}, {id: 3, value: null}];
const rangeColumns = [column('id'), column('value', nullableNumber)];
const sourceRangeSql = 'SELECT id, ((r)).amount + 0 AS value FROM records r '
  + 'WHERE ((r)).id > 0 ORDER BY value NULLS LAST, id';
const rangeSuccess = (name, text, extra = {}) => ({name: 'parenthesized-source-range-' + name,
  format: 'sql', text, sourceRows, sourceReadSessionCount: 1,
  expected: rangeExpected, columns: rangeColumns, ...extra});
export const parenthesizedSourceRangeSuccesses = [
  rangeSuccess('json-control', JSON.stringify(parenthesizedSourceRangeProgram), {format: 'json'}),
  rangeSuccess('sql', sourceRangeSql),
  rangeSuccess('pipe', 'FROM records r |> WHERE ((r)).id > 0 '
    + '|> SELECT id, ((r)).amount + 0 AS value |> ORDER BY value NULLS LAST, id', {format: 'aql-text'}),
  rangeSuccess('quoted', sourceRangeSql.replaceAll('((r))', '((`R`))').replace('records r', 'records `r`')),
  rangeSuccess('empty', sourceRangeSql, {sourceRows: [], expected: []}),
  success('parenthesized-range-nested', 'SELECT id, ((o)).payload.score AS score FROM objects o ORDER BY id',
    {expected: [{id: 1, score: 20}, {id: 2, score: 10}, {id: 2, score: 10}, {id: 3, score: null}, {id: 4, score: null}]}),
  success('parenthesized-value-range-collision', 'SELECT id, (payload).score AS score FROM objects payload ORDER BY id',
    {expected: [{id: 1, score: 20}, {id: 2, score: 10}, {id: 2, score: 10}, {id: 3, score: null}, {id: 4, score: null}]}),
];
export const parenthesizedSourceRangeRefusals = [
  'SELECT ((r)).missing AS value FROM records r',
  'SELECT ((r)).id.score AS value FROM records r',
  'FROM records old |> AS current |> SELECT ((old)).id AS value',
].map((text, index) => ({name: 'parenthesized-source-range-refusal-' + index,
  format: 'aql-text', text, expectedCode: 'ClientProgramInvalidInput'}));
computedObjectPropertySuccesses.push(...parenthesizedSourceRangeSuccesses);
computedObjectPropertyRefusals.push(...parenthesizedSourceRangeRefusals);
