// Independent contracts and machine control for selected-member ORDER trees.
const number = {type: 'number', nullable: true};
const object = {type: 'object', nullable: true, fields: {score: number}};
const declarations = {a: object, b: object, c: object, d: object};
const parameters = {a: {score: 10}, b: {score: 20}, c: null, d: {score: null}};
const rows = [{id: 2, amount: 20}, {id: 1, amount: 10},
  {id: 4, amount: 10}, {id: 3, amount: 99}, {id: 5, amount: 88}, {id: 0, amount: 777}];
const binding = 'WITH objects AS (SELECT id, amount AS score, '
  + 'CASE WHEN id = 2 THEN @a WHEN id = 1 OR id = 4 THEN @b WHEN id = 5 THEN @d ELSE @c END AS payload, '
  + 'CASE WHEN id = 2 THEN @b ELSE @a END AS other FROM records WHERE id > 0) ';
const expected = [{score: 20}, {score: 10}, {score: null}];
const columns = [{name: 'score', contract: number}];
export const distinctOrderMemberProgram = {version: 'actql/0.1', id: 'fixture.distinct_order_member',
  params: declarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {
      payload: {case: {when: [
        {when: {eq: [{field: 'id'}, {literal: 2}]}, then: {$param: 'a'}},
        {when: {or: [{eq: [{field: 'id'}, {literal: 1}]}, {eq: [{field: 'id'}, {literal: 4}]}]}, then: {$param: 'b'}},
        {when: {eq: [{field: 'id'}, {literal: 5}]}, then: {$param: 'd'}},
      ], else: {$param: 'c'}}},
      other: {case: {when: [{when: {eq: [{field: 'id'}, {literal: 2}]}, then: {$param: 'b'}}], else: {$param: 'a'}}},
    }}, {select: ['id', {score: 'amount'}, 'payload', 'other']},
      {derive: {selected_score: {property: {name: 'score', value: {field: 'payload'}}}}},
      {select: [{score: 'selected_score'}]}, {distinct: ['score']},
      {derive: {order_only: {negate: {field: 'score'}}}},
      {sort: [{field: 'order_only', dir: 'asc', nulls: 'last'}]},
      {select: ['score'], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['score']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, query, extra = {}) => ({name: 'distinct-order-member-' + name,
  format: 'aql-text', text: binding + query, parameterDeclarations: declarations,
  parameters, sourceRows: rows, sourceReadSessionCount: 1, expected, columns, ...extra});
const aliasColumns = [{name: 'original_score', contract: number}, {name: 'payload', contract: object}];
const aliasRows = [{original_score: 10, payload: {score: 20}},
  {original_score: 20, payload: {score: 10}}, {original_score: null, payload: {score: 10}}];
export const distinctOrderMemberSuccesses = [
  success('independent-json', '', {format: 'json', parameterDeclarations: undefined, text: JSON.stringify(distinctOrderMemberProgram)}),
  success('sql-path', 'SELECT DISTINCT payload.score AS score FROM objects ORDER BY -payload.score NULLS LAST'),
  success('sql-explicit-add', 'SELECT DISTINCT (payload).score AS score FROM objects ORDER BY payload.score + 1 NULLS LAST', {
    expected: [{score: 10}, {score: 20}, {score: null}],
  }),
  success('sql-qualified', 'SELECT DISTINCT ((payload)).`SCORE` AS score FROM objects ORDER BY -objects.payload.score NULLS LAST'),
  success('pipe', 'FROM objects AS active |> SELECT DISTINCT active.payload.score AS score |> ORDER BY -(payload).score NULLS LAST'),
  success('limited', 'SELECT DISTINCT payload.score AS score FROM objects ORDER BY -(payload).score NULLS LAST LIMIT 2 OFFSET 1', {
    expected: [{score: 10}, {score: null}],
  }),
  success('empty', 'SELECT DISTINCT payload.score AS score FROM objects ORDER BY -payload.score NULLS LAST', {sourceRows: [], expected: []}),

];
// These sources and their independent target rows are retained for the common
// object-key contract owner. They are not claimed as completed public support:
// the independent object DISTINCT Program rejects NotKeyComparable(payload).
export const distinctOrderMemberOwnerProgram = {
  ...distinctOrderMemberProgram, id: 'fixture.distinct_order_object_owner',
  stages: [distinctOrderMemberProgram.stages[0], {
    ...distinctOrderMemberProgram.stages[1],
    steps: [...distinctOrderMemberProgram.stages[1].steps.slice(0, 2),
      {derive: {selected_score: {property: {name: 'score', value: {field: 'payload'}}}}},
      {select: [{original_score: 'selected_score'}, {payload: 'other'}]},
      {distinct: ['original_score', 'payload']},
      {derive: {order_only: {negate: {property: {name: 'score', value: {field: 'payload'}}}}}},
      {sort: [{field: 'order_only', dir: 'asc', nulls: 'last'},
        {field: 'original_score', dir: 'asc', nulls: 'last'}]},
      {select: ['original_score', 'payload'], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['original_score', 'payload']}},
  }],
};
export const distinctOrderMemberOwnerCases = [
  success('output-receiver', 'SELECT DISTINCT payload.score AS original_score, other AS payload FROM objects ORDER BY -payload.score NULLS LAST, original_score NULLS LAST', {
    expected: aliasRows, columns: aliasColumns,
  }),
  success('input-receiver', 'SELECT DISTINCT payload.score AS original_score, other AS payload FROM objects ORDER BY -objects.payload.score NULLS LAST, original_score NULLS LAST', {
    expected: [aliasRows[1], aliasRows[0], aliasRows[2]], columns: aliasColumns,
  }),
];
export const distinctOrderMemberRefusals = [
  'SELECT DISTINCT payload.score AS score FROM objects ORDER BY other.score + 1',
  'SELECT DISTINCT payload.score AS score FROM objects ORDER BY objects.id + 1',
  'SELECT DISTINCT (payload.payload).score AS score FROM objects AS payload ORDER BY payload.score + 1',
  'SELECT DISTINCT payload.score AS score FROM objects AS payload ORDER BY (payload.payload).score + 1',
  'SELECT DISTINCT payload.score + 1 AS score FROM objects ORDER BY payload.score + 2',
].map((query, index) => ({...success('unselected-' + index, query),
  expectedCode: 'ClientProgramInvalidInput'}));
