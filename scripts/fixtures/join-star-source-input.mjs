// Public rows/schema/order and JSON control are authored from JOIN semantics.
const number = {type: 'number', nullable: false};
const nullable = {...number, nullable: true};
const column = (name, contract = number) => ({name, contract});
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}];
const sourceColumns = [column('amount', nullable), column('id')];
export const joinStarProgram = {version: 'actql/0.1', id: 'fixture.join_star',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {literal: true}}, {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{values: {schema: {k: number}, rows: [{k: 2}]}, as: 'keys'},
      {from: 'records', join: {with: 'keys', kind: 'inner',
        on: [{left: 'id', right: 'k'}], max_output_rows: 10,
        select: {amount: 'left.amount', id: 'left.id', k: 'right.k'}}, as: 'joined'},
      {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['amount', 'id', 'k']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
// Independent common Program for projection-only captured self JOIN.
export const capturedJoinProjectionProgram = {version: 'actql/0.1', id: 'fixture.captured_join_projection',
  stages: [structuredClone(joinStarProgram.stages[0]),
    {id: 'main', inputs: {
      left: {result: {stage: 'capture', result: 'source'}},
      right: {result: {stage: 'capture', result: 'source'}},
    }, steps: [{from: 'left', join: {with: 'right', kind: 'inner',
      on: [{left: 'id', right: 'id'}], max_output_rows: 10,
      select: {id: 'left.id', amount: 'right.amount'}}, as: 'joined'},
      {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'amount']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
// Independent scalar SET control. RIGHT JOIN preserves keys; its nullable
// original amount remains a separate slot when the current value is replaced.
export const pipeSetTargetProgram = {version: 'actql/0.1', id: 'fixture.pipe_set_target',
  stages: [structuredClone(joinStarProgram.stages[0]),
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{values: {schema: {k: number}, rows: [{k: 3}]}, as: 'keys'},
        {from: 'keys', join: {with: 'records', kind: 'left',
          on: [{left: 'k', right: 'id'}], max_output_rows: 10,
          select: {original: 'right.amount', matched: 'left.k'}}, as: 'joined'},
        {derive: {current: {literal: 99}}},
        {sort: [{field: 'original', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
      results: {rows: {from: 'ordered', fields: ['current', 'original', 'matched']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
// Independent machine input for the standalone Values compiler contract.
export const valuesJoinCeilingProgram = {version: 'actql/0.1', id: 'fixture.values_join_ceiling',
  stages: [{id: 'aql_join_left', inputs: {}, steps: [{values: {
    schema: {x: number, y: number}, rows: [{x: 1, y: 20}, {x: 2, y: 10}],
  }, as: 't'}], results: {aql_join_left: {from: 't', fields: ['x', 'y']}}},
  {id: 'aql_join_right', inputs: {}, steps: [{values: {
    schema: {k: number}, rows: [{k: 1}, {k: 2}],
  }, as: 'r'}], results: {aql_join_right: {from: 'r', fields: ['k']}}},
  {id: 'main', inputs: {l: {result: {stage: 'aql_join_left', result: 'aql_join_left'}},
    r: {result: {stage: 'aql_join_right', result: 'aql_join_right'}}},
    steps: [{from: 'l', join: {with: 'r', kind: 'inner', on: [{left: 'x', right: 'k'}],
      max_output_rows: 5, select: {x: 'left.x'}}, as: 'aql_join_output'}],
    results: {rows: {from: 'aql_join_output', fields: ['x']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const valuesJoinCeilingSql = 'WITH t AS (SELECT 1 AS x, 20 AS y UNION ALL SELECT 2 AS x, 10 AS y), '
  + 'r AS (SELECT 1 AS k UNION ALL SELECT 2 AS k) SELECT t.x AS x FROM t JOIN r '
  + 'ON t.x = r.k MAX_OUTPUT_ROWS 5';
const exceededValuesJoin = structuredClone(valuesJoinCeilingProgram);
exceededValuesJoin.stages[2].steps[0].join.max_output_rows = 1;
export const joinStarExecutionFailures = [
  {name: 'join-star-values-ceiling-json-exceeded', format: 'json',
    text: JSON.stringify(exceededValuesJoin), resultNames: ['answer'], sourceReadSessionCount: 0},
  {name: 'join-star-values-ceiling-source-exceeded', format: 'sql',
    text: valuesJoinCeilingSql.replace('MAX_OUTPUT_ROWS 5', 'MAX_OUTPUT_ROWS 1'),
    resultNames: ['main'], sourceReadSessionCount: 0},
];
const sql = 'SELECT * FROM records AS l JOIN (SELECT 2 AS k) AS r '
  + 'ON l.id = r.k MAX_OUTPUT_ROWS 10 ORDER BY id';
const success = (name, text, extra = {}) => ({name: 'join-star-' + name,
  format: 'sql', text, sourceRows, sourceReadSessionCount: 1,
  columns: [...sourceColumns, column('k')], expected: [{amount: 20, id: 2, k: 2}], ...extra});
const usingColumns = [column('id'), column('amount', nullable)];
const preserved = [{id: 1, amount: null}, {id: 2, amount: 20},
  {id: 3, amount: 30}, {id: 3, amount: 30}];
export const joinStarSuccesses = [
  success('independent-json', JSON.stringify(joinStarProgram), {format: 'json'}),
  success('on-unique-columns', sql),
  success('values-ceiling-json', JSON.stringify(valuesJoinCeilingProgram), {
    format: 'json', sourceReadSessionCount: 0, columns: [column('x')],
    expected: [{x: 1}, {x: 2}], unordered: true,
  }),
  success('values-ceiling-source', valuesJoinCeilingSql, {
    sourceReadSessionCount: 0, columns: [column('x')],
    expected: [{x: 1}, {x: 2}], unordered: true,
  }),
  success('captured-projection-json', JSON.stringify(capturedJoinProjectionProgram), {
    format: 'json', columns: [column('id'), column('amount', nullable)],
    expected: [{id: 1, amount: null}, {id: 2, amount: 20},
      ...Array.from({length: 4}, () => ({id: 3, amount: 30}))],
  }),
  success('captured-projection-source', 'SELECT l.id AS id, r.amount AS amount FROM records AS l '
    + 'JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 ORDER BY id', {
    columns: [column('id'), column('amount', nullable)],
    expected: [{id: 1, amount: null}, {id: 2, amount: 20},
      ...Array.from({length: 4}, () => ({id: 3, amount: 30}))],
  }),
  success('captured-projection-filtered', 'SELECT l.id AS id, r.amount AS amount FROM records AS l '
    + 'JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 WHERE r.amount > 20 ORDER BY id', {
    columns: [column('id'), column('amount', nullable)],
    expected: Array.from({length: 4}, () => ({id: 3, amount: 30})),
  }),
  success('captured-projection-limited', 'SELECT l.id AS id, r.amount AS amount FROM records AS l '
    + 'JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 ORDER BY id LIMIT 2 OFFSET 1', {
    columns: [column('id'), column('amount', nullable)],
    expected: [{id: 2, amount: 20}, {id: 3, amount: 30}],
  }),
  success('repeated-on-kept', sql.replace('ON l.id = r.k MAX_OUTPUT_ROWS',
    'ON l.id = r.k AND l.id = r.k MAX_OUTPUT_ROWS')),
  success('left-on-nullability', 'SELECT * FROM records AS l LEFT JOIN (SELECT 3 AS k) AS r '
    + 'ON l.id = r.k MAX_OUTPUT_ROWS 10 ORDER BY id', {
    columns: [...sourceColumns, column('k', nullable)],
    expected: [{amount: null, id: 1, k: null}, {amount: 20, id: 2, k: null},
      {amount: 30, id: 3, k: 3}, {amount: 30, id: 3, k: 3}],
  }),
  success('inner-using-key-first', 'SELECT * FROM records AS l JOIN (SELECT 2 AS id) AS r '
    + 'USING (id) MAX_OUTPUT_ROWS 10 ORDER BY id', {columns: usingColumns, expected: [{id: 2, amount: 20}]}),
  success('left-using-key-first', 'SELECT * FROM records AS l LEFT JOIN (SELECT 2 AS id) AS r '
    + 'USING (id) MAX_OUTPUT_ROWS 10 ORDER BY id', {columns: usingColumns, expected: preserved}),
  success('using-qualified-null-control', 'SELECT *, l.id AS original, r.id AS joined '
    + 'FROM records AS l LEFT JOIN (SELECT 2 AS id) AS r USING (id) MAX_OUTPUT_ROWS 10 ORDER BY id', {
    columns: [...usingColumns, column('original'), column('joined', nullable)],
    expected: preserved.map(row => ({...row, original: row.id, joined: row.id === 2 ? 2 : null})),
  }),
  success('declared-using-order', 'SELECT * FROM records AS l JOIN records AS r '
    + 'USING (id, amount) MAX_OUTPUT_ROWS 10 ORDER BY id', {
    columns: usingColumns, expected: [{id: 2, amount: 20},
      {id: 3, amount: 30}, {id: 3, amount: 30}, {id: 3, amount: 30}, {id: 3, amount: 30}],
  }),
  success('except-preserves-input-order', 'SELECT * EXCEPT (k) FROM records AS l JOIN (SELECT 2 AS k) AS r '
    + 'ON l.id = r.k MAX_OUTPUT_ROWS 10 ORDER BY id', {columns: sourceColumns, expected: [{amount: 20, id: 2}]}),
  success('cte-using-current-row', 'WITH chosen AS (SELECT amount, id FROM records) '
    + 'SELECT * FROM chosen AS l LEFT JOIN (SELECT 2 AS id) AS r USING (id) MAX_OUTPUT_ROWS 10 ORDER BY id', {
    columns: usingColumns, expected: preserved,
  }),
  success('empty-typed-result', sql, {sourceRows: [], expected: []}),
  success('set-target-independent-json', JSON.stringify(pipeSetTargetProgram), {
    format: 'json', columns: [column('current'), column('original', nullable), column('matched')],
    expected: [{current: 99, original: 30, matched: 3}, {current: 99, original: 30, matched: 3}],
  }),
  success('set-target-unique-range', 'FROM records AS l |> RIGHT JOIN (SELECT 3 AS k) AS r '
    + 'ON l.id = r.k MAX_OUTPUT_ROWS 10 |> SET amount = 99 '
    + '|> SELECT amount AS current, l.amount AS original, r.k AS matched |> ORDER BY original', {
    format: 'aql-text',
    columns: [column('current'), column('original', nullable), column('matched')],
    expected: [{current: 99, original: 30, matched: 3}, {current: 99, original: 30, matched: 3}],
  }),
  success('set-target-unmatched-range', 'FROM records AS l |> RIGHT JOIN (SELECT 9 AS k) AS r '
    + 'ON l.id = r.k MAX_OUTPUT_ROWS 10 |> SET amount = 99 '
    + '|> SELECT amount AS current, l.amount AS original, r.k AS matched |> ORDER BY original', {
    format: 'aql-text',
    columns: [column('current'), column('original', nullable), column('matched')],
    expected: [{current: 99, original: null, matched: 9}],
  }),
  success('set-target-coalesced-using', 'FROM records AS l |> RIGHT JOIN records AS r '
    + 'USING (id) MAX_OUTPUT_ROWS 10 |> SET id = -id '
    + '|> SELECT id AS current, l.id AS left_original, r.id AS right_original |> ORDER BY right_original', {
    format: 'aql-text',
    columns: [column('current'), column('left_original', nullable), column('right_original')],
    expected: [{current: -1, left_original: 1, right_original: 1},
      {current: -2, left_original: 2, right_original: 2},
      ...Array.from({length: 4}, () => ({current: -3, left_original: 3, right_original: 3}))],
  }),
];
export const joinStarRefusals = [
  'SELECT * FROM records AS l JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 10',
  'SELECT * FROM records AS l JOIN records AS r USING (id, `ID`) MAX_OUTPUT_ROWS 10',
  'SELECT * FROM records AS l JOIN (SELECT 2 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 0',
  'SELECT * EXCEPT (missing) FROM records AS l JOIN (SELECT 2 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 10',
].map((text, index) => ({name: 'join-star-refuse-' + index, format: 'sql', text,
  expectedCode: 'ClientProgramInvalidInput'}));
for (const kind of ['INNER', 'LEFT', 'RIGHT', 'FULL']) {
  joinStarRefusals.push({name: 'join-star-refuse-hidden-using-' + kind.toLowerCase(),
    format: 'sql', expectedCode: 'ClientProgramInvalidInput',
    text: `SELECT l.id AS original FROM records AS l ${kind} JOIN records AS r `
      + 'USING (id, `ID`) MAX_OUTPUT_ROWS 10'});
}
for (const [index, target] of ['id', 'ID', '`id`', '`ID`'].entries()) {
  for (const [kind, expression] of [['scalar', '99'], ['window', 'ROW_NUMBER() OVER (ORDER BY r.id)']]) {
    joinStarRefusals.push({name: `join-star-refuse-set-target-${kind}-${index}`, format: 'aql-text',
      expectedCode: 'ClientProgramInvalidInput',
      text: 'FROM records AS l |> RIGHT JOIN records AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 '
        + `|> SET ${target} = ${expression} |> SELECT l.id AS left_id, r.id AS right_id`});
  }
}
