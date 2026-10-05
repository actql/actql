// Values, column order and contracts are authored from the selected lexical
// rules and the ordinary Program contract, never from compiler output.
const number = name => ({name, contract: {type: 'number', nullable: false}});
const names = ['space name', 'line\nname', 'ÿ'];
const expected = [{'space name': 1, 'line\nname': 2, 'ÿ': 3}];
const columns = names.map(number);
const program = {version: 'actql/0.1', id: 'fixture.quoted_identifiers',
  stages: [{id: 'main', inputs: {}, steps: [{as: 'authored', values: {
    schema: Object.fromEntries(names.map(name => [name, number(name).contract])),
    rows: expected}}], results: {rows: {from: 'authored', fields: names}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const scalar = (name, text, overrides = {}) => ({
  name: 'quoted-identifier-' + name, format: 'sql', text,
  expected, columns, sourceReadCount: 0, ...overrides,
});
const sourceExpected = [{'space name': 1}, {'space name': 2},
  {'space name': 3}, {'space name': 3}];
export const quotedIdentifierSuccesses = [
  scalar('json-control', JSON.stringify(program), {format: 'json'}),
  scalar('octal', 'SELECT 1 AS `space\\040name`, 2 AS `line\\nname`, 3 AS `\\377`'),
  scalar('hex-unicode', 'SELECT 1 AS `space\\x20name`, 2 AS `line\\u000Aname`, 3 AS `\\U000000FF`'),
  scalar('physical-newline', 'SELECT 1 AS `space name`, 2 AS `line\r\nname`, 3 AS `ÿ`'),
  scalar('quote-and-control', 'SELECT 1 AS `a\\`b`, 2 AS `a\\tb`, 3 AS `a\\"b`', {
    expected: [{'a`b': 1, 'a\tb': 2, 'a"b': 3}],
    columns: ['a`b', 'a\tb', 'a"b'].map(number),
  }),
  scalar('sql-input-range', 'SELECT `r`.`\\151d` AS `space\\040name` FROM `\\162ecords` AS `\\162` ORDER BY `space\\x20name`', {
    expected: sourceExpected, columns: [number('space name')],
    sourceReadCount: undefined, sourceReadSessionCount: 1,
  }),
  scalar('pipe-input-range', 'FROM records |> AS `\\162` |> SELECT `r`.`\\151d` AS `space\\040name` |> ORDER BY `space\\x20name`', {
    format: 'aql-text', expected: sourceExpected, columns: [number('space name')],
    sourceReadCount: undefined, sourceReadSessionCount: 1,
  }),
  scalar('quoted-parameter', 'SELECT @`\\155inimum` AS `space\\040name`', {
    parameterDeclarations: {minimum: {type: 'number'}}, parameters: {minimum: 20},
    expected: [{'space name': 20}], columns: [number('space name')],
  }),
  scalar('empty-schema-retained', 'SELECT 1 AS `space\\040name` WHERE FALSE', {
    expected: [], columns: [number('space name')],
  }),
];
export const quotedIdentifierRefusals = [
  '\\400', '\\777', '\\00', '\\x4', '\\z', '\\uD800', '\\U00110000', '\\\n',
].map((escaped, index) => ({name: 'quoted-identifier-invalid-' + index,
  format: 'sql', text: 'SELECT 1 AS `a' + escaped + '`'}));
quotedIdentifierRefusals.push({name: 'quoted-identifier-empty',
  format: 'sql', text: 'SELECT 1 AS ``'});
