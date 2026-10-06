// Expectations count retained Unicode scalars, not UTF-8 bytes, UTF-16 code
// units or grapheme clusters. They are written independently of product len.
const column = (name, nullable = false) => ({name, contract: {type: 'number', nullable}});
const control = {version: 'actql/0.1', id: 'fixture.character_length', stages: [{
  id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'seed', derive: {n: {len: {literal: 'e\u0301😀'}}}},
    {select: ['n'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['n']}},
}], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, columns, extra = {}) => ({
  name: 'character-length-' + name, format: 'sql', text, expected, columns,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
export const characterLengthSuccesses = [
  success('json-control', JSON.stringify(control), [{n: 3}], [column('n')], {format: 'json'}),
  success('retained-unicode',
    "SELECT CHAR_LENGTH('é') AS composed, CHARACTER_LENGTH('e\\u0301') AS decomposed, "
      + "CHAR_LENGTH('\\U0001F600') AS supplementary, LENGTH('e\\u0301\\U0001F600') AS existing",
    [{composed: 1, decomposed: 2, supplementary: 1, existing: 3}],
    ['composed', 'decomposed', 'supplementary', 'existing'].map(name => column(name))),
  success('empty-and-null', "SELECT CHAR_LENGTH('') AS empty, CHARACTER_LENGTH(NULL) AS unknown",
    [{empty: 0, unknown: null}], [column('empty'), column('unknown', true)]),
  success('pipe-parameter', 'SELECT @text AS value |> SELECT character_length(value) AS n',
    [{n: 3}], [column('n', true)], {format: 'aql-text',
      parameterDeclarations: {text: {type: 'string', nullable: true, max_utf8_bytes: 16}},
      parameters: {text: 'e\u0301😀'}}),
  success('empty-result', "SELECT CHAR_LENGTH('é') AS n WHERE FALSE", [], [column('n')]),
  success('nullable-row',
    'SELECT id, CHAR_LENGTH(CAST(amount AS STRING)) AS n FROM records ORDER BY id',
    [{id: 1, n: null}, {id: 2, n: 2}, {id: 3, n: 2}, {id: 3, n: 2}],
    [column('id'), column('n', true)], {sourceReadCount: undefined, sourceReadSessionCount: 1}),
];
export const characterLengthRefusals = [
  'SELECT CHAR_LENGTH() AS n',
  "SELECT CHARACTER_LENGTH('a', 'b') AS n",
  'SELECT CHAR_LENGTH(1) AS n',
  'SELECT CHARACTER_LENGTH(@missing) AS n',
].map((text, index) => ({name: 'character-length-refusal-' + index, format: 'sql', text}));
