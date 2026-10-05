// Independent machine input and expected delivery values. No runtime imports.
const json = value => ({typed_literal: {type: 'json', value}});
const fields = ['json_null', 'sql_null', 'json_number', 'number', 'json_string',
  'string', 'json_boolean', 'boolean', 'json_object', 'json_array'];
const expressions = {
  json_null: json('null'), json_number: json('1.5'), number: {literal: 1.5},
  json_string: json('"x"'), string: {literal: 'x'},
  json_boolean: json('true'), boolean: {literal: true},
  json_object: json('{"a":1,"a":2,"e\\u0301":null}'),
  json_array: json('[null,false]'),
};
const program = (bindings = expressions, empty = false) => ({version: 'actql/0.1',
  id: 'typed-json-literals', stages: [{id: 's', inputs: {}, steps: [
    {as: 'seed', values: {schema: {sql_null: {type: 'json', nullable: true}},
      rows: [{sql_null: null}]}},
    {as: 'typed', derive: bindings},
    ...(empty ? [{as: 'empty', filter: {literal: false}}] : []),
  ], results: {out: {from: empty ? 'empty' : 'typed', fields}}}],
  results: {answer: {from: {stage: 's', result: 'out'}}}});
const columns = fields.map(name => ({name, contract: {type:
  name.startsWith('json_') || name === 'sql_null' ? 'json' : name,
nullable: name === 'sql_null', ...(name === 'string' ? {max_bytes: 1} : {})}}));
const expected = [{json_null: {$json: null}, sql_null: null,
  json_number: {$json: 1.5}, number: 1.5, json_string: {$json: 'x'}, string: 'x',
  json_boolean: {$json: true}, boolean: true,
  json_object: {$json: {a: 1, 'e\u0301': null}}, json_array: {$json: [null, false]}}];
export const typedJsonLiteralSuccesses = [
  {name: 'typed-json-all-roots-and-sql-null', format: 'json',
    text: JSON.stringify(program()), expected, columns, sourceReadCount: 0},
  {name: 'typed-json-empty-result-schema', format: 'json',
    text: JSON.stringify(program(expressions, true)), expected: [], columns, sourceReadCount: 0},
];
export const typedJsonLiteralRefusals = [
  ['numeric-precision-loss', '9007199254740993'],
  ['numeric-overflow', '1e400'],
  ['malformed-json', '{"a":}'],
  ['json-depth', '['.repeat(501) + 'null' + ']'.repeat(501)],
].map(([name, value]) => ({name: 'typed-json-' + name, format: 'json',
  text: JSON.stringify(program({...expressions, json_null: json(value)}))}));
