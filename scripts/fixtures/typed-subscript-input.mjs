// Issue #1195's complete independent Program. Keep its authored Values input,
// Stage and Result roots; do not replace it with a lowerer-only fixture.
const literal = value => ({literal: value});
const array = (...values) => ({array: values.map(literal)});
const subscript = (value, index) => ({subscript: {value, index}});
export function typedSubscriptProgram(expression) {
  return {version: 'actql/0.1', id: 'fixture.typed_subscript', stages: [
    {id: 'main', inputs: {}, steps: [
      {as: 'seed', values: {schema: {id: {type: 'number', nullable: false}}, rows: [{id: 1}]}},
      {from: 'seed', derive: {v: expression}}, {select: ['v'], as: 'selected'},
    ], results: {rows: {from: 'selected', fields: ['v']}}},
  ], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}
const nullArray = {if: [literal(false), array(7), literal(null)]};
const success = (name, expression, value, contract = {type: 'number', nullable: true}) => ({
  name: `typed-subscript-${name}`, format: 'json',
  text: JSON.stringify(typedSubscriptProgram(expression)),
  sourceReadCount: 0, sourceReadSessionCount: 0,
  results: {answer: {rows: [{v: value}], columns: [
    {name: 'v', contract},
  ]}},
});
export const typedSubscriptSuccesses = [
  success('issue-value', subscript(array(2, 1, 2), literal(1)), 1),
  success('issue-empty', subscript({empty_array: {items: {type: 'number', nullable: false}}}, literal(0)), null),
  success('safe-out-of-range', subscript(array(7), literal(9007199254740991)), null),
  success('null-receiver', subscript(nullArray, literal(0)), null),
  success('nullable-item', subscript(array(7, null), literal(1)), null),
  // The authored literal has 3 + 2 + 4 UTF-8 bytes. Subscript retains its
  // item contract, including the finite Text bound, and makes it nullable.
  success('unicode', subscript(array('e\u0301\r\n😀'), literal(0)), 'e\u0301\r\n😀',
    {type: 'string', nullable: true, max_utf8_bytes: 9}),
];
export const typedSubscriptExecutionFailures = [
  ['negative-index', subscript(array(7), literal(-1))],
  ['null-receiver-invalid-index', subscript(nullArray, literal(0.5))],
].map(([name, expression]) => ({
  name: `typed-subscript-${name}`, format: 'json',
  text: JSON.stringify(typedSubscriptProgram(expression)),
  resultNames: ['answer'], sourceReadSessionCount: 0,
}));
export const typedSubscriptRefusals = [
  ['scalar-receiver', subscript(literal(7), literal(0))],
  ['text-index', subscript(array(7), literal('0'))],
].map(([name, expression]) => ({
  name: `typed-subscript-${name}`, format: 'json',
  text: JSON.stringify(typedSubscriptProgram(expression)),
  expectedCode: 'ClientProgramInvalidInput',
}));
