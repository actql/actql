// Independent decimal values, ordered columns and multiplicities. Never derive
// expectations from lexer/lowerer output or an installed runtime.
const column = (name, nullable = false) => ({name, contract: {type: 'number', nullable}});
export const hexIntegerProgram = {version: 'actql/0.1', id: 'fixture.hex_integer',
  stages: [{id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'seed', derive: {value: {literal: 16}}},
    {select: ['value'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['value']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, columns, extra = {}) => ({
  name: 'hex-integer-' + name, format: 'sql', text, expected, columns,
  sourceReadSessionCount: 0, ...extra,
});
export const hexIntegerSuccesses = [
  success('independent-json', JSON.stringify(hexIntegerProgram), [{value: 16}],
    [column('value')], {format: 'json'}),
  success('scalars', 'SELECT 0x0 AS zero, +0X10 AS positive, -0x1f AS negative, 0x1fffffffffffff AS maximum',
    [{zero: 0, positive: 16, negative: -31, maximum: 9007199254740991}],
    ['zero', 'positive', 'negative', 'maximum'].map(name => column(name))),
  success('empty-typed', 'SELECT 0X10 AS value WHERE FALSE', [], [column('value')]),
  success('pipe-predicate', 'SELECT 0x10 AS value |> WHERE value = 0X10 |> SELECT value |> LIMIT 0x1',
    [{value: 16}], [column('value')], {format: 'aql-text'}),
  success('set-position-limit-offset', 'SELECT 0x2 AS id UNION ALL SELECT 0x1 AS id UNION ALL SELECT 0x1 AS id ORDER BY 0x1 LIMIT 0x2 OFFSET 0X1',
    [{id: 1}, {id: 2}], [column('id')]),
  success('group-position', 'SELECT id, COUNT(*) AS n FROM records WHERE id > 0x0 GROUP BY 0x1 ORDER BY 0X1 LIMIT 0x2',
    [{id: 1, n: 2}, {id: 2, n: 1}], [column('id'), column('n')], {
      sourceRows: [{id: 2, amount: null}, {id: 1, amount: 2}, {id: 1, amount: 3}, {id: 0, amount: 4}],
      sourceReadSessionCount: 1,
    }),
  success('navigation-offset', 'SELECT id, LAG(amount, 0x1) OVER (ORDER BY id) AS previous FROM records WHERE id > 0x0 ORDER BY id',
    [{id: 1, previous: null}, {id: 2, previous: 10}, {id: 3, previous: null}],
    [column('id'), column('previous', true)], {
      hostProfile: 'analytic-offset', sourceReadSessionCount: 1,
      sourceRows: [{id: 3, amount: 30}, {id: 1, amount: 10}, {id: 2, amount: null}],
    }),
];
export const hexIntegerRefusals = [
  'SELECT 0x AS value', 'SELECT 0xG AS value', 'SELECT 0x1p1 AS value',
  'SELECT 0x20000000000000 AS value', 'SELECT -0X0 AS value',
  'SELECT 1 AS value LIMIT 0x20000000000000',
  'SELECT 1 AS value ORDER BY 0x2',
].map((text, index) => ({name: 'hex-integer-refuse-' + index, format: 'sql', text, expectedCode: 'ClientProgramInvalidInput'}));
