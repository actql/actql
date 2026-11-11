// Authored receiver meanings, duplicate counts, NULLs and common Program control.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const object = {type: 'object', nullable: true, fields: {score: nullableNumber}};
const parameterDeclarations = {a: object, b: object, c: object};
const parameters = {a: {score: 20}, b: {score: 30}, c: null};
const sourceRows = [{id: 2, amount: 10}, {id: 1, amount: 10},
  {id: 3, amount: 20}, {id: 1, amount: 10}, {id: 0, amount: 999}];
const data = 'WITH objects AS (SELECT amount AS score, '
  + 'CASE WHEN id = 1 THEN @a WHEN id = 2 THEN @b ELSE @c END AS payload '
  + 'FROM records WHERE id > 0) ';
const projections = 'payload.score AS input_score, (payload.payload).score AS object_score, COUNT(*) AS n';
const expected = [{input_score: 10, object_score: 20, n: 2},
  {input_score: 10, object_score: 30, n: 1}, {input_score: 20, object_score: null, n: 1}];
const columns = [{name: 'input_score', contract: nullableNumber},
  {name: 'object_score', contract: nullableNumber}, {name: 'n', contract: number}];
export const groupPropertyReceiverProgram = {version: 'actql/0.1',
  id: 'fixture.group_property_receiver', params: parameterDeclarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {payload: {case: {when: [
      {when: {eq: [{field: 'id'}, {literal: 1}]}, then: {$param: 'a'}},
      {when: {eq: [{field: 'id'}, {literal: 2}]}, then: {$param: 'b'}},
    ], else: {$param: 'c'}}}}},
      {select: [{score: 'amount'}, 'payload']},
      {derive: {object_score: {property: {name: 'score', value: {field: 'payload'}}}}},
      {group: {by: ['score', 'object_score'], aggregates: {n: {fn: 'count'}}}},
      {sort: [{field: 'score', dir: 'asc', nulls: 'first'},
        {field: 'object_score', dir: 'asc', nulls: 'first'}]},
      {select: [{input_score: 'score'}, 'object_score', 'n'], as: 'output'}],
    results: {rows: {from: 'output', fields: ['input_score', 'object_score', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, query, extra = {}) => ({name: 'group-property-receiver-' + name,
  format: 'aql-text', text: data + query, parameterDeclarations, parameters,
  sourceRows, sourceReadSessionCount: 1, expected, columns, ...extra});
export const groupPropertyReceiverSuccesses = [
  success('independent-json', '', {format: 'json', parameterDeclarations: undefined,
    text: JSON.stringify(groupPropertyReceiverProgram)}),
  success('inferred-both-keys', `SELECT ${projections} FROM objects AS payload GROUP BY ALL ORDER BY input_score, object_score`),
  success('explicit-both-keys', `SELECT ${projections} FROM objects AS payload GROUP BY payload.score, (payload.payload).score ORDER BY input_score, object_score`),
  success('quoted-object-receiver', 'SELECT payload.score AS input_score, ((payload.payload)).`SCORE` AS object_score, COUNT(*) AS n '
    + 'FROM objects AS payload GROUP BY ALL ORDER BY input_score, object_score'),
  success('computed-both-keys', 'SELECT payload.score + 1 AS input_score, (payload.payload).score + 1 AS object_score, COUNT(*) AS n '
    + 'FROM objects AS payload GROUP BY ALL ORDER BY input_score, object_score', {
    expected: [{input_score: 11, object_score: 21, n: 2},
      {input_score: 11, object_score: 31, n: 1}, {input_score: 21, object_score: null, n: 1}],
  }),
  success('having-grouped-object', `SELECT ${projections} FROM objects AS payload GROUP BY ALL HAVING object_score > 20 ORDER BY input_score, object_score`, {
    expected: [{input_score: 10, object_score: 30, n: 1}],
  }),
  success('empty-typed-result', `SELECT ${projections} FROM objects AS payload GROUP BY ALL ORDER BY input_score, object_score`, {sourceRows: [], expected: []}),
];
export const groupPropertyReceiverRefusals = [
  'SELECT (payload.payload).score AS object_score, COUNT(*) AS n FROM objects AS payload GROUP BY payload.score',
  'SELECT payload.score AS input_score, COUNT(*) AS n FROM objects AS payload GROUP BY (payload.payload).score',
  'SELECT (payload.payload).score + 1 AS next, COUNT(*) AS n FROM objects AS payload GROUP BY payload.score + 1',
  'SELECT COUNT(*) AS n FROM objects AS payload GROUP BY payload.score HAVING (payload.payload).score > 0',
  'SELECT COUNT(*) AS n FROM objects AS payload GROUP BY payload.score ORDER BY (payload.payload).score',
].map((query, index) => ({name: 'group-property-receiver-refuse-' + index,
  text: data + query, format: 'aql-text', parameterDeclarations, parameters,
  expectedCode: 'ClientProgramInvalidInput'}));
