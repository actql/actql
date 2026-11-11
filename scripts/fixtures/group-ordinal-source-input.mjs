import {scalarAliasGroupSuccesses, scalarAliasGroupRefusals}
  from './scalar-alias-group-source-input.mjs';
import {groupComparisonSuccesses, groupComparisonRefusals}
  from './group-comparison-source-input.mjs';

// Independent grouped values and named-column contracts, not lowerer output.
// GROUP 2,1 denotes amount,id in the SELECT list id,amount,n. WHERE excludes
// ID 0; duplicate ID 3 rows must contribute to n=2, and NULL is a real key.
const rows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 0, amount: 99}];
const number = (name, nullable = false) => ({name,
  contract: {type: 'number', nullable}});
const columns = [number('id'), number('amount', true), number('n')];
const expected = [{id: 1, amount: null, n: 1},
  {id: 2, amount: 20, n: 1}, {id: 3, amount: 30, n: 2}];
const program = {version: 'actql/0.1', id: 'fixture.group_ordinal',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', group: {by: ['amount', 'id'],
      aggregates: {n: {fn: 'count'}}}},
    {select: ['id', 'amount', 'n']},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'amount', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const sql = 'SELECT id, amount, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY 2, 1 ORDER BY id';
const success = (name, format, text, overrides = {}) => ({
  name: 'group-ordinal-' + name, format, text, sourceRows: rows,
  expected, columns, sourceReadSessionCount: 1, ...overrides,
});
export const groupOrdinalSuccesses = [
  success('json-control', 'json', JSON.stringify(program)),
  success('sql', 'sql', sql),
  success('selected-expression-alias-collision', 'sql', 'SELECT -id AS id, -id AS copy, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY (+1) ORDER BY id', {
    expected: [{id: -3, copy: -3, n: 2}, {id: -2, copy: -2, n: 1}, {id: -1, copy: -1, n: 1}],
    columns: ['id', 'copy', 'n'].map(name => number(name)),
  }),
  success('expanded-star', 'sql', 'SELECT COUNT(*) AS n, * FROM records WHERE id > 0 GROUP BY 3, 2 ORDER BY id', {
    columns: [number('n'), number('amount', true), number('id')],
  }),
  success('star-and-literal', 'sql', 'SELECT *, 1 AS one FROM records WHERE id > 0 GROUP BY 2, 1 ORDER BY id', {
    expected: [{amount: null, id: 1, one: 1}, {amount: 20, id: 2, one: 1}, {amount: 30, id: 3, one: 1}],
    columns: [number('amount', true), number('id'), number('one')],
  }),
  success('cte', 'sql', 'WITH chosen AS (SELECT amount, id FROM records WHERE id > 0) SELECT id, amount, COUNT(*) AS n FROM chosen GROUP BY (2), 1 ORDER BY id'),
  success('scoped-join', 'sql', 'WITH a AS (SELECT 1 AS x, 20 AS y), b AS (SELECT 1 AS k), c AS (SELECT 1 AS z) SELECT *, COUNT(*) AS n FROM a JOIN b ON a.x = b.k JOIN c ON b.k = c.z GROUP BY 4, 3, 2, 1 ORDER BY x', {
    expected: [{x: 1, y: 20, k: 1, z: 1, n: 1}],
    columns: ['x', 'y', 'k', 'z', 'n'].map(name => number(name)),
    sourceReadSessionCount: 0,
  }),
  success('ordinary-arithmetic-key', 'sql', 'SELECT COUNT(*) AS n FROM records WHERE id > 0 GROUP BY 1 + 0 ORDER BY n', {
    expected: [{n: 4}], columns: [number('n')],
  }),
  success('empty', 'sql', sql, {sourceRows: [], expected: []}),
];

// Author-written common Program: one nullable computed value groups all three
// authored references. No compiler derives this control or its truth table.
const repeatedProgram = {version: 'actql/0.1', id: 'fixture.repeated_group_key',
  params: {increment: {type: 'number', nullable: false}},
  stages: [program.stages[0], {id: 'main',
    inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {key: {add: [{field: 'amount'}, {$param: 'increment'}]}}},
      {group: {by: ['key'], aggregates: {n: {fn: 'count'}}}},
      {select: [{bucket: 'key'}, 'n']},
      {sort: [{field: 'bucket', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['bucket', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const repeatedExpected = [{bucket: null, n: 1}, {bucket: 21, n: 1}, {bucket: 31, n: 2}];
const repeatedColumns = [number('bucket', true), number('n')];
const repeatedSql = 'SELECT amount + @increment AS bucket, COUNT(*) AS n FROM records '
  + 'WHERE id > 0 GROUP BY amount + @increment, (records.amount + @INCREMENT), 1 ORDER BY bucket';
export const repeatedGroupKeySuccesses = [
  success('repeated-key-json-control', 'json', JSON.stringify(repeatedProgram), {
    expected: repeatedExpected, columns: repeatedColumns, parameters: {increment: 1},
  }),
  success('repeated-key-expression-alias-ordinal', 'sql', repeatedSql, {
    expected: repeatedExpected, columns: repeatedColumns,
    parameterDeclarations: repeatedProgram.params, parameters: {increment: 1},
  }),
  success('repeated-key-direct', 'sql', 'SELECT id, amount, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY amount, id, records.amount, records.id, 2, 1 ORDER BY id'),
  success('repeated-key-star', 'sql', 'SELECT COUNT(*) AS n, * FROM records WHERE id > 0 GROUP BY 3, 2, id, amount, 3 ORDER BY id', {
    columns: [number('n'), number('amount', true), number('id')],
  }),
  success('repeated-key-alias-input-collision', 'sql', 'SELECT -amount AS amount, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY amount, -(records.amount), 1 ORDER BY amount NULLS LAST', {
    expected: [{amount: -30, n: 2}, {amount: -20, n: 1}, {amount: null, n: 1}],
    columns: [number('amount', true), number('n')],
  }),
  success('repeated-key-empty', 'sql', repeatedSql, {
    sourceRows: [], expected: [], columns: repeatedColumns,
    parameterDeclarations: repeatedProgram.params, parameters: {increment: 1},
  }),
  success('pipe-repeated-value-separate-names', 'aql-text', 'FROM records |> WHERE id > 0 |> AGGREGATE COUNT(*) AS n GROUP BY amount + 1 AS first, amount + 1 AS second |> ORDER BY first |> RESULT answer', {
    resultName: 'answer',
    expected: [{first: null, second: null, n: 1}, {first: 21, second: 21, n: 1}, {first: 31, second: 31, n: 2}],
    columns: [number('first', true), number('second', true), number('n')],
  }),
  success('repeated-key-distinct-property-receivers', 'aql-text', 'WITH objects AS (SELECT id, @p AS payload, CASE WHEN id = 1 THEN @a ELSE @b END AS other FROM records WHERE id > 0) '
    + 'SELECT payload.score AS score, other.score AS other, COUNT(*) AS n FROM objects GROUP BY payload.score, other.score, (objects.payload).score ORDER BY other', {
    expected: [{score: 1, other: 10, n: 1}, {score: 1, other: 20, n: 3}],
    columns: [number('score'), number('other'), number('n')],
    parameterDeclarations: Object.fromEntries(['p', 'a', 'b'].map(name => [name,
      {type: 'object', nullable: false, fields: {score: {type: 'number', nullable: false}}}])),
    parameters: {p: {score: 1}, a: {score: 10}, b: {score: 20}},
  }),
];
groupOrdinalSuccesses.push(...repeatedGroupKeySuccesses);
groupOrdinalSuccesses.push(...scalarAliasGroupSuccesses);
groupOrdinalSuccesses.push(...groupComparisonSuccesses);
export const groupOrdinalRefusals = [
  'SELECT id, amount FROM records GROUP BY 0',
  'SELECT *, COUNT(*) AS n FROM records GROUP BY 4',
  'SELECT id, COUNT(*) AS n FROM records GROUP BY 2',
  'SELECT id, amount FROM records GROUP BY 1.0',
  'SELECT id, amount FROM records GROUP BY TRUE',
  'FROM records |> AGGREGATE COUNT(*) AS n GROUP BY 1',
].map((text, index) => ({name: 'group-ordinal-invalid-' + index,
  format: 'aql-text', text, expectedCode: 'ClientProgramImplementationLimit'}))
  .concat(scalarAliasGroupRefusals, groupComparisonRefusals);
