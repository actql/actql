// Independent existing boolean CAST expectations; source aliases do not add a
// conversion rule or turn a failed cast into NULL.
const column = (name, nullable = false) => ({name, contract: {type: 'boolean', nullable}});
const cast = value => ({cast: {value: {literal: value}, target: {type: 'boolean'}}});
const control = {version: 'actql/0.1', id: 'fixture.boolean-cast', stages: [{
  id: 'main', inputs: {}, steps: [
    {as: 'seed', values: {schema: {unit: {type: 'boolean', nullable: false}}, rows: [{unit: true}]}},
    {from: 'seed', derive: {flag: cast(true), missing: cast(null)}},
    {select: ['flag', 'missing'], as: 'selected'},
  ], results: {rows: {from: 'selected', fields: ['flag', 'missing']}},
}], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, text, expected, columns, extra = {}) => ({
  name: 'boolean-cast-' + name, format: 'sql', text, expected, columns,
  sourceReadCount: 0, sourceReadSessionCount: 0, ...extra,
});
const pair = [{flag: true, missing: null}];
const columns = [column('flag'), column('missing', true)];
export const booleanCastSuccesses = [
  success('json-control', JSON.stringify(control), pair, columns, {format: 'json'}),
  success('canonical-bool', 'SELECT CAST(TRUE AS BOOL) AS flag, CAST(NULL AS BOOL) AS missing', pair, columns),
  success('alias-boolean', 'SELECT CAST(TRUE AS BOOLEAN) AS flag, CAST(NULL AS BOOLEAN) AS missing', pair, columns),
  success('mixed-case', 'SELECT CAST(FALSE AS bOoLeAn) AS flag', [{flag: false}], [column('flag')]),
  success('string-conversion', "SELECT CAST('true' AS BOOLEAN) AS flag, CAST('false' AS BOOLEAN) AS other",
    [{flag: true, other: false}], [column('flag'), column('other')]),
  success('empty-typed-null', 'SELECT CAST(NULL AS BOOLEAN) AS flag WHERE FALSE', [], [column('flag', true)]),
  success('nullable-parameter', 'SELECT CAST(@p AS BOOLEAN) AS flag', [{flag: null}], [column('flag', true)], {
    parameterDeclarations: {p: {type: 'boolean', nullable: true}}, parameters: {p: null},
  }),
  success('pipe-scope', 'SELECT CAST(FALSE AS BOOLEAN) AS flag |> WHERE flag IS NOT NULL |> SELECT flag',
    [{flag: false}], [column('flag')], {format: 'aql-text'}),
];
export const booleanCastRefusals = [
  {name: 'boolean-cast-refusal-quoted-type', format: 'sql', text: 'SELECT CAST(TRUE AS `BOOLEAN`) AS flag'},
  {name: 'boolean-cast-refusal-unsupported-type', format: 'sql', text: 'SELECT CAST(TRUE AS BOOLEANISH) AS flag'},
  {name: 'boolean-cast-refusal-undeclared-parameter', format: 'sql', text: 'SELECT CAST(@p AS BOOLEAN) AS flag'},
  {name: 'boolean-cast-refusal-wrong-parameter', format: 'sql', text: 'SELECT CAST(@p AS BOOLEAN) AS flag',
    parameterDeclarations: {p: {type: 'boolean'}}, parameters: {p: 'true'}},
];
export const booleanCastExecutionFailures = [{name: 'boolean-cast-invalid-string', format: 'sql',
  text: "SELECT CAST('bad' AS BOOLEAN) AS flag", resultNames: ['answer'], sourceReadSessionCount: 0}];
