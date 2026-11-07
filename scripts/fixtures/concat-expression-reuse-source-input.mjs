// Independent strict-STRING concatenation examples. Reversed operands, legacy
// NULL skipping and rebound receivers are deliberately not equivalences.
const rows = [{id: 2, amount: 2}, {id: 1, amount: 1},
  {id: 3, amount: 2}, {id: 4, amount: null}, {id: 0, amount: 99}];
const number = {type: 'number', nullable: false};
const string = {type: 'string', nullable: true};
const valueColumn = {name: 'value', contract: string};
const groupedColumns = [valueColumn, {name: 'n', contract: number}];
const grouped = [{value: 'az', n: 1}, {value: 'za', n: 2}, {value: null, n: 1}];
const distinct = [{value: 'az'}, {value: 'za'}, {value: null}];
const fields = {
  x: {case: {when: [{when: {eq: [{field: 'amount'}, {literal: 2}]},
    then: {literal: 'z'}}], else: {literal: 'a'}}},
  y: {case: {when: [{when: {is_null: {field: 'amount'}},
    then: {cast: {value: {literal: null}, target: {type: 'string'}}}},
  {when: {eq: [{field: 'amount'}, {literal: 2}]}, then: {literal: 'a'}}],
  else: {literal: 'z'}}},
};
const prefix = 'WITH pieces AS (SELECT id, '
  + "CASE WHEN amount = 2 THEN 'z' ELSE 'a' END AS x, "
  + "CASE WHEN amount IS NULL THEN CAST(NULL AS STRING) WHEN amount = 2 THEN 'a' ELSE 'z' END AS y "
  + 'FROM records WHERE id > 0) ';
const program = tail => ({version: 'actql/0.1', id: 'fixture.concat_expression_reuse',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: fields}, {select: ['id', 'x', 'y']},
      ...tail.steps], results: {rows: {from: 'ordered', fields: tail.columns}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}});
const concat = {concat_strict: [{field: 'x'}, {field: 'y'}]};
export const concatGroupProgram = program({steps: [{derive: {value: concat}},
  {group: {by: ['value'], aggregates: {n: {fn: 'count'}}}},
  {select: ['value', 'n']},
  {sort: [{field: 'value', dir: 'asc', nulls: 'last'}], as: 'ordered'}],
columns: ['value', 'n']});
export const concatDistinctProgram = program({steps: [{derive: {value: concat}},
  {select: ['value']}, {distinct: ['value']},
  {sort: [{field: 'value', dir: 'asc', nulls: 'last'}], as: 'ordered'}],
columns: ['value']});
const success = (name, query, expected, columns = groupedColumns, extra = {}) => ({
  name: 'concat-reuse-' + name, format: 'aql-text', text: prefix + query,
  sourceRows: rows, expected, columns, sourceReadSessionCount: 1, ...extra,
});
const groupedSql = (selected, key) => `SELECT ${selected} AS value, COUNT(*) AS n FROM pieces `
  + `GROUP BY ${key} ORDER BY value NULLS LAST`;
const distinctSql = (selected, ordered) => `SELECT DISTINCT ${selected} AS value FROM pieces `
  + `ORDER BY ${ordered} NULLS LAST`;
const collision = ordered => 'SELECT id, CONCAT(x,y) AS original, y AS x FROM pieces '
  + `ORDER BY ${ordered} NULLS LAST, id`;
const collisionColumns = [{name: 'id', contract: number},
  {name: 'original', contract: string}, {name: 'x', contract: string}];
const collisionRows = [{id: 2, original: 'za', x: 'a'}, {id: 3, original: 'za', x: 'a'},
  {id: 1, original: 'az', x: 'z'}, {id: 4, original: null, x: null}];
export const concatReuseSuccesses = [
  success('group-json-control', '', grouped, groupedColumns,
    {format: 'json', text: JSON.stringify(concatGroupProgram)}),
  success('group-function-key', groupedSql('x || y', 'CONCAT(x,y)'), grouped),
  success('group-operator-key', groupedSql('CONCAT(x,y)', 'x || y'), grouped),
  success('group-quoted', groupedSql('`concat`((pieces.x),y)', '(x) || (pieces.y)'), grouped),
  success('group-limit-offset', groupedSql('CONCAT(x,y)', 'x || y') + ' LIMIT 1 OFFSET 1',
    [{value: 'za', n: 2}]),
  success('group-empty', groupedSql('x || y', 'CONCAT(x,y)'), [], groupedColumns, {sourceRows: []}),
  success('distinct-json-control', '', distinct, [valueColumn],
    {format: 'json', text: JSON.stringify(concatDistinctProgram)}),
  success('distinct-function-selected', distinctSql('CONCAT(x,y)', 'x || y'), distinct, [valueColumn]),
  success('distinct-operator-selected', distinctSql('x || y', 'CONCAT(x,y)'), distinct, [valueColumn]),
  success('distinct-pipe-function', 'FROM pieces |> SELECT DISTINCT CONCAT(x,y) AS value '
    + '|> ORDER BY x || y NULLS LAST', distinct, [valueColumn]),
  success('distinct-pipe-operator', 'FROM pieces |> SELECT DISTINCT x || y AS value '
    + '|> ORDER BY `concat`(pieces.x,y) NULLS LAST', distinct, [valueColumn]),
  success('distinct-empty', distinctSql('CONCAT(x,y)', 'x || y'), [], [valueColumn], {sourceRows: []}),
  success('output-alias-receiver', collision('x || y'), collisionRows, collisionColumns),
  success('qualified-input-receiver', collision('pieces.x || y'),
    [collisionRows[2], collisionRows[0], collisionRows[1], collisionRows[3]], collisionColumns),
];
// Different operands, arity and receivers are outside the selected DISTINCT
// scope. Preserve the existing common InvalidQuery refusal.
export const concatReuseRefusals = [
  distinctSql('CONCAT(x,y)', 'y || x'),
  distinctSql('x || y', 'ACTQL.CONCAT(x,y)'),
  distinctSql("CONCAT(x,y,'')", 'x || y'),
  'SELECT DISTINCT CONCAT(x,y) AS x FROM pieces ORDER BY x || y',
].map((query, i) => ({name: 'concat-reuse-unproven-' + i,
  format: 'aql-text', text: prefix + query, expectedCode: 'ClientProgramInvalidInput'}));
