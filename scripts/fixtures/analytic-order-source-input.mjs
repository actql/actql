// Expectations follow input-scoped OVER ordering, independently of lowering.
// The id=0 row distinguishes retained WHERE from an unconditional capture.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const column = (name, contract = number) => ({name, contract});
const sourceRows = [{id: 3, amount: 20}, {id: 1, amount: 10},
  {id: 2, amount: null}, {id: 4, amount: 20}, {id: 0, amount: 99}];
const columns = [column('id'), column('amount', nullableNumber), column('pos')];
// ORDER -amount NULLS LAST, id gives ids 3,4,1,2; final ORDER id is separate.
const expected = [{id: 1, amount: 10, pos: 3}, {id: 2, amount: null, pos: 4},
  {id: 3, amount: 20, pos: 1}, {id: 4, amount: 20, pos: 2}];
const sql = 'SELECT id, amount, ROW_NUMBER() OVER '
  + '(ORDER BY -amount NULLS LAST, id) AS pos FROM records WHERE id > 0 ORDER BY id';
const pipe = 'FROM records |> WHERE id > 0 |> SELECT id, amount, ROW_NUMBER() OVER '
  + '(ORDER BY (-amount) NULLS LAST, (id)) AS pos |> ORDER BY id';
// A complete machine Program uses ordinary derive/analytic/select/sort. It
// shares no lowering helper, hidden field names or generated expected values.
const program = {version: 'actql/0.1', id: 'fixture.analytic_order_expression',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {key: {negate: {field: 'amount'}}}},
      {analytic: {partition_by: [], order_by: [
        {field: 'key', dir: 'asc', nulls: 'last'},
        {field: 'id', dir: 'asc', nulls: 'first'}],
      functions: {pos: {fn: 'row_number'}}}},
      {select: ['id', 'amount', 'pos']},
      {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'amount', 'pos']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, extra = {}) => ({name: 'analytic-order-' + name,
  format: 'sql', text, sourceRows, expected, columns, sourceReadSessionCount: 1,
  ...extra});
const ascending = [{id: 1, amount: -10, pos: 1}, {id: 2, amount: null, pos: 4},
  {id: 3, amount: -20, pos: 2}, {id: 4, amount: -20, pos: 3}];
const object = {type: 'object', nullable: true, fields: {score: number}};
const nonNullObject = {...object, nullable: false};
const objectText = 'DATA objects = SELECT 2 AS id, @a AS payload, @oa AS other '
  + 'UNION ALL SELECT 1 AS id, @b AS payload, @ob AS other '
  + 'UNION ALL SELECT 3 AS id, @c AS payload, @oc AS other; ';
const objectInput = {
  parameterDeclarations: {a: object, b: object, c: object,
    oa: nonNullObject, ob: nonNullObject, oc: nonNullObject},
  parameters: {a: {score: 10}, b: {score: 20}, c: null,
    oa: {score: 30}, ob: {score: 5}, oc: {score: 15}},
};
export const analyticOrderSuccesses = [
  success('independent-json', JSON.stringify(program), {format: 'json'}),
  success('sql-null-ties', sql),
  success('pipe-parentheses', pipe, {format: 'aql-text'}),
  success('select-alias-collision', 'SELECT id, -amount AS amount, ROW_NUMBER() '
    + 'OVER (ORDER BY amount + 1 NULLS LAST, id) AS pos FROM records '
    + 'WHERE id > 0 ORDER BY id', {expected: ascending}),
  success('constant-not-ordinal', 'SELECT id, amount, DENSE_RANK() OVER '
    + '(ORDER BY 1) AS pos FROM records WHERE id > 0 ORDER BY id',
  {expected: [{id: 1, amount: 10, pos: 1}, {id: 2, amount: null, pos: 1},
    {id: 3, amount: 20, pos: 1}, {id: 4, amount: 20, pos: 1}]}),
  success('pipe-snapshot', 'FROM records AS before |> WHERE id > 0 '
    + '|> SET amount = -amount |> SELECT id, before.amount AS original, amount, '
    + 'ROW_NUMBER() OVER (ORDER BY before.amount + 1 NULLS LAST, id) AS pos |> ORDER BY id',
  {format: 'aql-text', columns: [column('id'), column('original', nullableNumber),
    column('amount', nullableNumber), column('pos')], expected: [
    {id: 1, original: 10, amount: -10, pos: 1},
    {id: 2, original: null, amount: null, pos: 4},
    {id: 3, original: 20, amount: -20, pos: 2},
    {id: 4, original: 20, amount: -20, pos: 3}]}),
  success('shared-order-evaluation', 'SELECT id, ROW_NUMBER() OVER '
    + '(ORDER BY amount + 1 NULLS LAST, id) AS pos, RANK() OVER '
    + '(ORDER BY amount + 1 DESC NULLS LAST) AS ranking FROM records WHERE id > 0 ORDER BY id',
  {columns: [column('id'), column('pos'), column('ranking')], expected: [
    {id: 1, pos: 1, ranking: 3}, {id: 2, pos: 4, ranking: 4},
    {id: 3, pos: 2, ranking: 1}, {id: 4, pos: 3, ranking: 1}]}),
  success('empty-typed', sql, {sourceRows: [], expected: []}),
  success('typed-parameter', 'SELECT id, amount, ROW_NUMBER() OVER '
    + '(ORDER BY -amount + @offset NULLS LAST, id) AS pos '
    + 'FROM records WHERE id > 0 ORDER BY id',
  {parameterDeclarations: {offset: number}, parameters: {offset: 1}}),
  success('nullable-property-input', objectText + 'SELECT id, payload.score AS original_score, '
    + 'other AS payload, ROW_NUMBER() OVER (ORDER BY payload.score + 1 NULLS LAST, id) AS pos '
    + 'FROM objects ORDER BY id',
  {format: 'aql-text', ...objectInput, sourceReadSessionCount: undefined, sourceReadCount: 0,
    columns: [column('id'), column('original_score', nullableNumber),
      column('payload', {...nonNullObject, additional_properties: false}), column('pos')],
    expected: [{id: 1, original_score: 20, payload: {score: 5}, pos: 2},
      {id: 2, original_score: 10, payload: {score: 30}, pos: 1},
      {id: 3, original_score: null, payload: {score: 15}, pos: 3}]}),
];
export const analyticOrderRefusals = [
  ['sibling-alias', 'SELECT amount AS renamed, ROW_NUMBER() OVER (ORDER BY renamed + 1) AS pos FROM records'],
  ['self-alias', 'SELECT ROW_NUMBER() OVER (ORDER BY pos + 1) AS pos FROM records'],
  ['removed-range', 'FROM records AS old |> AS current |> SELECT ROW_NUMBER() OVER (ORDER BY old.amount + 1) AS pos'],
  ['missing', 'SELECT ROW_NUMBER() OVER (ORDER BY missing + 1) AS pos FROM records'],
  ['missing-declaration', 'SELECT ROW_NUMBER() OVER (ORDER BY id + @offset) AS pos FROM records'],
].map(([name, text]) => ({name: 'analytic-order-refuse-' + name, format: 'aql-text', text}));
analyticOrderRefusals.push({name: 'analytic-order-refuse-parameter-type', format: 'sql',
  text: 'SELECT ROW_NUMBER() OVER (ORDER BY id + @offset) AS pos FROM records',
  parameterDeclarations: {offset: number}, parameters: {offset: 'secret-value'}});
export const analyticOrderExecutionFailures = [{name: 'analytic-order-division-failure',
  format: 'sql', text: 'SELECT id, ROW_NUMBER() OVER (ORDER BY id / (id - id), id) AS pos FROM records',
  resultNames: ['answer'], sourceReadSessionCount: 1}];
