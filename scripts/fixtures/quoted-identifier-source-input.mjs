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

// Common authored-name NFC/LF is separate from the exact STRING value law.
const canonicalNames = ['é', 'line\nname'];
const canonicalRows = [{'é': 1, 'line\nname': 2}];
export const canonicalQuotedIdentifierProgram = {version: 'actql/0.1',
  id: 'fixture.canonical_quoted_identifiers', stages: [{id: 'main', inputs: {},
    steps: [{as: 'authored', values: {
      schema: Object.fromEntries(canonicalNames.map(name => [name, number(name).contract])),
      rows: canonicalRows}}], results: {rows: {from: 'authored', fields: canonicalNames}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const canonical = (name, text, overrides = {}) => scalar('canonical-' + name, text, {
  expected: canonicalRows, columns: canonicalNames.map(number), ...overrides,
});
export const canonicalQuotedIdentifierSuccesses = [
  canonical('json-control', JSON.stringify(canonicalQuotedIdentifierProgram), {format: 'json'}),
  canonical('escaped-names', 'SELECT 1 AS `e\\u0301`, 2 AS `line\\rname`'),
  canonical('physical-names', 'SELECT 1 AS `e\u0301`, 2 AS `line\r\nname`'),
  canonical('sql-order', 'SELECT id AS `e\\u0301` FROM records ORDER BY `é`', {
    expected: [{'é': 1}, {'é': 2}, {'é': 3}, {'é': 3}], columns: [number('é')],
    sourceReadCount: undefined, sourceReadSessionCount: 1,
  }),
  canonical('pipe-rename-filter-order', 'FROM records |> SELECT id AS `é` '
    + '|> RENAME `e\\u0301` AS `line\\rname` |> WHERE `line\\nname` > 1 '
    + '|> ORDER BY `line\\rname`', {
    format: 'aql-text', expected: [{'line\nname': 2}, {'line\nname': 3}, {'line\nname': 3}],
    columns: [number('line\nname')], sourceReadCount: undefined, sourceReadSessionCount: 1,
  }),
  canonical('parameter', 'SELECT @`\\u0070` AS `e\\u0301`', {
    parameterDeclarations: {p: {type: 'number'}}, parameters: {p: 20},
    expected: [{'é': 20}], columns: [number('é')],
  }),
  canonical('exact-string-values', 'SELECT "e\\u0301\\r\\n" AS `e\\u0301`, "\\r" AS `line\\rname`', {
    expected: [{'é': 'e\u0301\r\n', 'line\nname': '\r'}],
    // e + U+0301 + CR + LF is 1 + 2 + 1 + 1 bytes; CR is one byte.
    columns: [{name: 'é', contract: {type: 'string', nullable: false, max_utf8_bytes: 5}},
      {name: 'line\nname', contract: {type: 'string', nullable: false, max_utf8_bytes: 1}}],
  }),
  canonical('empty', 'SELECT 1 AS `e\\u0301`, 2 AS `line\\rname` WHERE FALSE', {expected: []}),
  canonical('range', 'SELECT `é`.id AS `é` FROM records AS `e\\u0301` ORDER BY `e\\u0301`', {
    expected: [{'é': 1}, {'é': 2}, {'é': 3}, {'é': 3}], columns: [number('é')],
    sourceReadCount: undefined, sourceReadSessionCount: 1,
  }),
  canonical('cte', 'WITH `e\\u0301` AS (SELECT id FROM records) '
    + 'SELECT id AS `é` FROM `é` ORDER BY `e\\u0301`', {
    expected: [{'é': 1}, {'é': 2}, {'é': 3}, {'é': 3}], columns: [number('é')],
    sourceReadCount: undefined, sourceReadSessionCount: 1,
  }),
];
quotedIdentifierSuccesses.push(...canonicalQuotedIdentifierSuccesses);
export const canonicalQuotedIdentifierRefusals = [
  'SELECT id AS `é`, amount AS `e\\u0301` FROM records',
  'SELECT id AS `line\\nname`, amount AS `line\\rname` FROM records',
  'FROM records AS `e\\u0301` |> AS current |> SELECT `é`.id',
].map((text, index) => ({name: 'quoted-identifier-canonical-invalid-' + index,
  format: 'sql', text, expectedCode: 'ClientProgramInvalidInput'}));
quotedIdentifierRefusals.push(...canonicalQuotedIdentifierRefusals);
