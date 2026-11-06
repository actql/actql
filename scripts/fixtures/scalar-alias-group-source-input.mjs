// Author-written Programs and result contracts, never compiler output.
// The supplementary Unicode scalar makes character and byte counts differ.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const declarations = Object.fromEntries(['a', 'b', 'c'].map(name => [name,
  {type: 'string', nullable: true}]));
const parameters = {a: null, b: 'e\u0301', c: '😀'};
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 0, amount: 99}];
const capture = {id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
  steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
    {select: ['amount', 'id'], as: 'captured'}],
  results: {source: {from: 'captured', fields: ['amount', 'id']}}};
export const scalarAliasGroupProgram = {version: 'actql/0.1',
  id: 'fixture.scalar_alias_group', params: declarations, stages: [capture,
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', derive: {name: {if: [
        {eq: [{field: 'id'}, {literal: 1}]}, {$param: 'a'},
        {if: [{eq: [{field: 'id'}, {literal: 2}]}, {$param: 'b'}, {$param: 'c'}]},
      ]}}},
      {derive: {key: {len: {field: 'name'}}}},
      {group: {by: ['key'], aggregates: {n: {fn: 'count'}}}},
      {derive: {total: {add: [{field: 'n'}, {field: 'key'}]}}},
      {select: [{width: 'key'}, 'total']},
      {sort: [{field: 'width', dir: 'asc', nulls: 'last'}], as: 'ordered'}],
      results: {rows: {from: 'ordered', fields: ['width', 'total']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const expected = [{width: 1, total: 3}, {width: 2, total: 3},
  {width: null, total: null}];
const columns = ['width', 'total'].map(name => ({name, contract: nullableNumber}));
const prefix = 'WITH texts AS (SELECT id, CASE WHEN id = 1 THEN @a WHEN id = 2 '
  + 'THEN @b ELSE @c END AS name FROM records WHERE id > 0) ';
const sql = 'SELECT CHAR_LENGTH(name) AS width, COUNT(*) + CHARACTER_LENGTH(texts.name) '
  + 'AS total FROM texts GROUP BY CHAR_LENGTH(name) ORDER BY width NULLS LAST';
const success = (name, text, extra = {}) => ({name: 'group-ordinal-scalar-alias-' + name,
  format: 'aql-text', text: prefix + text, sourceRows, parameterDeclarations: declarations,
  parameters, expected, columns, sourceReadSessionCount: 1, ...extra});
const roundedRows = [{id: 3, amount: 1.8}, {id: 1, amount: null},
  {id: 2, amount: -1.2}, {id: 4, amount: 1.4}, {id: 0, amount: 99}];
export const scalarAliasCeilingProgram = {version: 'actql/0.1',
  id: 'fixture.scalar_alias_ceiling', stages: [capture,
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', derive: {key: {negate: {floor: {
        subtract: [{literal: 0}, {field: 'amount'}],
      }}}}},
        {group: {by: ['key'], aggregates: {n: {fn: 'count'}}}},
        {select: [{bucket: 'key'}, 'n']},
        {sort: [{field: 'bucket', dir: 'asc', nulls: 'last'}], as: 'ordered'}],
      results: {rows: {from: 'ordered', fields: ['bucket', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const roundedExpected = [{bucket: -1, n: 1}, {bucket: 2, n: 2}, {bucket: null, n: 1}];
const roundedColumns = [{name: 'bucket', contract: nullableNumber},
  {name: 'n', contract: number}];
const rounded = {sourceRows: roundedRows, expected: roundedExpected,
  columns: roundedColumns, parameterDeclarations: undefined, parameters: undefined};
export const scalarAliasGroupSuccesses = [
  success('json-control', JSON.stringify(scalarAliasGroupProgram), {format: 'json',
    text: JSON.stringify(scalarAliasGroupProgram), parameterDeclarations: undefined}),
  success('sql-group-key', sql),
  success('quoted-aliases', 'SELECT `CHARACTER_LENGTH`(name) AS width, '
    + 'COUNT(*) + `CHAR_LENGTH`(texts.name) AS total FROM texts '
    + 'GROUP BY `CHAR_LENGTH`(name) ORDER BY width NULLS LAST'),
  success('pipe-key', 'FROM texts |> AGGREGATE COUNT(*) AS n GROUP BY CHAR_LENGTH(name) AS width '
    + '|> SELECT width, n + width AS total |> ORDER BY width NULLS LAST |> RESULT answer', {resultName: 'answer'}),
  success('typed-empty', sql, {sourceRows: [], expected: []}),
  success('ceiling-json-control', JSON.stringify(scalarAliasCeilingProgram), {...rounded,
    format: 'json', text: JSON.stringify(scalarAliasCeilingProgram)}),
  success('ceiling-sql-key', 'SELECT CEILING(amount) AS bucket, COUNT(*) AS n FROM records '
    + 'WHERE id > 0 GROUP BY CEIL(amount) ORDER BY bucket NULLS LAST', {...rounded,
    text: 'SELECT CEILING(amount) AS bucket, COUNT(*) AS n FROM records '
      + 'WHERE id > 0 GROUP BY CEIL(amount) ORDER BY bucket NULLS LAST'}),
  success('ceiling-pipe-key', 'FROM records |> WHERE id > 0 |> AGGREGATE COUNT(*) AS n '
    + 'GROUP BY CEILING(amount) AS bucket |> ORDER BY bucket NULLS LAST', {...rounded,
    text: 'FROM records |> WHERE id > 0 |> AGGREGATE COUNT(*) AS n '
      + 'GROUP BY CEILING(amount) AS bucket |> ORDER BY bucket NULLS LAST'}),
];
export const scalarAliasGroupRefusals = [
  'SELECT CHAR_LENGTH(id) AS n FROM texts GROUP BY CHAR_LENGTH(name)',
  'SELECT CHAR_LENGTH(old.name) AS n FROM texts AS current GROUP BY CHARACTER_LENGTH(current.name)',
  'SELECT CHARACTER_LENGTH(name, name) AS n FROM texts GROUP BY CHAR_LENGTH(name)',
].map((tail, index) => ({name: 'group-ordinal-scalar-alias-invalid-' + index,
  format: 'aql-text', text: prefix + tail, parameterDeclarations: declarations, parameters,
  expectedCode: 'ClientProgramInvalidInput'}));
