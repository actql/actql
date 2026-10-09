// Independent ordinary JOIN/append controls. One shared Source is captured;
// duplicate rows multiply at JOIN and remain duplicated by UNION ALL.
const number = {type: 'number', nullable: false};
const columns = [{name: 'id', contract: number},
  {name: 'amount', contract: {...number, nullable: true}}];
const sourceRows = [{id: 3, amount: null}, {id: 1, amount: 10},
  {id: 2, amount: 20}, {id: 2, amount: 20}];
const expected = [{id: 1, amount: 10}, {id: 2, amount: 20},
  {id: 2, amount: 20}, {id: 2, amount: 20}, {id: 2, amount: 20},
  {id: 3, amount: null}];
const left = 'SELECT l.id AS id, r.amount AS amount FROM records AS l JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 WHERE l.id = 1';
const right = 'SELECT l.id AS id, r.amount AS amount FROM records AS l JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 WHERE l.id >= 2';
const order = ' ORDER BY amount NULLS LAST, id';
const sql = left + ' UNION ALL ' + right + order;
export const setJoinProgram = {version: 'actql/0.1', id: 'fixture.set_join',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', filter: {eq: [{field: 'id'}, {literal: 1}]}},
      {join: {with: 'records', kind: 'inner', on: [{left: 'id', right: 'id'}],
        max_output_rows: 10, select: {id: 'left.id', amount: 'right.amount'}}, as: 'left'},
      {from: 'records', filter: {gte: [{field: 'id'}, {literal: 2}]}},
      {join: {with: 'records', kind: 'inner', on: [{left: 'id', right: 'id'}],
        max_output_rows: 10, select: {id: 'left.id', amount: 'right.amount'}}, as: 'right'},
      {from: 'left', append: {with: 'right'}},
      {sort: [{field: 'amount', dir: 'asc', nulls: 'last'}, {field: 'id', dir: 'asc', nulls: 'first'}]},
      {select: ['id', 'amount'], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'amount']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, extra = {}) => ({name: 'set-join-' + name,
  format: 'sql', text, sourceRows, expected, columns, sourceReadSessionCount: 1, ...extra});
export const setJoinSuccesses = [
  success('independent-json', JSON.stringify(setJoinProgram), {format: 'json'}),
  success('sql-both-operands', sql),
  success('sql-right-operand', 'SELECT id, amount FROM records WHERE id = 1 UNION ALL ' + right + order),
  success('sql-corresponding', left + ' UNION ALL CORRESPONDING '
    + 'SELECT r.amount AS amount, l.id AS id FROM records AS l JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 WHERE l.id >= 2' + order),
  success('cte-set-body', 'WITH combined AS (' + left + ' UNION ALL ' + right + ') SELECT id, amount FROM combined' + order),
  success('typed-empty', sql, {sourceRows: [], expected: []}),
  success('parameter-limit', sql + ' LIMIT @count OFFSET @offset', {
    parameterDeclarations: {count: number, offset: number}, parameters: {count: 2, offset: 1},
    expected: [{id: 2, amount: 20}, {id: 2, amount: 20}]}),
  success('distinct', left + ' UNION DISTINCT ' + right + order, {
    expected: [{id: 1, amount: 10}, {id: 2, amount: 20}, {id: 3, amount: null}]}),
];
export const setJoinRefusals = [
  {name: 'operand-range-after-set', text: left + ' UNION ALL ' + right + ' ORDER BY r.amount'},
  {name: 'right-alias-after-set', text: left + ' UNION ALL ' + right.replace('AS amount', 'AS right_amount') + ' ORDER BY right_amount'},
  {name: 'undeclared-final-limit', text: sql + ' LIMIT @missing'},
  {name: 'unsupported-join-key', expectedCode: 'ClientProgramImplementationLimit',
    text: left.replace('l.id = r.id', 'l.id > r.id') + ' UNION ALL ' + right + order},
].map(item => ({format: 'sql', expectedCode: 'ClientProgramInvalidInput', ...item, name: 'set-join-refuse-' + item.name}));
