// Expectations follow literal, non-overlapping, retained-value replacement.
// They are not calculated by the compiler or by the product's String helpers.
const column = (name, type = 'string', nullable = false) => ({name, contract: {type, nullable}});
export const replaceCallProgram = {version: 'actql/0.1', id: 'fixture.replace', stages: [{
  id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'seed', derive: {value: {replace: [{literal: 'banana'}, {literal: 'ana'}, {literal: 'X'}]}}},
    {select: ['value'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['value']}},
}], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, columns = [column('value')], extra = {}) => ({
  name: 'replace-call-' + name, format: 'sql', text, expected, columns,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 0, amount: 99}];
const source = {sourceRows, sourceReadCount: undefined, sourceReadSessionCount: 1};
const inputColumns = [column('id', 'number'), column('value', 'string', true)];
const inputText = "SELECT id, REPLACE(CAST(amount AS STRING), '2', 'X') AS value "
  + 'FROM records WHERE id > 0 ORDER BY id';
const declarations = {value: {type: 'string', nullable: true},
  pattern: {type: 'string', nullable: false}, replacement: {type: 'string', nullable: false}};
export const replaceCallSuccesses = [
  success('independent-json', JSON.stringify(replaceCallProgram), [{value: 'bXna'}],
    undefined, {format: 'json'}),
  success('non-overlapping-all-occurrences', "SELECT REPLACE('banana banana', 'ana', 'X') AS value",
    [{value: 'bXna bXna'}]),
  success('empty-search-and-replacement', "SELECT REPLACE('aba', '', 'X') AS unchanged, "
    + "REPLACE('banana', 'ana', '') AS removed", [{unchanged: 'aba', removed: 'bna'}],
    [column('unchanged'), column('removed')]),
  success('unicode-and-line-endings', "SELECT REPLACE('e\\u0301\\r\\n', '', 'X') AS decomposed, "
    + "REPLACE('é', 'e\\u0301', 'X') AS composed, REPLACE('a\\r\\nb', '\\r', 'R') AS lines",
    [{decomposed: 'é\r\n', composed: 'é', lines: 'aR\nb'}],
    [column('decomposed'), column('composed'), column('lines')]),
  success('null-operands', "SELECT REPLACE(CAST(NULL AS STRING), 'a', 'b') AS original, "
    + "REPLACE('a', CAST(NULL AS STRING), 'b') AS pattern, "
    + "REPLACE('a', 'a', CAST(NULL AS STRING)) AS replacement",
    [{original: null, pattern: null, replacement: null}],
    [column('original', 'string', true), column('pattern', 'string', true),
      column('replacement', 'string', true)]),
  success('parameters', 'SELECT REPLACE(@value, @pattern, @replacement) AS value',
    [{value: 'bXna'}], [column('value', 'string', true)], {
      parameterDeclarations: declarations, parameters: {value: 'banana', pattern: 'ana', replacement: 'X'},
    }),
  success('nullable-parameter', 'SELECT REPLACE(@value, @pattern, @replacement) AS value',
    [{value: null}], [column('value', 'string', true)], {
      parameterDeclarations: declarations, parameters: {value: null, pattern: 'ana', replacement: 'X'},
    }),
  success('input-null-and-duplicates', inputText,
    [{id: 1, value: null}, {id: 2, value: 'X0'}, {id: 3, value: '30'}, {id: 3, value: '30'}],
    inputColumns, source),
  success('current-and-qualified-original', 'FROM records AS before |> WHERE id > 0 '
    + "|> SET amount = amount + 1 |> SELECT id, REPLACE(CAST(amount AS STRING), '2', 'X') AS current_value, "
    + "REPLACE(CAST(before.amount AS STRING), '2', 'X') AS original_value |> ORDER BY id",
    [{id: 1, current_value: null, original_value: null}, {id: 2, current_value: 'X1', original_value: 'X0'},
      {id: 3, current_value: '31', original_value: '30'}, {id: 3, current_value: '31', original_value: '30'}],
    [column('id', 'number'), column('current_value', 'string', true),
      column('original_value', 'string', true)], {...source, format: 'aql-text'}),
  success('typed-empty', inputText, [], inputColumns, {...source, sourceRows: []}),
  success('lazy-conditional', "SELECT IF(FALSE, REPLACE(CAST(1 / 0 AS STRING), 'x', 'y'), 'safe') AS value",
    [{value: 'safe'}]),
];
export const replaceCallRefusals = [
  "SELECT REPLACE('a', 'b') AS value",
  "SELECT REPLACE('a', 'b', 'c', 'd') AS value",
  "SELECT REPLACE(1, 'a', 'b') AS value",
  "SELECT REPLACE('a', unknown_function('b'), 'c') AS value",
  "SELECT REPLACE(@missing, 'a', 'b') AS value",
  "SELECT ACTQL.REPLACE('a', 'b', 'c') AS value",
  "SELECT REPLACE(JSON '\"abc\"', 'a', 'b') AS value",
].map((text, index) => ({name: 'replace-call-refuse-' + index, format: 'sql', text}));
export const replaceCallExecutionFailures = [{name: 'replace-call-demanded-failure', format: 'sql',
  text: "SELECT REPLACE(CAST(1 / 0 AS STRING), 'x', 'y') AS value",
  resultNames: ['answer'], sourceReadSessionCount: 0}];
