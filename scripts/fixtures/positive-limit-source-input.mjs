// Authored from take's positive count/nonnegative offset contract. Values and
// full schemas are independent of the compiler and installed runtime.
import {limitParameterProgram} from './limit-parameter-source-input.mjs';
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const declarations = {count: number, skip: number};
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 0, amount: 99}];
const columns = [{name: 'amount', contract: nullableNumber},
  {name: 'id', contract: number}];
const expected = [{amount: 20, id: 2}, {amount: 30, id: 3}];
const prefix = 'SELECT amount, id FROM records WHERE id > 0 ORDER BY id';
const success = (name, text, extra = {}) => ({name: 'positive-limit-' + name,
  format: 'sql', text, parameterDeclarations: declarations,
  parameters: {count: 2, skip: 1}, sourceRows, columns, expected,
  sourceReadSessionCount: 1, ...extra});
export const positiveLimitSuccesses = [
  success('independent-json', JSON.stringify(limitParameterProgram),
    {format: 'json', parameterDeclarations: undefined}),
  success('sql-parameters', prefix + ' LIMIT +@count OFFSET +(@skip)'),
  success('pipe-mixed', 'FROM records |> WHERE id > 0 |> SELECT amount, id '
    + '|> ORDER BY id |> LIMIT (+1) OFFSET ++(@skip)',
    {format: 'aql-text', parameterDeclarations: {skip: number},
      parameters: {skip: 2}, expected: [{amount: 30, id: 3}]}),
  success('literal-count', prefix + ' LIMIT +2 OFFSET (+@skip)',
    {parameterDeclarations: {skip: number}, parameters: {skip: 1}}),
  success('literal-operands', prefix + ' LIMIT +((2)) OFFSET (++1)',
    {parameterDeclarations: undefined, parameters: undefined}),
  success('zero-offset-null-and-duplicates', prefix + ' LIMIT ++(@count) OFFSET (+0)',
    {parameterDeclarations: {count: number}, parameters: {count: 4},
      expected: [{amount: null, id: 1}, ...expected, {amount: 30, id: 3}]}),
  success('typed-empty', prefix + ' LIMIT +@count OFFSET +(@skip)',
    {sourceRows: [], expected: []}),
];
export const positiveLimitRefusals = [
  ...['+id', '+(@count + 1)', '+NULL', '+0', '+2.5'].map((count, index) => ({
    name: 'operand-' + index, text: prefix + ` LIMIT ${count} OFFSET +@skip`,
    expectedCode: 'ClientProgramInvalidInput',
  })),
  {name: 'null-count-parameter', text: prefix + ' LIMIT +@count OFFSET +(@skip)',
    parameterDeclarations: {count: nullableNumber, skip: number},
    parameters: {count: null, skip: 1}},
].map(item => ({format: 'sql', parameterDeclarations: declarations,
  parameters: {count: 2, skip: 1}, ...item,
  name: 'positive-limit-refuse-' + item.name}));
