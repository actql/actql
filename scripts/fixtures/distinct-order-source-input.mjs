// Authored from projected ORDER scope, independently of the query lowerer.
// WHERE excludes 99; DISTINCT collapses two 2s; -amount sorts the already
// negated output as NULL, -1, -2. Reusing the input expression reverses it.
const rows = [{id: 3, amount: 2}, {id: 1, amount: 2},
  {id: 2, amount: 1}, {id: 4, amount: null}, {id: 0, amount: 99}];
const columns = [{name: 'amount', contract: {type: 'number', nullable: true}}];
const fullRows = [{amount: null}, {amount: -1}, {amount: -2}];
const limitedRows = [{amount: -1}, {amount: -2}];
const sql = 'SELECT DISTINCT -amount AS amount FROM records WHERE id > 0 ORDER BY -amount';
const pipe = 'FROM records |> WHERE id > 0 |> SELECT DISTINCT -amount AS amount |> ORDER BY -amount';
// The same operations are written directly as a machine Program. The common
// checker/planner/Host receives them without test-side Program modification.
const program = {version: 'actql/0.1', id: 'fixture.distinct_output_order',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {selected_value: {negate: {field: 'amount'}}}},
      {select: [{amount: 'selected_value'}]}, {distinct: ['amount']},
      {derive: {sort_only: {negate: {field: 'amount'}}}},
      {sort: [{field: 'sort_only', dir: 'asc', nulls: 'first'}]},
      {select: ['amount']}, {take: {count: 2, offset: 1}, as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['amount']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, format, text, expected, sourceRows = rows) => ({
  name: 'distinct-order-' + name, format, text, sourceRows,
  expected, columns, sourceReadSessionCount: 1,
});
export const distinctOrderSuccesses = [
  success('json-control', 'json', JSON.stringify(program), limitedRows),
  success('sql-limited', 'sql', sql + ' LIMIT 2 OFFSET 1', limitedRows),
  success('pipe-limited', 'aql-text', pipe + ' |> LIMIT 2 OFFSET 1', limitedRows),
  success('sql-null-duplicates', 'sql', sql, fullRows),
  {...success('sql-selected-qualified', 'sql',
    'SELECT DISTINCT id AS x FROM records WHERE id > 0 ORDER BY records.id + 1 DESC LIMIT 2',
    [{x: 4}, {x: 3}]), columns: [{name: 'x', contract: {type: 'number', nullable: false}}]},
  success('sql-empty', 'sql', sql, [], []),
];
export const distinctOrderRefusals = [
  'SELECT DISTINCT -amount AS amount FROM records ORDER BY id + 1',
  'SELECT DISTINCT -amount AS amount FROM records ORDER BY records.amount',
  'FROM records AS original |> SELECT DISTINCT -amount AS amount |> ORDER BY original.amount',
].map((text, index) => ({name: 'distinct-order-unselected-' + index,
  format: 'aql-text', text, expectedCode: 'ClientProgramInvalidInput'}));

// The shared Source is read once; JOIN duplicates are removed using only the
// public amount before an ORDER helper negates its evaluated output value.
const joinedProgram = structuredClone(program);
joinedProgram.id = 'fixture.join_distinct_output_order';
joinedProgram.stages[0].steps[0].filter = {literal: true};
joinedProgram.stages[1].steps.unshift(
  {from: 'records', join: {with: 'records', kind: 'inner',
    on: [{left: 'id', right: 'id'}], max_output_rows: 20,
    select: {amount: 'left.amount', id: 'left.id'}}},
  {filter: {gt: [{field: 'id'}, {literal: 0}]}},
);
delete joinedProgram.stages[1].steps[2].from;
const joinedSql = 'SELECT DISTINCT -l.amount AS amount FROM records AS l '
  + 'JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 20 '
  + 'WHERE l.id > 0 ORDER BY -amount';
distinctOrderSuccesses.push(
  success('join-json-control', 'json', JSON.stringify(joinedProgram), limitedRows),
  success('join-sql-limited', 'sql', joinedSql + ' LIMIT 2 OFFSET 1', limitedRows),
  success('join-pipe-limited', 'aql-text', 'FROM records AS l '
    + '|> JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 20 '
    + '|> WHERE l.id > 0 |> SELECT DISTINCT -l.amount AS amount '
    + '|> ORDER BY -amount |> LIMIT 2 OFFSET 1', limitedRows),
  success('join-sql-null-duplicates', 'sql', joinedSql, fullRows),
  success('join-sql-empty', 'sql', joinedSql, [], []),
);
for (const [index, order] of ['l.amount', 'l.id + 1', 'r.amount + 1'].entries()) {
  distinctOrderRefusals.push({name: 'distinct-order-join-unselected-' + index,
    format: 'sql', text: 'SELECT DISTINCT -l.amount AS amount FROM records AS l '
      + 'JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 20 ORDER BY ' + order,
    expectedCode: 'ClientProgramInvalidInput'});
}

// The SELECT input property and ORDER property have different AST spellings,
// but the same receiver slot. DISTINCT must retain and sort the computed value
// without restoring the dropped object or deriving the property a second time.
const receiverNumber = {type: 'number', nullable: true};
const receiverObject = {type: 'object', nullable: true, fields: {score: receiverNumber}};
const receiverDeclarations = {a: receiverObject, b: receiverObject,
  c: receiverObject, d: receiverObject};
const receiverParameters = {a: {score: 10}, b: {score: 20}, c: null, d: {score: null}};
const receiverRows = [{id: 2, amount: 20}, {id: 1, amount: 10},
  {id: 4, amount: 10}, {id: 3, amount: 99}, {id: 5, amount: 88}, {id: 0, amount: 777}];
const receiverData = 'WITH objects AS (SELECT id, amount AS score, '
  + 'CASE WHEN id = 2 THEN @a WHEN id = 1 OR id = 4 THEN @b WHEN id = 5 THEN @d ELSE @c END AS payload '
  + 'FROM records WHERE id > 0) ';
const receiverExpected = [{score: 10}, {score: 20}, {score: null}];
const receiverColumns = [{name: 'score', contract: receiverNumber}];
export const orderReceiverProgram = {version: 'actql/0.1', id: 'fixture.order_property_receiver',
  params: receiverDeclarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {payload: {case: {when: [
      {when: {eq: [{field: 'id'}, {literal: 2}]}, then: {$param: 'a'}},
      {when: {or: [{eq: [{field: 'id'}, {literal: 1}]}, {eq: [{field: 'id'}, {literal: 4}]}]}, then: {$param: 'b'}},
      {when: {eq: [{field: 'id'}, {literal: 5}]}, then: {$param: 'd'}},
    ], else: {$param: 'c'}}}}},
      {select: ['id', {score: 'amount'}, 'payload']},
      {derive: {selected_score: {property: {name: 'score', value: {field: 'payload'}}}}},
      {select: [{score: 'selected_score'}]}, {distinct: ['score']},
      {sort: [{field: 'score', dir: 'asc', nulls: 'last'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['score']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const receiverCase = (name, query, extra = {}) => ({name: 'order-receiver-' + name,
  format: 'aql-text', text: receiverData + query,
  parameterDeclarations: receiverDeclarations, parameters: receiverParameters,
  sourceRows: receiverRows, sourceReadSessionCount: 1,
  expected: receiverExpected, columns: receiverColumns, ...extra});
distinctOrderSuccesses.push(
  receiverCase('independent-json', '', {format: 'json', parameterDeclarations: undefined,
    text: JSON.stringify(orderReceiverProgram)}),
  receiverCase('distinct-explicit', 'SELECT DISTINCT payload.score AS score FROM objects ORDER BY (payload).score NULLS LAST'),
  receiverCase('distinct-qualified', 'SELECT DISTINCT (payload).score AS score FROM objects ORDER BY objects.payload.score NULLS LAST'),
  receiverCase('distinct-quoted', 'SELECT DISTINCT ((payload)).`SCORE` AS score FROM objects ORDER BY payload.score NULLS LAST'),
  receiverCase('distinct-pipe', 'FROM objects AS active |> SELECT DISTINCT active.payload.score AS score |> ORDER BY (payload).score NULLS LAST'),
  receiverCase('distinct-computed', 'SELECT DISTINCT payload.score + 1 AS score FROM objects ORDER BY (payload).score + 1 NULLS LAST', {
    expected: [{score: 11}, {score: 21}, {score: null}],
  }),
  receiverCase('distinct-limited', 'SELECT DISTINCT (payload).score AS score FROM objects ORDER BY objects.payload.score NULLS LAST LIMIT 2 OFFSET 1', {
    expected: [{score: 20}, {score: null}],
  }),
  receiverCase('distinct-empty', 'SELECT DISTINCT payload.score AS score FROM objects ORDER BY (payload).score NULLS LAST', {sourceRows: [], expected: []}),
  receiverCase('ordinary-reuse', 'SELECT payload.score AS score FROM objects ORDER BY (payload).score NULLS LAST', {
    expected: [{score: 10}, {score: 20}, {score: 20}, {score: null}, {score: null}],
  }),
);
for (const [index, query] of [
  'SELECT DISTINCT (payload.payload).score AS score FROM objects AS payload ORDER BY payload.score',
  'SELECT DISTINCT payload.score AS score FROM objects AS payload ORDER BY (payload.payload).score',
  'SELECT DISTINCT (payload.payload).score + 1 AS score FROM objects AS payload ORDER BY payload.score + 1',
  'SELECT DISTINCT payload.score AS score FROM objects ORDER BY objects.id',
].entries()) {
  distinctOrderRefusals.push({...receiverCase('unselected-' + index, query),
    expectedCode: 'ClientProgramInvalidInput'});
}
