// Independent aliases, scopes, values and schema; no compiler output is an oracle.
const number = {type: 'number', nullable: false};
const column = (name, contract = number) => ({name, contract});
const hello = {type: 'string', nullable: false, max_utf8_bytes: 5};
const collisionRows = [{id: 2, amount: 1}, {id: 1, amount: 2}];
const control = {version: 'actql/0.1', id: 'fixture.optional_output_as',
  stages: [{id: 'main', inputs: {}, steps: [
    {as: 'one', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'one', derive: {id: {literal: 1}, label: {literal: 'hello'}}},
    {select: ['id', 'label'], as: 'out'},
  ], results: {rows: {from: 'out', fields: ['id', 'label']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, extra = {}) => ({name: 'optional-output-as-' + name,
  format: 'sql', text, expected: [{id: 1, label: 'hello'}],
  columns: [column('id'), column('label', hello)], sourceReadSessionCount: 0, ...extra});
export const optionalOutputAsSuccesses = [
  success('json-control', JSON.stringify(control), {format: 'json'}),
  success('scalar', "SELECT 1 id, 'hello' label"),
  success('quoted', "SELECT 1 `id`, 'hello' `label`"),
  success('quoted-reserved', "SELECT 1 `FROM`, 'hello' `GROUP`", {
    expected: [{FROM: 1, GROUP: 'hello'}], columns: [column('FROM'), column('GROUP', hello)],
  }),
  success('alias-priority', 'SELECT id amount FROM records ORDER BY amount + 1', {
    sourceRows: collisionRows, sourceReadSessionCount: 1,
    expected: [{amount: 1}, {amount: 2}], columns: [column('amount')],
  }),
  success('qualified-input', 'SELECT r.id amount FROM records r ORDER BY r.amount + 1 NULLS LAST', {
    sourceRows: collisionRows, sourceReadSessionCount: 1,
    expected: [{amount: 2}, {amount: 1}], columns: [column('amount')],
  }),
  success('aggregate', 'SELECT COUNT(*) n FROM records', {
    sourceReadSessionCount: 1, expected: [{n: 4}], columns: [column('n')],
  }),
  success('pipe-aggregate', 'FROM records |> AGGREGATE COUNT(*) n', {
    format: 'aql-text', sourceReadSessionCount: 1, expected: [{n: 4}], columns: [column('n')],
  }),
  success('analytic', 'SELECT id, COUNT(*) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING '
    + 'AND CURRENT ROW) n FROM records ORDER BY id', {
    sourceRows: [{id: 3, amount: null}, {id: 1, amount: 20}, {id: 2, amount: 10}],
    sourceReadSessionCount: 1, expected: [{id: 1, n: 1}, {id: 2, n: 2}, {id: 3, n: 3}],
    columns: [column('id'), column('n')],
  }),
  success('cte-set', 'WITH chosen AS (SELECT 2 id UNION ALL SELECT 1 other) '
    + 'SELECT id value FROM chosen ORDER BY value + 1', {
    expected: [{value: 1}, {value: 2}], columns: [column('value')],
  }),
  success('pipe-extend', 'FROM records |> EXTEND amount + 1 next_amount '
    + '|> SELECT id, next_amount |> ORDER BY id', {
    format: 'aql-text', sourceRows: [{id: 2, amount: null}, {id: 1, amount: 2}],
    sourceReadSessionCount: 1, expected: [{id: 1, next_amount: 3}, {id: 2, next_amount: null}],
    columns: [column('id'), column('next_amount', {...number, nullable: true})],
  }),
  success('empty', 'SELECT id amount FROM records WHERE FALSE', {
    sourceReadSessionCount: 1, expected: [], columns: [column('amount')],
  }),
];
export const optionalOutputAsRefusals = [
  'SELECT 1 x, 2 X',
  'SELECT 1 x, x y',
  'SELECT 1 QUALIFY TRUE',
  'SELECT 1 id extra',
  'SELECT COUNT(*) FROM records',
  'FROM records |> SELECT * alias',
].map((text, index) => ({name: 'optional-output-as-refuse-' + index, format: 'aql-text', text}));
export const optionalOutputAsExecutionFailures = [{name: 'optional-output-as-failing-value', format: 'sql',
  text: 'SELECT 1 / 0 value', resultNames: ['answer'], sourceReadSessionCount: 0}];
