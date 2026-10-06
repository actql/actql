// Hand-authored take operands, rows and complete column contracts. Neither
// Program expectations nor Result expectations come from compiler output.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const declarations = {count: number, skip: number};
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 0, amount: 99}];
const columns = [{name: 'amount', contract: nullableNumber},
  {name: 'id', contract: number}];
const expected = [{amount: 20, id: 2}, {amount: 30, id: 3}];
const sql = 'SELECT amount, id FROM records WHERE id > 0 ORDER BY id LIMIT @count OFFSET @skip';
export const limitParameterProgram = {version: 'actql/0.1',
  id: 'fixture.limit_parameter', params: declarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', select: ['amount', 'id']},
      {sort: [{field: 'id', dir: 'asc', nulls: 'first'}]},
      {take: {count: {$param: 'count'}, offset: {$param: 'skip'}}, as: 'out'}],
    results: {rows: {from: 'out', fields: ['amount', 'id']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, extra = {}) => ({name: 'limit-parameter-' + name,
  format: 'sql', text, parameterDeclarations: declarations,
  parameters: {count: 2, skip: 1}, sourceRows, sourceReadSessionCount: 1,
  columns, expected, ...extra});
export const limitParameterSuccesses = [
  success('independent-json', JSON.stringify(limitParameterProgram),
    {format: 'json', parameterDeclarations: undefined}),
  success('sql', sql),
  success('pipe-different-bindings', 'FROM records |> WHERE id > 0 |> SELECT amount, id |> ORDER BY id |> LIMIT @count OFFSET @skip',
    {format: 'aql-text', parameters: {count: 1, skip: 2}, expected: [{amount: 30, id: 3}]}),
  success('zero-offset-null-and-duplicates', sql, {parameters: {count: 4, skip: 0},
    expected: [{amount: null, id: 1}, ...expected, {amount: 30, id: 3}]}),
  success('literal-count', sql.replace('@count', '2'),
    {parameterDeclarations: {skip: number}, parameters: {skip: 1}}),
  success('omitted-offset', sql.replace(' OFFSET @skip', ''),
    {parameterDeclarations: {count: number}, parameters: {count: 1}, expected: [{amount: null, id: 1}]}),
  success('offset-past-end', sql, {parameters: {count: 1, skip: 8}, expected: []}),
  success('typed-empty', sql, {sourceRows: [], expected: []}),
  success('cte-body', 'WITH chosen AS (SELECT amount, id FROM records WHERE id > 0 ORDER BY id LIMIT @count OFFSET @skip) SELECT amount, id FROM chosen ORDER BY id'),
  success('set-final', 'DATA selected = SELECT amount, id FROM records WHERE id > 0; '
    + 'SELECT amount, id FROM selected UNION ALL SELECT amount, id FROM selected ORDER BY id LIMIT @count OFFSET @skip',
    {format: 'aql-text', expected: [{amount: null, id: 1}, {amount: 20, id: 2}]}),
  success('join-final', 'DATA selected = SELECT amount, id FROM records WHERE id > 0; '
    + 'DATA keys = SELECT 1 AS id UNION ALL SELECT 2 AS id UNION ALL SELECT 3 AS id; '
    + 'SELECT l.amount AS amount, l.id AS id FROM selected AS l JOIN keys AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 ORDER BY id LIMIT @count OFFSET @skip',
    {format: 'aql-text'}),
];
export const limitParameterRefusals = [
  {name: 'undeclared', parameterDeclarations: undefined, parameters: undefined},
  {name: 'missing', parameters: {skip: 1}},
  ...[0, -1, 1.5, null, 9007199254740992, 'private-value'].map((count, index) => ({
    name: 'invalid-count-' + index,
    parameterDeclarations: {count: count === null ? nullableNumber : number, skip: number},
    parameters: {count, skip: 1}})),
  {name: 'negative-offset', parameters: {count: 1, skip: -1}},
  {name: 'nullable-offset', parameterDeclarations: {count: number, skip: nullableNumber},
    parameters: {count: 1, skip: null}},
  {name: 'row-operand', text: sql.replace('@count', 'id')},
].map(item => ({format: 'sql', text: sql,
  parameterDeclarations: declarations, parameters: {count: 2, skip: 1}, ...item,
  name: 'limit-parameter-refuse-' + item.name}));
