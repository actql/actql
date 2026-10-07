// Independent Programs, contracts and rows authored from typed-access and
// per-call collection ordering. No runtime output generates these expectations.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const string = {type: 'string', nullable: true};
const payload = {type: 'object', nullable: true, fields: {score: nullableNumber}};
const other = {type: 'object', nullable: false, fields: {score: number}};
const parameterDeclarations = {p1: payload, p2: payload, p3: payload, p4: payload,
  o1: other, o2: other, o3: other, o4: other};
const parameters = {p1: {score: 20}, p2: {score: 10}, p3: null, p4: {score: null},
  o1: {score: 5}, o2: {score: 30}, o3: {score: 15}, o4: {score: 25}};
const sourceRows = [{id: 2, amount: 10}, {id: 1, amount: 20},
  {id: 3, amount: null}, {id: 4, amount: 40}, {id: 2, amount: 10}, {id: 0, amount: 99}];
const data = 'DATA objects = SELECT id, '
  + "CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, "
  + 'CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, '
  + 'CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other '
  + 'FROM records WHERE id > 0; ';
const column = (name, contract = string) => ({name, contract});
const parameterCase = prefix => ({case: {when: [
  {when: {eq: [{field: 'id'}, {literal: 1}]}, then: {$param: prefix + '1'}},
  {when: {eq: [{field: 'id'}, {literal: 2}]}, then: {$param: prefix + '2'}},
  {when: {eq: [{field: 'id'}, {literal: 3}]}, then: {$param: prefix + '3'}},
], else: {$param: prefix + '4'}}});
export const aggregatePropertyOrderProgram = {version: 'actql/0.1',
  id: 'fixture.aggregate_property_order', params: parameterDeclarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {
      name: {case: {when: [
        {when: {eq: [{field: 'id'}, {literal: 1}]}, then: {literal: 'a'}},
        {when: {eq: [{field: 'id'}, {literal: 2}]}, then: {literal: 'b'}},
        {when: {eq: [{field: 'id'}, {literal: 3}]}, then: {literal: 'c'}},
      ], else: {literal: null}}}, payload: parameterCase('p'), other: parameterCase('o')}},
    {select: ['id', 'name', 'payload', 'other']},
    {derive: {key: {property: {name: 'score', value: {field: 'payload'}}}}},
    {group: {by: [], aggregates: {names: {fn: 'string_agg', field: 'name',
      order_by: [{field: 'key', dir: 'asc', nulls: 'last'},
        {field: 'id', dir: 'asc', nulls: 'first'}], max_bytes: 65536, delimiter: '|'}}}, as: 'out'}],
    results: {rows: {from: 'out', fields: ['names']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const aggregateDefaultDelimiterProgram = {
  ...aggregatePropertyOrderProgram, id: 'fixture.aggregate_default_delimiter',
  stages: [aggregatePropertyOrderProgram.stages[0], {
    ...aggregatePropertyOrderProgram.stages[1],
    steps: [...aggregatePropertyOrderProgram.stages[1].steps.slice(0, 3),
      {group: {by: [], aggregates: {names: {fn: 'string_agg', field: 'name',
        order_by: [{field: 'key', dir: 'asc', nulls: 'last'},
          {field: 'id', dir: 'asc', nulls: 'first'}], max_bytes: 65536, delimiter: ','}}}, as: 'out'}],
  }],
};
export const aggregatePropertyOrderArrayProgram = {
  ...aggregatePropertyOrderProgram, id: 'fixture.aggregate_property_array_order',
  stages: [aggregatePropertyOrderProgram.stages[0], {
    ...aggregatePropertyOrderProgram.stages[1],
    steps: [...aggregatePropertyOrderProgram.stages[1].steps.slice(0, 2),
      {assert_rows: {unique_by: ['id']}},
      {sort: [{field: 'id', dir: 'asc', nulls: 'first'}]}, {take: 4},
      {derive: {key: {property: {name: 'score', value: {field: 'payload'}}}}},
      {group: {by: [], aggregates: {ids: {fn: 'array_agg', field: 'id',
        order_by: [{field: 'key', dir: 'asc', nulls: 'last'},
          {field: 'id', dir: 'asc', nulls: 'first'}], max_items: 1000000}}}, as: 'out'}],
    results: {rows: {from: 'out', fields: ['ids']}},
  }],
};
const success = (name, tail, extra = {}) => ({name: 'aggregate-property-order-' + name,
  format: 'aql-text', text: data + tail, parameterDeclarations, parameters, sourceRows,
  sourceReadSessionCount: 1, expected: [{names: 'b|b|a|c'}], columns: [column('names')], ...extra});
export const aggregatePropertyOrderSuccesses = [
  success('independent-json', '', {format: 'json', text: JSON.stringify(aggregatePropertyOrderProgram),
    parameterDeclarations: undefined}),
  success('sql', "SELECT STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names FROM objects"),
  success('pipe-qualified', "FROM objects AS before |> AGGREGATE STRING_AGG(name, '|' ORDER BY `before`.`payload`.`score` NULLS LAST, id) AS names"),
  success('per-call-opposite-order', "SELECT STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names, "
    + "STRING_AGG(name, '|' ORDER BY payload.score DESC NULLS FIRST, id) AS reverse FROM objects", {
    expected: [{names: 'b|b|a|c', reverse: 'c|a|b|b'}], columns: [column('names'), column('reverse')],
  }),
  success('current-and-snapshot', 'FROM objects AS before |> SET payload = other '
    + "|> AGGREGATE STRING_AGG(name, '|' ORDER BY payload.score, id) AS current, "
    + "STRING_AGG(name, '|' ORDER BY before.payload.score NULLS LAST, id) AS previous", {
    expected: [{current: 'a|c|b|b', previous: 'b|b|a|c'}], columns: [column('current'), column('previous')],
  }),
  success('input-over-sibling', "SELECT COUNT(*) AS payload, STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names FROM objects", {
    expected: [{payload: 5, names: 'b|b|a|c'}], columns: [column('payload', number), column('names')],
  }),
  success('filtered-input', "SELECT STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names FROM objects WHERE name != 'c' AND id <= 2", {expected: [{names: 'b|b|a'}]}),
  success('empty-global', "SELECT STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names FROM objects", {
    sourceRows: [], expected: [{names: null}],
  }),
  success('default-independent-json', '', {format: 'json',
    text: JSON.stringify(aggregateDefaultDelimiterProgram), parameterDeclarations: undefined,
    expected: [{names: 'b,b,a,c'}],
  }),
  success('default-sql', 'SELECT STRING_AGG(name ORDER BY payload.score NULLS LAST, id) AS names FROM objects',
    {expected: [{names: 'b,b,a,c'}]}),
  success('default-pipe', 'FROM objects |> AGGREGATE STRING_AGG(name ORDER BY payload.score NULLS LAST, id) AS names',
    {expected: [{names: 'b,b,a,c'}]}),
  success('explicit-empty-delimiter', "SELECT STRING_AGG(name, '' ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
    {expected: [{names: 'bbac'}]}),
  success('default-filter', 'SELECT STRING_AGG(name WHERE id <= 2 ORDER BY payload.score NULLS LAST, id) AS names FROM objects',
    {expected: [{names: 'b,b,a'}]}),
  success('default-empty', 'SELECT STRING_AGG(name ORDER BY payload.score NULLS LAST, id) AS names FROM objects',
    {sourceRows: [], expected: [{names: null}]}),
  success('default-all-null', 'SELECT STRING_AGG(name ORDER BY payload.score NULLS LAST, id) AS names FROM objects',
    {sourceRows: [{id: 4, amount: 40}], expected: [{names: null}]}),
  // ARRAY_AGG requires actual key evidence. The author supplies the existing
  // assertion and a bounded input; the Frontend never invents either condition.
  success('independent-array-json', '', {format: 'json',
    text: JSON.stringify(aggregatePropertyOrderArrayProgram), parameterDeclarations: undefined,
    sourceRows: sourceRows.filter((row, index) => index !== 4),
    expected: [{ids: [2, 1, 3, 4]}], columns: [column('ids',
      {type: 'array', nullable: false, items: number})],
  }),
  success('keyed-array', 'FROM objects |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 '
    + '|> AGGREGATE ARRAY_AGG(id IGNORE NULLS ORDER BY payload.score NULLS LAST, id) AS ids', {
    sourceRows: sourceRows.filter((row, index) => index !== 4),
    expected: [{ids: [2, 1, 3, 4]}], columns: [column('ids',
      {type: 'array', nullable: false, items: number})],
  }),
];
export const aggregatePropertyOrderRefusals = [
  "SELECT STRING_AGG(name, '|' ORDER BY payload.missing, id) AS names FROM objects",
  "SELECT STRING_AGG(name, '|' ORDER BY id.score, id) AS names FROM objects",
  "FROM objects AS old |> AS current |> AGGREGATE STRING_AGG(name, '|' ORDER BY old.payload.score, id) AS names",
  "SELECT STRING_AGG(name, '|' ORDER BY names, id) AS names FROM objects",
  "SELECT STRING_AGG(name, 1 ORDER BY id) AS names FROM objects",
  "SELECT STRING_AGG(name, @p1 ORDER BY id) AS names FROM objects",
  "SELECT STRING_AGG(name, ORDER BY id) AS names FROM objects",
].map((tail, index) => ({name: 'aggregate-property-order-refuse-' + index,
  format: 'aql-text', text: data + tail, parameterDeclarations, parameters}));
export const aggregatePropertyOrderExecutionFailures = [{
  name: 'aggregate-property-order-demanded-argument-failure', format: 'aql-text',
  text: data + "SELECT STRING_AGG(IF(id / (id - id) = 0, name, name), '|' ORDER BY payload.score, id) AS names FROM objects",
  parameterDeclarations, parameters, sourceReadSessionCount: 1, resultNames: ['answer'],
}];
