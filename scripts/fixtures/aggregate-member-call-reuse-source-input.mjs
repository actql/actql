import {aggregatePropertyOrderProgram, aggregatePropertyOrderSuccesses}
  from './aggregate-property-order-source-input.mjs';

// Reuse only the existing independently authored input, not compiler output.
// Five admitted rows have scores 20,10,NULL,NULL,10; COUNT is therefore 3.
const base = aggregatePropertyOrderSuccesses.find(item => item.name === 'aggregate-property-order-sql');
const prefix = base.text.slice(0, base.text.lastIndexOf('SELECT STRING_AGG'));
const number = {type: 'number', nullable: false};
const string = {type: 'string', nullable: true};
const object = {type: 'object', nullable: true, additional_properties: false,
  fields: {score: {type: 'number', nullable: true}}};
const columns = [{name: 'n', contract: number}];
const member = {property: {name: 'score', value: {field: 'payload'}}};
export const aggregateMemberCallProgram = {version: 'actql/0.1',
  id: 'fixture.aggregate_member_call', params: aggregatePropertyOrderProgram.params,
  stages: [aggregatePropertyOrderProgram.stages[0], {
    id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [...aggregatePropertyOrderProgram.stages[1].steps.slice(0, 2),
      {group: {by: [], aggregates: {n: {fn: 'count', expr: member}}}},
      {filter: {gt: [{field: 'n'}, {literal: 0}]}},
      {select: ['n'], as: 'out'}],
    results: {rows: {from: 'out', fields: ['n']}},
  }], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const aggregateMemberAliasProgram = {...aggregateMemberCallProgram,
  id: 'fixture.aggregate_member_alias', stages: [aggregateMemberCallProgram.stages[0], {
    ...aggregateMemberCallProgram.stages[1],
    steps: [...aggregateMemberCallProgram.stages[1].steps.slice(0, 4),
      {derive: {published_payload: {$param: 'p3'}}},
      {select: ['n', {payload: 'published_payload'}], as: 'out'}],
    results: {rows: {from: 'out', fields: ['n', 'payload']}},
  }],
};
const success = (name, text, extra = {}) => ({...base,
  name: 'aggregate-member-call-' + name, text: prefix + text,
  expected: [{n: 3}], columns, ...extra});
const count = 'SELECT COUNT(payload.score) AS n FROM objects ';
const alias = 'SELECT COUNT(payload.score) AS n, @p3 AS payload FROM objects ';
export const aggregateMemberCallSuccesses = [
  success('independent-json', '', {format: 'json', text: JSON.stringify(aggregateMemberCallProgram),
    parameterDeclarations: undefined}),
  success('selected-property', count + 'HAVING COUNT((objects.payload).`SCORE`) > 0'),
  success('filtered-property', 'SELECT COUNT(payload.score WHERE payload.score > 10) AS n FROM objects '
    + 'HAVING COUNT((payload).score WHERE (objects.payload).`SCORE` > 10) > 0', {expected: [{n: 1}]}),
  success('empty-global', count + 'HAVING COUNT((payload).score) = 0',
    {sourceRows: [], expected: [{n: 0}]}),
  success('alias-null-contrast', alias + 'HAVING COUNT((payload).score) > 0',
    {expected: [], columns: [...columns, {name: 'payload', contract: object}]}),
  success('qualified-input-contrast', alias + 'HAVING COUNT((objects.payload).score) > 0',
    {expected: [{n: 3, payload: null}], columns: [...columns, {name: 'payload', contract: object}]}),
  success('qualified-independent-json', '', {format: 'json', text: JSON.stringify(aggregateMemberAliasProgram),
    parameterDeclarations: undefined, expected: [{n: 3, payload: null}],
    columns: [...columns, {name: 'payload', contract: object}]}),
  success('range-object-contrast', ', colliding AS (SELECT id, payload, other.score AS score FROM objects) '
    + 'SELECT COUNT((payload.payload).score) AS n FROM colliding AS payload HAVING COUNT(payload.score) > 3'),
  success('distinct-contrast', count + 'HAVING COUNT(DISTINCT (payload).score) = 2'),
  success('filter-contrast', 'SELECT COUNT(payload.score WHERE payload.score > 10) AS n FROM objects '
    + 'HAVING COUNT((payload).score WHERE payload.score > 20) > 0', {expected: []}),
  success('ordered-collection', "SELECT STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names FROM objects "
    + "HAVING STRING_AGG(name, '|' ORDER BY (objects.payload).`SCORE` NULLS LAST, id) = 'b|b|a|c'",
    {expected: [{names: 'b|b|a|c'}], columns: [{name: 'names', contract: string}]}),
  success('order-contrast', "SELECT STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names FROM objects "
    + "HAVING STRING_AGG(name, '|' ORDER BY (objects.payload).score DESC NULLS FIRST, id) = 'c|a|b|b'",
    {expected: [{names: 'b|b|a|c'}], columns: [{name: 'names', contract: string}]}),
];
export const aggregateMemberCallRefusals = [
  count + 'HAVING COUNT((missing).score) > 0',
  count + 'HAVING COUNT(n) > 0',
].map((text, index) => ({...base, name: 'aggregate-member-call-invalid-' + index,
  text: prefix + text, expectedCode: 'ClientProgramInvalidInput'}));
