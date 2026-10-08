// Independent visible-row and range-slot expectations from the pinned GoogleSQL
// Pipe DISTINCT rules. Different old ids must not prevent current-row equality.
const number = {type: 'number', nullable: false};
const nullable = {...number, nullable: true};
const amountColumns = [{name: 'amount', contract: nullable}];
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 4, amount: 20}];
const amounts = [{amount: 20}, {amount: 30}, {amount: null}];
const allRows = [{amount: 30, id: 3}, {amount: 20, id: 2},
  {amount: 20, id: 4}, {amount: null, id: 1}];
const allColumns = [...amountColumns, {name: 'id', contract: number}];
// An independently authored machine input, not a post-lowering correction.
export const pipeDistinctProgram = {version: 'actql/0.1', id: 'fixture.pipe_distinct',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', distinct: ['amount']},
      {sort: [{field: 'amount', dir: 'asc', nulls: 'last'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['amount']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, extra = {}) => ({name: 'pipe-distinct-' + name,
  format: 'aql-text', text, sourceRows, expected: amounts, columns: amountColumns,
  sourceReadSessionCount: 1, ...extra});
const drop = 'FROM records AS original |> DROP id |> DISTINCT '
  + '|> SELECT original.amount AS amount |> ORDER BY amount NULLS LAST';
export const pipeDistinctSuccesses = [
  success('independent-json', JSON.stringify(pipeDistinctProgram), {format: 'json'}),
  success('drop-preserves-surviving-range', drop),
  success('set-prunes-displaced-slot', 'FROM records AS original |> SET id = 0 |> DISTINCT '
    + '|> SELECT original.amount AS amount, id |> ORDER BY amount NULLS LAST',
    {expected: [{amount: 20, id: 0}, {amount: 30, id: 0}, {amount: null, id: 0}], columns: allColumns}),
  success('rename-preserves-value-slot', 'FROM records AS original |> RENAME amount AS score |> DISTINCT '
    + '|> SELECT original.amount AS score, id |> ORDER BY score DESC NULLS LAST, id',
    {expected: allRows.map(row => ({score: row.amount, id: row.id})),
      columns: [{name: 'score', contract: nullable}, {name: 'id', contract: number}]}),
  success('select-then-current-where', 'FROM records |> SELECT amount |> DISTINCT '
    + '|> WHERE amount >= 20 |> ORDER BY amount', {expected: [{amount: 20}, {amount: 30}]}),
  success('rebind-quoted-range', 'FROM records AS original |> DROP id |> AS `Current` |> DISTINCT '
    + '|> SELECT `CURRENT`.`AMOUNT` AS amount |> ORDER BY amount NULLS LAST'),
  success('sql-headed-tail', 'SELECT amount, id FROM records |> DISTINCT '
    + '|> ORDER BY amount DESC NULLS LAST, id', {format: 'sql', expected: allRows, columns: allColumns}),
  success('data-shared-set', 'DATA copied = FROM records |> SELECT amount '
    + '|> UNION ALL (FROM records |> SELECT amount) |> DISTINCT; FROM copied |> ORDER BY amount NULLS LAST'),
  success('cte-distinct-body', 'WITH chosen AS (FROM records AS original |> DROP id |> DISTINCT '
    + '|> SELECT original.amount AS amount) SELECT amount FROM chosen ORDER BY amount NULLS LAST', {format: 'sql'}),
  success('join-prefix-surviving-range', 'FROM records AS original |> SET id = 0 |> DISTINCT '
    + '|> JOIN records AS rr ON original.amount = rr.amount MAX_OUTPUT_ROWS 20 '
    + '|> SELECT original.amount AS amount, rr.id AS id |> ORDER BY amount, id',
    {expected: [{amount: 20, id: 2}, {amount: 20, id: 4}, {amount: 30, id: 3}, {amount: 30, id: 3}], columns: allColumns}),
  success('typed-empty', drop, {sourceRows: [], expected: []}),
  success('parameter-predicate-limit', 'FROM records |> WHERE id >= @minimum |> DROP id '
    + '|> DISTINCT |> ORDER BY amount |> LIMIT 1 OFFSET 1', {parameterDeclarations: {minimum: number},
      parameters: {minimum: 2}, expected: [{amount: 30}]}),
  success('scalar-value-table', 'FROM UNNEST(@items) AS value |> DISTINCT |> ORDER BY value NULLS LAST',
    {parameterDeclarations: {items: {type: 'array', max_items: 4, items: nullable}},
      parameters: {items: [2, 2, 1, null]}, expected: [{value: 1}, {value: 2}, {value: null}],
      columns: [{name: 'value', contract: nullable}], sourceReadCount: 0, sourceReadSessionCount: 0}),
];
export const pipeDistinctRefusals = [
  {name: 'arguments', text: 'FROM records |> DISTINCT amount'},
  {name: 'removed-by-drop', text: 'FROM records AS original |> DROP id |> DISTINCT |> SELECT original.id'},
  {name: 'displaced-by-set', text: 'FROM records AS original |> SET id = 0 |> DISTINCT |> SELECT original.id'},
  {name: 'replaced-range', text: 'FROM records AS original |> AS current |> DISTINCT |> SELECT original.id'},
  {name: 'projected-range', text: 'FROM records AS original |> SELECT amount |> DISTINCT |> SELECT original.amount'},
  {name: 'undeclared-parameter', text: 'FROM records |> WHERE id >= @missing |> DISTINCT'},
  {name: 'non-groupable-json', text: "SELECT JSON 'null' AS payload |> DISTINCT", format: 'sql'},
  {name: 'closed-value-table', text: 'FROM UNNEST(@items) AS value |> DISTINCT',
    parameterDeclarations: {items: {type: 'array', max_items: 2,
      items: {type: 'object', nullable: true, fields: {score: nullable}}}},
    parameters: {items: [null, {score: null}]}, expectedCode: 'ClientProgramImplementationLimit'},
].map(item => ({format: 'aql-text', ...item, name: 'pipe-distinct-refuse-' + item.name}));
