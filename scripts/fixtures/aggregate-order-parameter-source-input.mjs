// Independent ordinary Programs and ordered Result expectations. Parameters
// remain separately admitted values; no fixture rewrites a generated Program.
const number = {type: 'number', nullable: false};
const nullableNumber = {...number, nullable: true};
const string = {type: 'string', nullable: true};
const object = {type: 'object', nullable: true, fields: {rank: nullableNumber}};
const sourceRows = [{id: 2, amount: 10}, {id: 1, amount: 20},
  {id: 3, amount: null}, {id: 4, amount: 40}, {id: 2, amount: 10}, {id: 0, amount: 99}];
const data = 'DATA labels = SELECT id, '
  + "CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name "
  + 'FROM records WHERE id > 0; ';
const sql = "SELECT STRING_AGG(name, '|' ORDER BY @key DESC NULLS LAST, id) AS names FROM labels";
export const aggregateOrderParameterProgram = {version: 'actql/0.1',
  id: 'fixture.aggregate_order_parameter', params: {key: nullableNumber},
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {literal: 0}]}},
      {select: ['id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {name: {case: {when: [
      {when: {eq: [{field: 'id'}, {literal: 1}]}, then: {literal: 'z'}},
      {when: {eq: [{field: 'id'}, {literal: 2}]}, then: {literal: 'a'}},
      {when: {eq: [{field: 'id'}, {literal: 3}]}, then: {literal: 'm'}},
    ], else: {literal: null}}}}},
    {select: ['id', 'name']}, {derive: {key: {$param: 'key'}}},
    {group: {by: [], aggregates: {names: {fn: 'string_agg', field: 'name',
      order_by: [{field: 'key', dir: 'desc', nulls: 'last'},
        {field: 'id', dir: 'asc', nulls: 'first'}], max_bytes: 65536, delimiter: '|'}}}, as: 'out'}],
    results: {rows: {from: 'out', fields: ['names']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}}};
export const aggregateOrderObjectParameterProgram = {
  ...aggregateOrderParameterProgram, id: 'fixture.aggregate_order_object_parameter', params: {cfg: object},
  stages: [aggregateOrderParameterProgram.stages[0], {
    ...aggregateOrderParameterProgram.stages[1],
    steps: [...aggregateOrderParameterProgram.stages[1].steps.slice(0, 2),
      {derive: {key: {property: {name: 'rank', value: {$param: 'cfg'}}}}},
      aggregateOrderParameterProgram.stages[1].steps[3]],
  }],
};
const success = (name, tail = sql, extra = {}) => ({name: 'aggregate-order-parameter-' + name,
  format: 'aql-text', text: data + tail, parameterDeclarations: {key: nullableNumber},
  parameters: {key: 7}, sourceRows, sourceReadSessionCount: 1,
  expected: [{names: 'z|a|a|m'}], columns: [{name: 'names', contract: string}], ...extra});
const objectSuccess = (name, parameters, extra = {}) => success(name,
  "FROM labels |> AGGREGATE STRING_AGG(name, '|' ORDER BY ((@`CFG`)).`rank` DESC NULLS LAST, id) AS names",
  {parameterDeclarations: {cfg: object}, parameters, ...extra});
export const aggregateOrderParameterSuccesses = [
  success('independent-json', '', {format: 'json', text: JSON.stringify(aggregateOrderParameterProgram),
    parameterDeclarations: undefined}),
  success('sql'),
  success('quoted-pipe', "FROM labels |> AGGREGATE STRING_AGG(name, '|' ORDER BY (@`KEY`) DESC NULLS LAST, id) AS names"),
  success('nullable-scalar', sql, {parameters: {key: null}}),
  success('column-name-collision', sql.replace('@key', '@NAME'), {
    parameterDeclarations: {name: nullableNumber}, parameters: {name: 7},
  }),
  objectSuccess('object-member', {cfg: {rank: 7}}),
  objectSuccess('nullable-object', {cfg: null}),
  objectSuccess('nullable-member', {cfg: {rank: null}}),
  objectSuccess('independent-object-json', {cfg: {rank: 7}}, {format: 'json',
    text: JSON.stringify(aggregateOrderObjectParameterProgram), parameterDeclarations: undefined}),
  success('filtered-argument', sql.replace("name, '|'", "name, '|' WHERE id <= 2"),
    {expected: [{names: 'z|a|a'}]}),
  success('typed-empty', sql, {sourceRows: [], expected: [{names: null}]}),
  success('distinct-same-parameter', "SELECT STRING_AGG(DISTINCT @label, '|' ORDER BY @LABEL) AS names FROM labels", {
    parameterDeclarations: {label: string}, parameters: {label: 'kept'}, expected: [{names: 'kept'}],
  }),
  success('distinct-null-parameter', "FROM labels |> AGGREGATE STRING_AGG(DISTINCT @`LABEL`, '|' ORDER BY (@label)) AS names", {
    parameterDeclarations: {label: string}, parameters: {label: null}, expected: [{names: null}],
  }),
];
export const aggregateOrderParameterRefusals = [
  {name: 'undeclared', parameterDeclarations: undefined, parameters: undefined},
  {name: 'missing-value', parameters: {}},
  {name: 'wrong-type', parameters: {key: 'private-value'}},
  {name: 'wrong-machine-case', parameters: {KEY: 7}},
  {name: 'ambiguous-declarations', parameterDeclarations: {key: nullableNumber, KEY: nullableNumber},
    parameters: {key: 7, KEY: 7}, expectedCode: 'ClientProgramRejected'},
  {name: 'missing-member', text: data + sql.replace('@key', '@cfg.missing'),
    parameterDeclarations: {cfg: object}, parameters: {cfg: {rank: 7}}},
  {name: 'scalar-receiver', text: data + sql.replace('@key', '@key.rank')},
  {name: 'non-orderable-object', text: data + sql.replace('@key', '@cfg'),
    parameterDeclarations: {cfg: object}, parameters: {cfg: {rank: 7}}},
  {name: 'distinct-different-argument', text: data + sql.replace('STRING_AGG(name', 'STRING_AGG(DISTINCT name'),
    expectedCode: 'ClientProgramImplementationLimit'},
  {name: 'numeric-ordinal', text: data + sql.replace('@key DESC NULLS LAST, id', '1'),
    expectedCode: 'ClientProgramImplementationLimit'},
].map(item => ({format: 'aql-text', text: data + sql,
  parameterDeclarations: {key: nullableNumber}, parameters: {key: 7}, ...item,
  name: 'aggregate-order-parameter-refuse-' + item.name}));
