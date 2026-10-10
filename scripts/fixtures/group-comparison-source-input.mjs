// Independent common Program and three-valued expectations, not source output.
const sourceRows = [{id: 3, amount: 20}, {id: 1, amount: 10},
  {id: 2, amount: null}, {id: 3, amount: 20}, {id: 0, amount: 99}];
const expected = [{flag: false, n: 1}, {flag: true, n: 2}, {flag: null, n: 1}];
const columns = [{name: 'flag', contract: {type: 'boolean', nullable: true}},
  {name: 'n', contract: {type: 'number', nullable: false}}];
export const groupComparisonProgram = {version: 'actql/0.1',
  id: 'fixture.group_comparison', stages: [
    {id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
        {select: ['amount', 'id'], as: 'captured'}],
      results: {source: {from: 'captured', fields: ['amount', 'id']}}},
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', derive: {key: {neq: [{field: 'amount'}, {literal: 10}]}}},
        {group: {by: ['key'], aggregates: {n: {fn: 'count'}}}},
        {select: [{flag: 'key'}, 'n']},
        {sort: [{field: 'flag', dir: 'asc', nulls: 'last'}], as: 'ordered'}],
      results: {rows: {from: 'ordered', fields: ['flag', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, extra = {}) => ({name: 'group-ordinal-comparison-' + name,
  format: 'sql', text, sourceRows, expected, columns, sourceReadSessionCount: 1, ...extra});
export const groupComparisonSuccesses = [
  success('json-control', JSON.stringify(groupComparisonProgram), {format: 'json'}),
  success('sql-key', 'SELECT amount != 10 AS flag, COUNT(*) AS n FROM records '
    + 'WHERE id > 0 GROUP BY amount <> 10 ORDER BY flag NULLS LAST'),
  success('reverse-spelling', 'SELECT records.amount <> 10 AS flag, COUNT(*) AS n FROM records '
    + 'WHERE id > 0 GROUP BY amount != 10 ORDER BY flag NULLS LAST'),
  success('repeated-key', 'SELECT amount != 10 AS flag, COUNT(*) AS n FROM records '
    + 'WHERE id > 0 GROUP BY amount <> 10, records.amount != 10 ORDER BY flag NULLS LAST'),
  success('output-collision', 'SELECT amount != 10 AS amount, COUNT(*) AS n FROM records '
    + 'WHERE id > 0 GROUP BY records.amount <> 10 ORDER BY amount NULLS LAST', {
    expected: [{amount: false, n: 1}, {amount: true, n: 2}, {amount: null, n: 1}],
    columns: [{...columns[0], name: 'amount'}, columns[1]],
  }),
  success('having-null', 'SELECT amount <> 10 AS flag, COUNT(*) AS n FROM records '
    + 'WHERE id > 0 GROUP BY amount <> 10 HAVING (records.amount != 10) IS NOT TRUE '
    + 'ORDER BY flag NULLS LAST', {expected: [{flag: false, n: 1}, {flag: null, n: 1}]}),
  success('pipe-control', 'FROM records |> WHERE id > 0 |> AGGREGATE COUNT(*) AS n '
    + 'GROUP BY amount <> 10 AS flag |> SELECT flag, n |> ORDER BY flag NULLS LAST',
    {format: 'aql-text'}),
  success('empty', 'SELECT amount != 10 AS flag, COUNT(*) AS n FROM records '
    + 'WHERE id > 0 GROUP BY amount <> 10 ORDER BY flag NULLS LAST',
    {sourceRows: [], expected: []}),
];
export const groupComparisonRefusals = [
  'SELECT id != 10 AS flag, COUNT(*) AS n FROM records GROUP BY amount <> 10',
  'SELECT amount = 10 AS flag, COUNT(*) AS n FROM records GROUP BY amount <> 10',
  'SELECT old.amount != 10 AS flag, COUNT(*) AS n FROM records AS current GROUP BY current.amount <> 10',
].map((text, index) => ({name: 'group-ordinal-comparison-invalid-' + index,
  format: 'sql', text, expectedCode: 'ClientProgramInvalidInput'}));
