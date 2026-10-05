// Independently authored source and delivery/schema expectations. No compiler imports.
const source = `SELECT JSON 'null' AS json_null, CAST(NULL AS FLOAT64) AS sql_null,
  JSON '1.5' AS json_number, 1.5 AS number,
  JSON '"x"' AS json_string, 'x' AS string,
  JSON 'true' AS json_boolean, TRUE AS boolean,
  JSON '{"a":1,"a":2,"e\\\\u0301":null}' AS json_object,
  JSON '[null,false]' AS json_array`;
const names = ['json_null', 'sql_null', 'json_number', 'number', 'json_string',
  'string', 'json_boolean', 'boolean', 'json_object', 'json_array'];
const columns = names.map(name => ({name, contract: {
  type: name.startsWith('json_') ? 'json' : name === 'sql_null' ? 'number' : name,
  nullable: name === 'sql_null', ...(name === 'string' ? {max_utf8_bytes: 1} : {}),
}}));
const expected = [{json_null: {$json: null}, sql_null: null,
  json_number: {$json: 1.5}, number: 1.5, json_string: {$json: 'x'}, string: 'x',
  json_boolean: {$json: true}, boolean: true,
  json_object: {$json: {a: 1, 'e\u0301': null}}, json_array: {$json: [null, false]}}];
export const jsonLiteralSourceSuccesses = [
  {name: 'json-source-all-roots-and-sql-null', text: source, expected, columns, sourceReadCount: 0},
  {name: 'json-source-empty-schema', text: source + ' WHERE FALSE', expected: [], columns,
    sourceReadCount: 0},
  {name: 'json-source-null-is-data', text:
    `SELECT JSON 'null' AS j |> WHERE j IS NOT NULL |> SELECT j`,
  expected: [{j: {$json: null}}], columns: [{name: 'j', contract: {type: 'json', nullable: false}}],
  sourceReadCount: 0},
];
export const jsonLiteralSourceRefusals = [
  ['precision-loss', "SELECT JSON '9007199254740993' AS j"],
  ['overflow', "SELECT JSON '1e400' AS j"],
  ['malformed-json', `SELECT JSON '{"a":}' AS j`],
  ['json-depth', "SELECT JSON '" + '['.repeat(501) + 'null' + ']'.repeat(501) + "' AS j"],
].map(([name, text]) => ({name: 'json-source-' + name, text, sourceReadCount: 0}));
