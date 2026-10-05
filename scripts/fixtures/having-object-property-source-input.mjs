// Independent expectations from grouped SELECT/HAVING scope and Language's
// nullable closed-object property contract. No compiler emits these fixtures.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const string = {type: 'string', nullable: false, max_utf8_bytes: 4};
const nested = {type: 'object', nullable: true, fields: {
  risk: string, reason: {...string, nullable: true},
}};
const object = {type: 'object', nullable: true, fields: {score: nullableNumber, nested}};
// Checked closed objects expose this existing contract expansion, including
// nested objects. Author parameter declarations need not spell the default.
const checkedObject = {...object, additional_properties: false, fields: {
  score: nullableNumber, nested: {...nested, additional_properties: false},
}};
const rows = [{id: 3, amount: 30}, {id: 1, amount: null},
  {id: 2, amount: 20}, {id: 3, amount: 30}, {id: 0, amount: 99}];
const high = {score: 20, nested: {risk: 'high', reason: null}};
const low = {score: 5, nested: null};
const columns = [{name: 'id', contract: number},
  {name: 'assessment', contract: checkedObject}, {name: 'n', contract: number}];
const selected = [{id: 1, assessment: high, n: 1}, {id: 3, assessment: high, n: 2}];
const declarations = {high: object, low: object};
const parameters = {high, low};
const projection = 'SELECT id, CASE WHEN id = 2 THEN @low ELSE @high END AS assessment, COUNT(*) AS n '
  + 'FROM records WHERE id > 0 GROUP BY id ';
const source = projection + 'HAVING assessment.score > 10 ORDER BY id';
const success = (name, text, extra = {}) => ({name: 'having-object-property-' + name,
  format: 'sql', text, sourceRows: rows, parameterDeclarations: declarations,
  parameters, expected: selected, columns, sourceReadSessionCount: 1, ...extra});
export const havingObjectPropertyProgram = {
  version: 'actql/0.1', id: 'fixture.having_object_property', params: declarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', group: {by: ['id'], aggregates: {n: {fn: 'count'}}}},
        {derive: {assessment: {case: {when: [{
          when: {eq: [{field: 'id'}, {literal: 2}]}, then: {$param: 'low'},
        }], else: {$param: 'high'}}}}},
        {filter: {gt: [{property: {value: {field: 'assessment'}, name: 'score'}}, {literal: 10}]}},
        {select: ['id', 'assessment', 'n']},
        {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'summary'}],
      results: {rows: {from: 'summary', fields: ['id', 'assessment', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}},
};
const collisionProjection = 'SELECT records.id AS original_id, @high AS id, COUNT(*) AS n '
  + 'FROM records WHERE records.id > 0 GROUP BY records.id ';
const collisionValue = {...high, score: 2};
const collisionOptions = {parameterDeclarations: {high: object}, parameters: {high: collisionValue},
  columns: [{name: 'original_id', contract: number}, {name: 'id', contract: checkedObject},
    {name: 'n', contract: number}]};
export const havingObjectPropertySuccesses = [
  success('independent-json', JSON.stringify(havingObjectPropertyProgram), {
    format: 'json', parameterDeclarations: undefined,
  }),
  success('computed-alias', source),
  success('nested-and-quoted', projection
    + "HAVING `ASSESSMENT`.`nested`.`risk` = 'high' AND assessment.nested.reason IS NULL ORDER BY id"),
  success('null-receiver', source, {parameters: {...parameters, high: null}, expected: []}),
  success('null-field', source, {parameters: {...parameters, high: {...high, score: null}}, expected: []}),
  success('empty-input', source, {sourceRows: [], expected: []}),
  success('alias-input-collision', collisionProjection + 'HAVING id.score > records.id ORDER BY original_id', {
    ...collisionOptions, expected: [{original_id: 1, id: collisionValue, n: 1}],
  }),
  success('qualified-input-control', collisionProjection + 'HAVING records.id > 1 AND id.score IS NOT NULL ORDER BY original_id', {
    ...collisionOptions, expected: [{original_id: 2, id: collisionValue, n: 1},
      {original_id: 3, id: collisionValue, n: 2}],
  }),
  success('next-pipe-scope', projection + 'HAVING assessment.score > 10 '
    + '|> SELECT id, assessment.nested.risk AS risk, n |> ORDER BY id', {
    format: 'aql-text', expected: [{id: 1, risk: 'high', n: 1}, {id: 3, risk: 'high', n: 2}],
    columns: [{name: 'id', contract: number}, {name: 'risk', contract: {...string, nullable: true}},
      {name: 'n', contract: number}],
  }),
];
export const havingObjectPropertyRefusals = [
  'HAVING assessment.missing > 0',
  'HAVING id.score > 0',
  'HAVING records.assessment.score > 0',
  'HAVING amount.score > 0',
].map((tail, index) => ({name: 'having-object-property-invalid-' + index,
  format: 'sql', text: projection + tail, parameterDeclarations: declarations, parameters}));
export const havingObjectPropertyExecutionFailures = [
  {name: 'having-object-property-demanded-failure', format: 'sql',
    text: projection + 'HAVING assessment.score / (id - id) > 10 ORDER BY id',
    parameterDeclarations: declarations, parameters, sourceRows: rows, sourceReadSessionCount: 1,
    resultNames: ['answer']},
];
