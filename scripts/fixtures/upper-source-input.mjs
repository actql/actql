// Fixed expectations from Unicode 16 full default mappings, not host casing.
const column = (name, type = 'string', nullable = false) => ({name, contract: {type, nullable}});
const control = {version: 'actql/0.1', id: 'fixture.upper', stages: [{
  id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'seed', derive: {value: {upper: {literal: 'straße'}}}},
    {select: ['value'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['value']}},
}], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, columns = [column('value')], extra = {}) => ({
  name: 'upper-' + name, format: 'sql', text, expected, columns,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}];
const source = {sourceRows, sourceReadCount: undefined, sourceReadSessionCount: 1};
const sourceExpected = [{id: 1, value: null}, {id: 2, value: 'STRASSE-20'},
  {id: 3, value: 'STRASSE-30'}, {id: 3, value: 'STRASSE-30'}];
const sourceColumns = [column('id', 'number'), column('value', 'string', true)];
const sourceText = "SELECT id, UPPER(CONCAT('straße-', CAST(amount AS STRING))) AS value FROM records ORDER BY id";
export const upperSuccesses = [
  success('json-control', JSON.stringify(control), [{value: 'STRASSE'}], undefined, {format: 'json'}),
  success('full-expansions',
    "SELECT UPPER('straße') AS word, UPPER('ﬃ') AS ligature, UPPER('ᾀ') AS greek, UPPER('ΐ') AS marks",
    [{word: 'STRASSE', ligature: 'FFI', greek: 'ἈΙ', marks: 'Ϊ́'}],
    ['word', 'ligature', 'greek', 'marks'].map(name => column(name))),
  success('unicode-16-and-supplementary',
    "SELECT UPPER('𐐨') AS deseret, UPPER('𐵰') AS garay, UPPER('ᲊ') AS cyrillic",
    [{deseret: '𐐀', garay: '𐵐', cyrillic: 'Ᲊ'}],
    ['deseret', 'garay', 'cyrillic'].map(name => column(name))),
  success('no-normalization',
    "SELECT UPPER('e\\u0301') AS decomposed, UPPER('é') AS composed, UPPER('ǰ\\u0323') AS mark_order",
    [{decomposed: 'É', composed: 'É', mark_order: 'J̣̌'}],
    ['decomposed', 'composed', 'mark_order'].map(name => column(name))),
  success('locale-independent', "SELECT UPPER('i I ı İ i\\u0307 σ ς Σ') AS value",
    [{value: 'I I I İ İ Σ Σ Σ'}]),
  success('not-titlecase-or-lowercase', "SELECT UPPER('ǳ') AS digraph, UPPER('ẞ') AS capital",
    [{digraph: 'Ǳ', capital: 'ẞ'}], [column('digraph'), column('capital')]),
  success('retained-text', "SELECT UPPER('日本😀!?\\r\\n') AS retained, UPPER('') AS empty",
    [{retained: '日本😀!?\r\n', empty: ''}], [column('retained'), column('empty')]),
  success('literal-null', 'SELECT UPPER(NULL) AS value, UPPER(CAST(NULL AS STRING)) AS typed_value',
    [{value: null, typed_value: null}], [column('value', 'string', true), column('typed_value', 'string', true)]),
  success('parameter', 'SELECT UPPER(@text) AS value', [{value: 'STRASSE'}], undefined, {
    parameterDeclarations: {text: {type: 'string', nullable: false}}, parameters: {text: 'straße'},
  }),
  success('nullable-parameter', 'SELECT UPPER(@text) AS value', [{value: null}], [column('value', 'string', true)], {
    parameterDeclarations: {text: {type: 'string', nullable: true}}, parameters: {text: null},
  }),
  success('sql-input', sourceText, sourceExpected, sourceColumns, source),
  success('pipe-input', "FROM records |> SELECT id, UPPER(CONCAT('straße-', CAST(amount AS STRING))) AS value |> ORDER BY id",
    sourceExpected, sourceColumns, {...source, format: 'aql-text'}),
  success('typed-empty', sourceText, [], sourceColumns, {...source, sourceRows: []}),
  success('lazy-operand', "SELECT IF(FALSE, UPPER(CAST(1 / 0 AS STRING)), 'safe') AS value", [{value: 'safe'}]),
  success('quoted-name', "SELECT `UpPeR`('straße') AS value", [{value: 'STRASSE'}]),
];
export const upperRefusals = [
  {name: 'zero-arguments', text: 'SELECT UPPER() AS value'},
  {name: 'two-arguments', text: "SELECT UPPER('a', 'b') AS value"},
  {name: 'number', text: 'SELECT UPPER(4) AS value'},
  {name: 'boolean', text: 'SELECT UPPER(CAST(TRUE AS BOOL)) AS value'},
  {name: 'decimal', text: "SELECT UPPER(CAST('4' AS DECIMAL(8,0))) AS value"},
  {name: 'number-parameter', text: 'SELECT UPPER(@value) AS value',
    parameterDeclarations: {value: {type: 'number', nullable: false}}, parameters: {value: 4}},
  {name: 'undeclared-parameter', text: 'SELECT UPPER(@missing) AS value'},
].map(value => ({...value, name: 'upper-' + value.name, format: 'sql', expectedCode: 'ClientProgramInvalidInput'}));
export const upperExecutionFailures = [{
  name: 'upper-demanded-operand', text: 'SELECT UPPER(CAST(1 / 0 AS STRING)) AS value',
  format: 'sql', resultNames: ['main'], sourceReadSessionCount: 0,
}];
