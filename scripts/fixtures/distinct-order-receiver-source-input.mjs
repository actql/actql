// DISTINCT keeps only evaluated numeric outputs. A property on the numeric
// output alias must be rejected, never replaced by the old range's column.
const nullableNumber = {type: 'number', nullable: true};
const sourceRows = [{id: 1, amount: 10}, {id: 2, amount: 20},
  {id: 1, amount: 10}, {id: 3, amount: null}, {id: 0, amount: 99}];
const data = 'DATA objects = SELECT amount AS score FROM records WHERE id > 0; ';
const select = 'SELECT DISTINCT score AS original_score, -score AS payload ';
const from = 'FROM objects AS payload ORDER BY ';
const expected = [{original_score: 10, payload: -10},
  {original_score: 20, payload: -20}, {original_score: null, payload: null}];
const columns = ['original_score', 'payload'].map(name => ({name, contract: nullableNumber}));
export const distinctOrderReceiverProgram = {version: 'actql/0.1',
  id: 'fixture.distinct_order_receiver',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {negative: {negate: {field: 'amount'}}}},
      {select: [{original_score: 'amount'}, {payload: 'negative'}]},
      {distinct: ['original_score', 'payload']},
      {derive: {order_only: {add: [{field: 'original_score'}, {literal: 1}]}}},
      {sort: [{field: 'order_only', dir: 'asc', nulls: 'last'}]},
      {select: ['original_score', 'payload'], as: 'output'}],
    results: {rows: {from: 'output', fields: ['original_score', 'payload']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const distinctOrderReceiverInvalidProgram = {
  ...distinctOrderReceiverProgram, id: 'fixture.distinct_order_receiver_invalid',
  stages: [distinctOrderReceiverProgram.stages[0], {
    ...distinctOrderReceiverProgram.stages[1],
    steps: [...distinctOrderReceiverProgram.stages[1].steps.slice(0, 3),
      {derive: {order_only: {add: [
        {property: {name: 'score', value: {field: 'payload'}}}, {literal: 1},
      ]}}}, ...distinctOrderReceiverProgram.stages[1].steps.slice(4)],
  }],
};
const success = (name, query, extra = {}) => ({name: 'distinct-order-receiver-' + name,
  format: 'aql-text', text: data + query, sourceRows,
  sourceReadSessionCount: 1, expected, columns, ...extra});
export const distinctOrderReceiverSuccesses = [
  success('independent-json', '', {format: 'json', text: JSON.stringify(distinctOrderReceiverProgram)}),
  success('unshadowed-input', select + 'FROM objects AS original ORDER BY original.score + 1 NULLS LAST'),
  success('range-without-output-shadow',
    select.replace('AS payload', 'AS negative') + from + 'payload.score + 1 NULLS LAST', {
      expected: expected.map(({original_score, payload}) => ({original_score, negative: payload})),
      columns: ['original_score', 'negative'].map(name => ({name, contract: nullableNumber})),
    }),
  success('numeric-output', select + from + 'payload NULLS LAST', {
    expected: [expected[1], expected[0], expected[2]],
  }),
  success('empty-typed', select + 'FROM objects AS original ORDER BY original.score + 1 NULLS LAST', {
    sourceRows: [], expected: [],
  }),
];
export const distinctOrderReceiverRefusals = [
  success('independent-json-type-refusal', '', {
    format: 'json', text: JSON.stringify(distinctOrderReceiverInvalidProgram),
  }),
  success('dotted-shadow', select + from + 'payload.score + 1 NULLS LAST'),
  success('explicit-object-control', select + from + '(payload).score + 1 NULLS LAST'),
  success('quoted-shadow', select + from + '`PAYLOAD`.`score` + 1 NULLS LAST'),
  success('signed-shadow', select + from + '-payload.score NULLS LAST'),
].map(({expected, columns, ...item}) => ({...item, expectedCode: 'ClientProgramInvalidInput'}));
