// Authored independently: output object scores reverse the two non-NULL
// grouping keys. Resolving the old range instead would publish the wrong order.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const object = {type: 'object', nullable: true, fields: {score: nullableNumber}};
const parameterDeclarations = {low: object, high: object, nil: object};
const parameters = {low: {score: 30}, high: {score: 5}, nil: null};
const sourceRows = [{id: 1, amount: 10}, {id: 2, amount: 20},
  {id: 1, amount: 10}, {id: 3, amount: null}, {id: 0, amount: 99}];
const data = 'WITH objects AS (SELECT amount AS score FROM records WHERE id > 0) ';
const projection = 'SELECT score AS bucket, CASE WHEN score IS NULL THEN @nil '
  + 'WHEN score = 10 THEN @low ELSE @high END AS payload, COUNT(*) AS n ';
const from = 'FROM objects AS payload GROUP BY score ORDER BY ';
const caseValue = {case: {when: [
  {when: {is_null: {field: 'score'}}, then: {$param: 'nil'}},
  {when: {eq: [{field: 'score'}, {literal: 10}]}, then: {$param: 'low'}},
], else: {$param: 'high'}}};
export const groupOrderRangeAliasProgram = {version: 'actql/0.1',
  id: 'fixture.group_order_range_alias', params: parameterDeclarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', select: [{score: 'amount'}]},
      {group: {by: ['score'], aggregates: {n: {fn: 'count'}}}},
      {derive: {evaluated: caseValue}},
      {derive: {order_score: {property: {name: 'score', value: {field: 'evaluated'}}}}},
      {sort: [{field: 'order_score', dir: 'asc', nulls: 'last'}]},
      {select: [{bucket: 'score'}, {payload: 'evaluated'}, 'n'], as: 'output'}],
    results: {rows: {from: 'output', fields: ['bucket', 'payload', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const expected = [{bucket: 20, payload: {score: 5}, n: 1},
  {bucket: 10, payload: {score: 30}, n: 2}, {bucket: null, payload: null, n: 1}];
const inputOrder = [expected[1], expected[0], expected[2]];
const columns = [{name: 'bucket', contract: nullableNumber},
  {name: 'payload', contract: {...object, additional_properties: false}},
  {name: 'n', contract: number}];
const success = (name, order, extra = {}) => ({name: 'group-order-range-alias-' + name,
  format: 'aql-text', text: data + projection + from + order,
  parameterDeclarations, parameters, sourceRows, sourceReadSessionCount: 1,
  expected, columns, ...extra});
export const groupOrderRangeAliasSuccesses = [
  success('independent-json', '', {format: 'json', parameterDeclarations: undefined,
    text: JSON.stringify(groupOrderRangeAliasProgram)}),
  success('dotted-shadow', 'payload.score NULLS LAST'),
  success('explicit-object-control', '(payload).score NULLS LAST'),
  success('quoted-shadow', '`PAYLOAD`.`score` NULLS LAST'),
  success('qualified-input-control', 'original.score NULLS LAST', {
    text: data + projection + from.replace('AS payload', 'AS original') + 'original.score NULLS LAST',
    expected: inputOrder,
  }),
  success('empty-typed', 'payload.score NULLS LAST', {sourceRows: [], expected: []}),
];
export const groupOrderRangeAliasRefusals = [
  success('missing-member', 'payload.missing NULLS LAST'),
  success('scalar-alias', 'payload.score NULLS LAST', {
    text: data + 'SELECT score AS bucket, -score AS payload, COUNT(*) AS n '
      + from + 'payload.score NULLS LAST',
  }),
  success('removed-input-range', 'old.score NULLS LAST'),
].map(({expected, columns, ...item}) => ({...item, expectedCode: 'ClientProgramInvalidInput'}));
