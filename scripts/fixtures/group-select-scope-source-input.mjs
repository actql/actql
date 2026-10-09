// Independent expectations from SELECT input scope and aggregate output scope.
// WHERE excludes ID 0. Two ID 3 rows remain two COUNT contributions; amount
// retains its nullable contract. No product lowerer computes these fixtures.
const rows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 0, amount: 99}];
const number = (name, nullable = false) => ({name,
  contract: {type: 'number', nullable}});
const globalRows = [{n: 4, one: 1}];
const globalColumns = [number('n'), number('one')];
const program = {version: 'actql/0.1', id: 'fixture.group_select_scope',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', group: {by: [], aggregates: {n: {fn: 'count'}}}},
      {derive: {one: {literal: 1}}}, {select: ['n', 'one'], as: 'summary'}],
    results: {rows: {from: 'summary', fields: ['n', 'one']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, format, text, overrides = {}) => ({
  name: 'group-select-scope-' + name, format, text, sourceRows: rows,
  expected: globalRows, columns: globalColumns, sourceReadSessionCount: 1,
  ...overrides,
});
const sql = 'SELECT COUNT(*) AS n, 1 AS one FROM records WHERE id > 0';
const nextRows = [{n: 4, next: 5}];
const nextColumns = [number('n'), number('next')];
export const groupSelectScopeSuccesses = [
  success('json-control', 'json', JSON.stringify(program)),
  success('sql-global-constant', 'sql', sql),
  success('sql-grouped-input-expression', 'sql', 'SELECT records.id + 1 AS next, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY id HAVING n > 0 ORDER BY next', {
    expected: [{next: 2, n: 1}, {next: 3, n: 1}, {next: 4, n: 2}],
    columns: [number('next'), number('n')],
  }),
  success('sql-next-pipe-scope', 'sql', 'SELECT COUNT(*) AS n FROM records WHERE id > 0 |> SELECT n, n + 1 AS next |> ORDER BY next', {
    expected: nextRows, columns: nextColumns,
  }),
  success('pipe-next-projection-scope', 'aql-text', 'FROM records |> WHERE id > 0 |> AGGREGATE COUNT(*) AS n |> SELECT n, n + 1 AS next |> ORDER BY next', {
    expected: nextRows, columns: nextColumns,
  }),
  success('scoped-join-grouped-input', 'sql', 'WITH a AS (SELECT 1 AS x UNION ALL SELECT 1 AS x), b AS (SELECT 1 AS k), c AS (SELECT 1 AS z) SELECT a.x AS x, COUNT(*) AS n FROM a JOIN b ON a.x = b.k JOIN c ON b.k = c.z GROUP BY a.x HAVING n > 0 ORDER BY n + x', {
    expected: [{x: 1, n: 2}], columns: [number('x'), number('n')],
    sourceReadSessionCount: 0,
  }),
  success('empty-global-constant', 'sql', sql, {
    sourceRows: [], expected: [{n: 0, one: 1}],
  }),
  success('nullable-grouped-input', 'sql', 'SELECT amount, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY amount HAVING n > 0 ORDER BY amount', {
    expected: [{amount: null, n: 1}, {amount: 20, n: 1}, {amount: 30, n: 2}],
    columns: [number('amount', true), number('n')],
  }),
];
export const groupSelectScopeRefusals = [
  'SELECT COUNT(*) AS n, n + 1 AS next FROM records',
  'SELECT n + 1 AS next, COUNT(*) AS n FROM records',
  'SELECT COUNT(*) AS id, id + 1 AS next FROM records',
  'SELECT COUNT(*) AS n, records.n AS next FROM records',
  'WITH a AS (SELECT 1 AS x), b AS (SELECT 1 AS k), c AS (SELECT 1 AS z) SELECT COUNT(*) AS n, n + 1 AS next FROM a JOIN b ON a.x = b.k JOIN c ON b.k = c.z',
].map((text, index) => ({name: 'group-select-scope-invalid-sibling-' + index,
  format: 'sql', text}));

// FLOAT64 spellings 1.0 and 1e0 have the same admitted value. Grouping and
// DISTINCT reuse evaluated expressions; neither restores a removed input.
const numericProgram = structuredClone(program);
numericProgram.id = 'fixture.group_numeric_reuse';
numericProgram.stages[1].steps = [
  {from: 'records', derive: {group_value: {add: [{field: 'id'}, {literal: 1}]}}},
  {group: {by: ['group_value'], aggregates: {n: {fn: 'count'}}}},
  {select: [{next: 'group_value'}, 'n']},
  {sort: [{field: 'next', dir: 'asc', nulls: 'first'}], as: 'summary'},
];
numericProgram.stages[1].results.rows.fields = ['next', 'n'];
const groupedRows = [{next: 2, n: 1}, {next: 3, n: 1}, {next: 4, n: 2}];
const groupedColumns = [number('next'), number('n')];
groupSelectScopeSuccesses.push(
  success('numeric-json-control', 'json', JSON.stringify(numericProgram), {
    expected: groupedRows, columns: groupedColumns,
  }),
  success('numeric-sql-group', 'sql', 'SELECT id + 1.0 AS next, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY id + 1e0 ORDER BY next', {
    expected: groupedRows, columns: groupedColumns,
  }),
  success('numeric-nullable-group', 'sql', 'SELECT amount + 1.0 AS next, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY amount + 1e0 ORDER BY next', {
    expected: [{next: null, n: 1}, {next: 21, n: 1}, {next: 31, n: 2}],
    columns: [number('next', true), number('n')],
  }),
  success('numeric-distinct-reuse', 'sql', 'SELECT DISTINCT id + 1.0 AS next FROM records WHERE id > 0 ORDER BY records.id + 1e0 DESC LIMIT 2', {
    expected: [{next: 4}, {next: 3}], columns: [number('next')],
  }),
  success('numeric-distinct-alias-guard', 'sql', 'SELECT DISTINCT -amount + 1.0 AS amount FROM records WHERE id > 0 ORDER BY -amount + 1e0', {
    expected: [{amount: null}, {amount: -19}, {amount: -29}],
    columns: [number('amount', true)],
  }),
);
groupSelectScopeRefusals.push(
  {name: 'group-select-scope-numeric-distinct-unselected', format: 'sql',
    expectedCode: 'ClientProgramImplementationLimit',
    text: 'SELECT DISTINCT id + 1.0 AS next FROM records ORDER BY id + 2e0'},
  {name: 'group-select-scope-numeric-unsafe-integer', format: 'sql',
    text: 'SELECT id + 9007199254740992.0 AS next, COUNT(*) AS n FROM records GROUP BY id + 9007199254740992'},
);

// Legitimate authored names cannot collide with a generated GROUP slot.
// Deliberately unequal id values on duplicate amounts detect grouping by the
// wrong authored column; neither the compiler nor a runtime creates this oracle.
const collisionRows = [{id: 1, amount: 2}, {id: 2, amount: 1},
  {id: 3, amount: 2}, {id: 4, amount: null}, {id: 0, amount: 99}];
const collisionExpected = [{bucket: null, n: 1}, {bucket: 2, n: 1}, {bucket: 3, n: 2}];
const collisionColumns = [number('bucket', true), number('n')];
export const groupKeyCollisionProgram = {
  version: 'actql/0.1', id: 'fixture.group_key_collision',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: [{x: 'amount'}, {aql_group_key_0: 'id'}], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['x', 'aql_group_key_0']}}},
  {id: 'main', inputs: {colliding: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'colliding', derive: {key: {add: [{field: 'x'}, {literal: 1}]}}},
      {group: {by: ['key'], aggregates: {n: {fn: 'count'}}}},
      {select: [{bucket: 'key'}, 'n']},
      {sort: [{field: 'bucket', dir: 'asc', nulls: 'first'}], as: 'summary'}],
    results: {rows: {from: 'summary', fields: ['bucket', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}},
};
const collisionData = 'DATA colliding = SELECT amount AS x, id AS aql_group_key_0 FROM records WHERE id > 0; ';
const collisionSql = 'SELECT x + 1 AS bucket, COUNT(*) AS n FROM colliding GROUP BY x + 1 ORDER BY bucket';
const collision = (name, text, extra = {}) => success('private-key-' + name, 'aql-text', text, {
  sourceRows: collisionRows, expected: collisionExpected, columns: collisionColumns, ...extra,
});
groupSelectScopeSuccesses.push(
  collision('independent-json', JSON.stringify(groupKeyCollisionProgram), {format: 'json'}),
  collision('sql-input', collisionData + collisionSql),
  collision('quoted-case', collisionData.replace('AS aql_group_key_0', 'AS `AQL_GROUP_KEY_0`') + collisionSql),
  collision('all', collisionData + collisionSql.replace('GROUP BY x + 1', 'GROUP BY ALL')),
  collision('pipe', collisionData + 'FROM colliding AS original |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 AS bucket |> ORDER BY bucket'),
  collision('output-alias', 'DATA colliding = SELECT amount AS x FROM records WHERE id > 0; '
    + collisionSql.replace('AS n', 'AS aql_group_key_0'), {
    expected: collisionExpected.map(({bucket, n}) => ({bucket, aql_group_key_0: n})),
    columns: [number('bucket', true), number('aql_group_key_0')],
  }),
  collision('empty', collisionData + collisionSql, {sourceRows: [], expected: []}),
);
groupSelectScopeRefusals.push({name: 'group-select-scope-private-key-ungrouped-input',
  format: 'aql-text', expectedCode: 'ClientProgramInvalidInput',
  text: collisionData + 'SELECT x + 1 AS bucket, COUNT(*) AS n '
    + 'FROM colliding GROUP BY x + 1 HAVING colliding.aql_group_key_0 > 0'});
