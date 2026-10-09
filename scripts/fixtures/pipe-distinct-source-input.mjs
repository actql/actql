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
// Full JOIN-row equality precedes projection. Rows with ids 2 and 4 remain
// different here even though both later project to {amount: 20}.
export const joinPipeDistinctProgram = {version: 'actql/0.1', id: 'fixture.join_pipe_distinct',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {left_rows: {result: {stage: 'capture', result: 'source'}},
    right_rows: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'left_rows', join: {with: 'right_rows', kind: 'inner',
      on: [{left: 'id', right: 'id'}], max_output_rows: 20,
      select: {left_amount: 'left.amount', left_id: 'left.id',
        right_amount: 'right.amount', right_id: 'right.id'}}, as: 'joined'},
    {from: 'joined', distinct: ['left_amount', 'left_id', 'right_amount', 'right_id']},
    {sort: [{field: 'left_amount', dir: 'asc', nulls: 'last'}]},
    {select: [{amount: 'left_amount'}], as: 'projected'}],
    results: {rows: {from: 'projected', fields: ['amount']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const crossPipeDistinctProgram = {version: 'actql/0.1', id: 'fixture.cross_pipe_distinct',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{values: {schema: {match_id: number},
      rows: [{match_id: 1}, {match_id: 1}, {match_id: 2}]}, as: 'matches'},
    {from: 'records', cross_join: {with: 'matches', max_output_rows: 15,
      select: {amount: 'left.amount', id: 'left.id', match_id: 'right.match_id'}}, as: 'joined'},
    {from: 'joined', distinct: ['amount', 'id', 'match_id']},
    {sort: [{field: 'amount', dir: 'asc', nulls: 'last'},
      {field: 'id', dir: 'asc', nulls: 'first'},
      {field: 'match_id', dir: 'asc', nulls: 'first'}]},
    {select: ['amount'], as: 'projected'}],
    results: {rows: {from: 'projected', fields: ['amount']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const joinAmounts = [{amount: 20}, {amount: 20}, {amount: 30}, {amount: null}];
const crossAmounts = [{amount: 20}, {amount: 20}, {amount: 20}, {amount: 20},
  {amount: 30}, {amount: 30}, {amount: null}, {amount: null}];
const joinDistinct = 'FROM records AS l |> JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 20 '
  + '|> DISTINCT |> SELECT l.amount AS amount |> ORDER BY amount NULLS LAST';
const crossDistinct = 'FROM records AS l |> CROSS JOIN '
  + '(SELECT 1 AS match_id UNION ALL SELECT 1 AS match_id UNION ALL SELECT 2 AS match_id) '
  + 'AS r MAX_OUTPUT_ROWS 15 |> DISTINCT |> ORDER BY l.amount NULLS LAST, l.id, r.match_id '
  + '|> SELECT l.amount AS amount';
const success = (name, text, extra = {}) => ({name: 'pipe-distinct-' + name,
  format: 'aql-text', text, sourceRows, expected: amounts, columns: amountColumns,
  sourceReadSessionCount: 1, ...extra});
const drop = 'FROM records AS original |> DROP id |> DISTINCT '
  + '|> SELECT original.amount AS amount |> ORDER BY amount NULLS LAST';
export const pipeDistinctSuccesses = [
  success('independent-json', JSON.stringify(pipeDistinctProgram), {format: 'json'}),
  success('join-independent-json', JSON.stringify(joinPipeDistinctProgram),
    {format: 'json', expected: joinAmounts}),
  success('join-before-projection', joinDistinct, {expected: joinAmounts}),
  success('join-quoted-surviving-ranges', 'FROM records AS `Left` |> JOIN records AS `Right` '
    + 'ON `LEFT`.`ID` = `RIGHT`.`ID` MAX_OUTPUT_ROWS 20 |> DISTINCT '
    + '|> SELECT `LEFT`.`AMOUNT` AS amount |> ORDER BY amount NULLS LAST', {expected: joinAmounts}),
  success('join-after-sql-projection', 'SELECT l.amount AS amount FROM records AS l '
    + 'JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 20 |> DISTINCT '
    + '|> ORDER BY amount NULLS LAST', {format: 'sql'}),
  success('join-typed-empty', joinDistinct, {sourceRows: [], expected: []}),
  success('cross-join-independent-json', JSON.stringify(crossPipeDistinctProgram),
    {format: 'json', expected: crossAmounts}),
  success('cross-join-before-projection', crossDistinct, {expected: crossAmounts}),
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
  {name: 'join-ambiguous-column', text: 'FROM records AS l |> JOIN records AS r '
    + 'ON l.id = r.id MAX_OUTPUT_ROWS 20 |> DISTINCT |> SELECT id',
    expectedCode: 'ClientProgramInvalidInput'},
  {name: 'join-projected-range', text: 'FROM records AS l |> JOIN records AS r '
    + 'ON l.id = r.id MAX_OUTPUT_ROWS 20 |> SELECT l.amount AS amount |> DISTINCT |> SELECT l.id',
    expectedCode: 'ClientProgramInvalidInput'},
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
