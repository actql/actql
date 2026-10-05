import {aggregatePropertyOrderProgram, aggregatePropertyOrderSuccesses}
  from './aggregate-property-order-source-input.mjs';

// Authored from grouped input multiplicity, TRUE-only filtering and alias
// scope. Expectations do not come from the compiler or execution output.
const number = {type: 'number', nullable: false};
const nullableNumber = {type: 'number', nullable: true};
const columns = names => names.map(name => ({name, contract: number}));
const rows = [{id: 3, amount: 20}, {id: 1, amount: null},
  {id: 2, amount: 10}, {id: 3, amount: 20}, {id: 4, amount: 0},
  {id: 1, amount: null}, {id: 0, amount: 999}];
const expected = [{id: 1}, {id: 3}];
export const havingAggregateProgram = {version: 'actql/0.1', id: 'fixture.having_aggregate',
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['amount', 'id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['amount', 'id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', group: {by: ['id'], aggregates: {cardinality: {fn: 'count'}}}},
      {filter: {gt: [{field: 'cardinality'}, {literal: 1}]}},
      {select: ['id']}, {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const query = 'SELECT id FROM records WHERE id > 0 GROUP BY id HAVING COUNT(*) > 1 ORDER BY id';
const success = (name, text, extra = {}) => ({name: 'having-aggregate-' + name,
  format: 'sql', text, sourceRows: rows, expected, columns: columns(['id']),
  sourceReadSessionCount: 1, ...extra});
// Independent ordinary Program for the separate single-JOIN source gap. It
// retains the same predicate, authored JOIN ceiling, multiplicity and Result.
export const havingSingleJoinProgram = {version: 'actql/0.1', id: 'fixture.having_single_join',
  stages: [havingAggregateProgram.stages[0],
    {id: 'seed', inputs: {}, steps: [{values: {schema: {k: number}, rows: [{k: 1}]}, as: 'one'}],
      results: {rows: {from: 'one', fields: ['k']}}},
    {id: 'main', inputs: {picked: {result: {stage: 'capture', result: 'source'}},
      seed: {result: {stage: 'seed', result: 'rows'}}},
    steps: [{from: 'picked', join: {with: 'seed', kind: 'inner',
      on: [{left: 'id', right: 'k'}], max_output_rows: 10, select: {id: 'left.id'}}},
    {group: {by: ['id'], aggregates: {n: {fn: 'count'}}}},
    {filter: {gt: [{field: 'n'}, {literal: 1}]}}, {select: ['id', 'n']},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'}],
    results: {rows: {from: 'ordered', fields: ['id', 'n']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const havingAggregateSuccesses = [
  success('independent-json', JSON.stringify(havingAggregateProgram), {format: 'json'}),
  success('hidden-count-star', query),
  success('repeated-count-limit', query.replace('COUNT(*) > 1', 'COUNT(*) > 1 AND COUNT(*) < 3') + ' LIMIT 1 OFFSET 1',
    {expected: [{id: 3}]}),
  success('selected-and-hidden', 'SELECT id, COUNT(*) AS n FROM records WHERE id > 0 GROUP BY id HAVING COUNT(*) > 1 AND COUNT(amount) > 0 ORDER BY id',
    {expected: [{id: 3, n: 2}], columns: columns(['id', 'n'])}),
  success('selected-sum-reuse', 'SELECT id, SUM(amount) AS total FROM records WHERE id > 0 GROUP BY id HAVING SUM(records.amount) > 35 ORDER BY id',
    {expected: [{id: 3, total: 40}], columns: [...columns(['id']), {name: 'total', contract: nullableNumber}]}),
  success('alias-input-collision', 'SELECT -id AS id, SUM(records.id) AS total FROM records WHERE id > 0 GROUP BY records.id HAVING SUM(id) < -4 ORDER BY id',
    {expected: [{id: -3, total: 6}], columns: [...columns(['id']), {name: 'total', contract: nullableNumber}]}),
  success('qualified-input-control', 'SELECT -id AS id, SUM(records.id) AS total FROM records WHERE id > 0 GROUP BY records.id HAVING SUM(records.id) < -4 ORDER BY id',
    {expected: [], columns: [...columns(['id']), {name: 'total', contract: nullableNumber}]}),
  success('null-and-distinct', 'SELECT id FROM records WHERE id > 0 GROUP BY id HAVING COUNT(DISTINCT amount) > 0 AND SUM(amount) > 0 ORDER BY id',
    {expected: [{id: 2}, {id: 3}]}),
  success('declared-parameters-pipe-tail', 'SELECT id FROM records WHERE id > 0 GROUP BY id HAVING COUNT(*) > @minimum |> SELECT id + 1 AS next |> ORDER BY next',
    {format: 'aql-text', parameterDeclarations: {minimum: number}, parameters: {minimum: 1},
      expected: [{next: 2}, {next: 4}], columns: columns(['next'])}),
  success('scoped-cte-join-chain', 'WITH picked AS (SELECT id FROM records WHERE id > 0) SELECT p.id, COUNT(*) AS n FROM picked AS p JOIN (SELECT 1 AS k) AS seed ON p.id = seed.k MAX_OUTPUT_ROWS 10 JOIN (SELECT 1 AS k) AS second ON p.id = second.k MAX_OUTPUT_ROWS 10 GROUP BY p.id HAVING COUNT(*) > 1 ORDER BY id',
    {expected: [{id: 1, n: 2}], columns: columns(['id', 'n'])}),
  success('single-join-json-control', JSON.stringify(havingSingleJoinProgram),
    {format: 'json', expected: [{id: 1, n: 2}], columns: columns(['id', 'n'])}),
  success('empty-grouped', query, {sourceRows: [], expected: []}),
  success('empty-global', 'SELECT COUNT(*) AS n FROM records HAVING COUNT(*) = 0',
    {sourceRows: [], expected: [{n: 0}], columns: columns(['n'])}),
];
export const havingAggregateRefusals = [
  'SELECT id FROM records GROUP BY id HAVING COUNTIF(id) > 0',
  'SELECT id FROM records GROUP BY id HAVING COUNT(*) > @missing',
  'SELECT id FROM records GROUP BY id HAVING COUNT(*) > 0 AND amount > 0',
  'SELECT id, COUNT(*) AS n FROM records GROUP BY id HAVING SUM(n) > 0',
  'SELECT id FROM records GROUP BY id HAVING COUNT(DISTINCT *) > 0',
].map((text, index) => ({name: 'having-aggregate-refuse-' + index, format: 'sql', text}));
// This valid query is an existing single-JOIN lowering gap, not a language
// restriction or a completed positive acceptance. Keep the failed source.
havingAggregateRefusals.push({name: 'having-aggregate-known-single-join-gap', format: 'sql',
  text: 'WITH picked AS (SELECT id FROM records WHERE id > 0) SELECT p.id, COUNT(*) AS n FROM picked AS p JOIN (SELECT 1 AS k) AS seed ON p.id = seed.k MAX_OUTPUT_ROWS 10 GROUP BY p.id HAVING COUNT(*) > 1 ORDER BY id',
  expectedCode: 'ClientProgramUnsupported',
  knownImplementationGap: true, intendedExpected: [{id: 1, n: 2}]});
export const havingAggregateExecutionFailures = [{
  name: 'having-aggregate-demanded-expression-failure', format: 'sql',
  text: 'SELECT id FROM records GROUP BY id HAVING SUM(1 / 0) > 0',
  resultNames: ['answer'], sourceReadSessionCount: 1,
}];

// Reuse the unchanged authored object/NULL input fixture, not product output.
// Selected aggregate orders see input payload; HAVING orders prefer its alias.
const propertyBase = aggregatePropertyOrderSuccesses.find(item => item.name === 'aggregate-property-order-sql');
const propertyPrefix = propertyBase.text.slice(0, propertyBase.text.lastIndexOf('SELECT STRING_AGG'));
const propertyControl = structuredClone(aggregatePropertyOrderProgram);
propertyControl.id = 'fixture.having_property_order';
const main = propertyControl.stages[1];
main.steps[3] = {group: {by: [], aggregates: {n: {fn: 'count'},
  hidden: aggregatePropertyOrderProgram.stages[1].steps[3].group.aggregates.names}}};
main.steps.push({filter: {eq: [{field: 'hidden'}, {literal: 'b|b|a|c'}]}},
  {select: ['n'], as: 'out'});
main.results.rows.fields = ['n'];
export const havingPropertyOrderProgram = propertyControl;
const propertySuccess = (name, tail, extra = {}) => ({...propertyBase,
  name: 'having-aggregate-property-' + name, text: propertyPrefix + tail,
  expected: [{n: 5}], columns: columns(['n']), ...extra});
const collision = "SELECT COUNT(*) AS n, @o1 AS payload, STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS original FROM objects HAVING STRING_AGG(name, '|' ORDER BY ";
const collisionColumns = [columnCount(), {name: 'payload', contract: propertyControl.params.o1},
  {name: 'original', contract: {type: 'string', nullable: true}}];
function columnCount() { return {name: 'n', contract: number}; }
havingAggregateSuccesses.push(
  propertySuccess('independent-json', '', {format: 'json', text: JSON.stringify(propertyControl),
    parameterDeclarations: undefined}),
  propertySuccess('hidden-order', "SELECT COUNT(*) AS n FROM objects HAVING STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) = 'b|b|a|c'"),
  propertySuccess('alias-input-collision', collision + "payload.score NULLS LAST, id) = 'a|b|b|c'",
    {expected: [{n: 5, payload: {score: 5}, original: 'b|b|a|c'}], columns: collisionColumns}),
  propertySuccess('qualified-input-control', collision + "objects.payload.score NULLS LAST, id) = 'a|b|b|c'",
    {expected: [], columns: collisionColumns}),
);
for (const [index, receiver] of ['payload.missing', 'id.score'].entries()) {
  havingAggregateRefusals.push({name: 'having-aggregate-property-refuse-' + index,
    format: 'aql-text', text: propertyPrefix + "SELECT COUNT(*) AS n FROM objects HAVING STRING_AGG(name, '|' ORDER BY " + receiver + " NULLS LAST, id) = 'b|b|a|c'",
    parameterDeclarations: propertyBase.parameterDeclarations, parameters: propertyBase.parameters});
}
