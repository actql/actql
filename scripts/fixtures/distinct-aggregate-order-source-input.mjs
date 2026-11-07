// Authored Programs and expectations; no compiler or evaluator generates them.
import {distinctArrayReferenceKeySuccesses, distinctArrayReferenceKeyRefusals}
  from './distinct-array-reference-key-source-input.mjs';
const number = {type: 'number', nullable: false};
const string = {type: 'string', nullable: true};
const sourceRows = [{id: 4, amount: 20}, {id: 2, amount: 10},
  {id: 1, amount: 20}, {id: 3, amount: null}, {id: 0, amount: 99}];
const columns = [{name: 'names', contract: string}];
const data = 'WITH labels AS (SELECT id, CAST(amount AS STRING) AS name '
  + 'FROM records WHERE id > 0) ';
export const distinctAggregateOrderProgram = {version: 'actql/0.1',
  id: 'fixture.distinct_aggregate_order', stages: [
    {id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
      steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
        {select: ['amount', 'id'], as: 'captured'}],
      results: {source: {from: 'captured', fields: ['amount', 'id']}}},
    {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
      steps: [{from: 'records', derive: {
        name: {cast: {value: {field: 'amount'}, target: {type: 'string'}}}}},
      {group: {by: [], aggregates: {names: {fn: 'string_agg', field: 'name',
        distinct: true, max_bytes: 65536, delimiter: '|',
        order_by: [{field: 'name', dir: 'asc', nulls: 'first'}]}}}, as: 'out'}],
      results: {rows: {from: 'out', fields: ['names']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
const success = (name, tail, extra = {}) => ({name: 'distinct-aggregate-order-' + name,
  format: 'aql-text', text: data + tail, sourceRows, expected: [{names: '10|20'}],
  columns, sourceReadSessionCount: 1, ...extra});
export const distinctAggregateOrderSuccesses = [
  success('independent-json', '', {format: 'json', text: JSON.stringify(distinctAggregateOrderProgram)}),
  success('sql', "SELECT STRING_AGG(DISTINCT name, '|' ORDER BY name) AS names FROM labels"),
  success('qualified', "SELECT STRING_AGG(DISTINCT name, '|' ORDER BY l.name) AS names FROM labels AS l"),
  success('quoted-parenthesized', "SELECT STRING_AGG(DISTINCT l.name, '|' ORDER BY (`l`.`NAME`)) AS names FROM labels AS l"),
  success('pipe-descending', "FROM labels |> AGGREGATE STRING_AGG(DISTINCT name, '|' ORDER BY name DESC NULLS LAST) AS names",
    {expected: [{names: '20|10'}]}),
  success('old-input-snapshot', "FROM labels AS old |> SET name = 'changed' "
    + "|> AGGREGATE STRING_AGG(DISTINCT old.name, '|' ORDER BY old.name) AS names"),
  success('ordinary-other-key', "SELECT STRING_AGG(name, '|' ORDER BY id) AS names FROM labels",
    {expected: [{names: '20|10|20'}]}),
  success('typed-empty', "SELECT STRING_AGG(DISTINCT name, '|' ORDER BY name) AS names FROM labels",
    {sourceRows: [], expected: [{names: null}]}),
  success('keyed-array-qualified', '', {
    text: 'FROM records |> WHERE id > 0 |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 '
      + '|> AGGREGATE ARRAY_AGG(DISTINCT id IGNORE NULLS ORDER BY records.id DESC) AS ids',
    expected: [{ids: [4, 3, 2, 1]}],
    columns: [{name: 'ids', contract: {type: 'array', nullable: false, items: number}}],
  }),
  success('static-property', '', {
    text: 'WITH objects AS (SELECT id, @payload AS payload FROM records WHERE id > 0) '
      + "SELECT STRING_AGG(DISTINCT (payload).name, '|' ORDER BY objects.payload.`NAME`) AS names FROM objects",
    parameterDeclarations: {payload: {type: 'object', nullable: true,
      fields: {name: {type: 'string', nullable: true}}}},
    parameters: {payload: {name: 'kept'}}, expected: [{names: 'kept'}],
  }),
];
export const distinctAggregateOrderRefusals = [
  "SELECT STRING_AGG(DISTINCT name, '|' ORDER BY id) AS names FROM labels",
  "SELECT STRING_AGG(DISTINCT name, '|' ORDER BY name, id) AS names FROM labels",
  "FROM labels |> AGGREGATE STRING_AGG(DISTINCT name, '|' ORDER BY id) AS names",
  "FROM labels AS old |> SET name = 'changed' |> AGGREGATE STRING_AGG(DISTINCT name, '|' ORDER BY old.name) AS names",
  "SELECT ARRAY_AGG(DISTINCT id IGNORE NULLS ORDER BY name) AS items FROM labels",
  "SELECT ARRAY_AGG(DISTINCT id IGNORE NULLS ORDER BY id, name) AS items FROM labels",
].map((tail, index) => ({name: 'distinct-aggregate-order-refuse-' + index,
  format: 'aql-text', text: data + tail, expectedCode: 'ClientProgramImplementationLimit'}));
distinctAggregateOrderRefusals.push({
  name: 'distinct-aggregate-order-refuse-object-range-collision', format: 'aql-text',
  text: "WITH objects AS (SELECT id, 'outer' AS name, @payload AS payload FROM records WHERE id > 0) "
    + "SELECT STRING_AGG(DISTINCT (payload.payload).name, '|' ORDER BY payload.name) AS names FROM objects AS payload",
  parameterDeclarations: {payload: {type: 'object', nullable: true,
    fields: {name: {type: 'string', nullable: true}}}},
  parameters: {payload: {name: 'inner'}},
  expectedCode: 'ClientProgramImplementationLimit',
});
distinctAggregateOrderSuccesses.push(...distinctArrayReferenceKeySuccesses);
distinctAggregateOrderRefusals.push(...distinctArrayReferenceKeyRefusals);
