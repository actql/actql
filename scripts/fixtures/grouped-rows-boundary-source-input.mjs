// Independent physical windows reuse the authored JSON control and rows,
// never compiler/runtime output. Wrappers do not change the frame interval.
import {analyticFrameParameterProgram, analyticFrameParameterSuccesses}
  from './analytic-frame-parameter-source-input.mjs';
const byName = name => analyticFrameParameterSuccesses.find(item => item.name === 'analytic-frame-parameter-' + name);
const base = byName('sql-distinct-widths');
const wraps = text => text.replaceAll('@before', '(+@before)').replaceAll('@after', '((@after))');
export const groupedRowsBoundarySuccesses = [
  {...base, name: 'grouped-rows-independent-json', format: 'json',
    text: JSON.stringify(analyticFrameParameterProgram), parameterDeclarations: undefined},
  ...['sql-distinct-widths', 'pipe-changed-bindings', 'following-empty-frame', 'typed-empty'].map(name => ({
    ...byName(name), name: 'grouped-rows-' + name, text: wraps(byName(name).text),
  })),
  {...byName('literal-control'), name: 'grouped-rows-literal',
    text: base.text.replaceAll('@before', '(+1)').replaceAll('@after', '++((2))'),
    parameterDeclarations: undefined, parameters: undefined},
  {...base, name: 'grouped-rows-zero-current',
    text: base.text.replaceAll('@before', '(+0)').replaceAll('@after', '((0))'),
    parameterDeclarations: undefined, parameters: undefined,
    expected: [{id: 1, first: null, last: null}, {id: 2, first: 10, last: 10},
      {id: 3, first: 20, last: 20}, {id: 4, first: 30, last: 30}, {id: 5, first: 40, last: 40}]},
];
const query = operand => 'SELECT FIRST_VALUE(amount) OVER '
  + `(ORDER BY id ROWS ${operand} PRECEDING) AS first FROM records`;
export const groupedRowsBoundaryRefusals = [
  ...['(id)', '+(@before + 1)', '+(-1)', '(+1.5)', '(9007199254740992)'].map((operand, index) => ({
    name: 'grouped-rows-refuse-operand-' + index, format: 'sql', text: query(operand),
    parameterDeclarations: {before: {type: 'number', nullable: false}}, parameters: {before: 1},
    expectedCode: 'ClientProgramInvalidInput',
  })),
  {name: 'grouped-rows-refuse-zero-parameter', format: 'sql', text: query('(+@before)'),
    parameterDeclarations: {before: {type: 'number', nullable: false}}, parameters: {before: 0},
    expectedCode: 'ClientProgramInvalidInput'},
  {name: 'grouped-rows-refuse-zero-following-short', format: 'sql',
    text: 'SELECT FIRST_VALUE(amount) OVER (ORDER BY id ROWS (+0) FOLLOWING) AS first FROM records',
    expectedCode: 'ClientProgramInvalidInput'},
];
