// Independent Unicode 16 default lowercase and Final_Sigma vectors.
const column = (name, type = 'string', nullable = false) => ({name, contract: {type, nullable}});
const columns = (...names) => names.map(name => column(name));
const control = {version: 'actql/0.1', id: 'fixture.lower', stages: [{
  id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'seed', derive: {value: {lower: {literal: 'ΟΣ'}}}},
    {select: ['value'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['value']}},
}], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, schema = [column('value')], extra = {}) => ({
  name: 'lower-' + name, format: 'sql', text, expected, columns: schema,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
const sourceRows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}];
const source = {sourceRows, sourceReadCount: undefined, sourceReadSessionCount: 1};
const sourceExpected = [{id: 1, value: null}, {id: 2, value: 'ος-20'},
  {id: 3, value: 'ος-30'}, {id: 3, value: 'ος-30'}];
const sourceColumns = [column('id', 'number'), column('value', 'string', true)];
const sourceText = "SELECT id, LOWER(CONCAT('ΟΣ-', CAST(amount AS STRING))) AS value FROM records ORDER BY id";
export const lowerSuccesses = [
  success('json-control', JSON.stringify(control), [{value: 'ος'}], undefined, {format: 'json'}),
  success('full-mapping-not-folding', "SELECT LOWER('İ ẞ ß ﬃ Ꭰ ǲ') AS value",
    [{value: 'i\u0307 ß ß ﬃ ꭰ ǳ'}]),
  success('sigma-context',
    "SELECT LOWER('Σ') AS isolated, LOWER('ΟΣ') AS final, LOWER('ΟΣΑ') AS medial, LOWER('ΣΣΣ') AS repeated",
    [{isolated: 'σ', final: 'ος', medial: 'οσα', repeated: 'σσς'}], columns('isolated', 'final', 'medial', 'repeated')),
  success('sigma-overlap-before', "SELECT LOWER('ͅΣ') AS alone, LOWER('AͅΣ') AS preceded",
    [{alone: '\u0345σ', preceded: 'a\u0345ς'}], columns('alone', 'preceded')),
  success('sigma-overlap-after', "SELECT LOWER('AΣͅ') AS final, LOWER('AΣͅB') AS medial, LOWER('AΣʰB') AS modifier",
    [{final: 'aς\u0345', medial: 'aσ\u0345b', modifier: 'aσʰb'}], columns('final', 'medial', 'modifier')),
  success('sigma-punctuation',
    "SELECT LOWER('AΣ.B') AS dot, LOWER('AΣ:B') AS colon, LOWER('AΣ,B') AS comma, LOWER('AΣ-B') AS dash",
    [{dot: 'aσ.b', colon: 'aσ:b', comma: 'aς,b', dash: 'aς-b'}], columns('dot', 'colon', 'comma', 'dash')),
  success('sigma-supplementary-nonletter', "SELECT LOWER('🄰Σ') AS before, LOWER('AΣ🄰') AS after",
    [{before: '🄰ς', after: 'aσ🄰'}], columns('before', 'after')),
  success('unicode-16-and-supplementary', "SELECT LOWER('𐐀') AS deseret, LOWER('𐵐') AS garay, LOWER('Ᲊ') AS cyrillic",
    [{deseret: '𐐨', garay: '𐵰', cyrillic: 'ᲊ'}], columns('deseret', 'garay', 'cyrillic')),
  success('no-normalization',
    "SELECT LOWER('E\\u0301') AS decomposed, LOWER('É') AS composed, LOWER('İ\\u0323') AS mark_order",
    [{decomposed: 'e\u0301', composed: 'é', mark_order: 'i\u0307\u0323'}], columns('decomposed', 'composed', 'mark_order')),
  success('locale-independent', "SELECT LOWER('I İ ı i I\\u0301 I\\u0307') AS value",
    [{value: 'i i\u0307 ı i i\u0301 i\u0307'}]),
  success('retained-text', "SELECT LOWER('日本😀!?\\r\\n') AS retained, LOWER('') AS empty",
    [{retained: '日本😀!?\r\n', empty: ''}], columns('retained', 'empty')),
  success('literal-null', 'SELECT LOWER(NULL) AS value, LOWER(CAST(NULL AS STRING)) AS typed_value',
    [{value: null, typed_value: null}], [column('value', 'string', true), column('typed_value', 'string', true)]),
  success('parameter-context', 'SELECT LOWER(@text) AS value', [{value: "aσ'b"}], undefined, {
    parameterDeclarations: {text: {type: 'string', nullable: false}}, parameters: {text: "AΣ'B"},
  }),
  success('nullable-parameter', 'SELECT LOWER(@text) AS value', [{value: null}], [column('value', 'string', true)], {
    parameterDeclarations: {text: {type: 'string', nullable: true}}, parameters: {text: null},
  }),
  success('sql-input', sourceText, sourceExpected, sourceColumns, source),
  success('pipe-input', "FROM records |> SELECT id, LOWER(CONCAT('ΟΣ-', CAST(amount AS STRING))) AS value |> ORDER BY id",
    sourceExpected, sourceColumns, {...source, format: 'aql-text'}),
  success('typed-empty', sourceText, [], sourceColumns, {...source, sourceRows: []}),
  success('lazy-operand', "SELECT IF(FALSE, LOWER(CAST(1 / 0 AS STRING)), 'safe') AS value", [{value: 'safe'}]),
  success('quoted-name', "SELECT `LoWeR`('ΟΣ') AS value", [{value: 'ος'}]),
];
export const lowerRefusals = [
  {name: 'zero-arguments', text: 'SELECT LOWER() AS value'},
  {name: 'two-arguments', text: "SELECT LOWER('a', 'b') AS value"},
  {name: 'number', text: 'SELECT LOWER(4) AS value'},
  {name: 'boolean', text: 'SELECT LOWER(CAST(TRUE AS BOOL)) AS value'},
  {name: 'decimal', text: "SELECT LOWER(CAST('4' AS DECIMAL(8,0))) AS value"},
  {name: 'number-parameter', text: 'SELECT LOWER(@value) AS value',
    parameterDeclarations: {value: {type: 'number', nullable: false}}, parameters: {value: 4}},
  {name: 'undeclared-parameter', text: 'SELECT LOWER(@missing) AS value'},
].map(value => ({...value, name: 'lower-' + value.name, format: 'sql', expectedCode: 'ClientProgramInvalidInput'}));
export const lowerExecutionFailures = [{
  name: 'lower-demanded-operand', text: 'SELECT LOWER(CAST(1 / 0 AS STRING)) AS value',
  format: 'sql', resultNames: ['main'], sourceReadSessionCount: 0,
}];
