// Independent Source-to-Graph expectations. Flat rows use the standard
// installed Source; object values use existing typed parameters and CASE.
// This does not claim that raw object Source capture has an order witness.
const number = {type: 'number', nullable: false};
const score = {...number, nullable: true};
const payload = {type: 'object', nullable: true, fields: {score}};
const parameterDeclarations = {minimum: number, p1: payload, p2: payload,
  p3: payload, p4: payload};
const parameters = {minimum: 0, p1: {score: 20}, p2: {score: 10},
  p3: null, p4: {score: null}};
const sourceRows = [{id: 2, amount: 10}, {id: 1, amount: 20},
  {id: 3, amount: null}, {id: 4, amount: 40}, {id: 0, amount: 99}];
const columns = [{name: 'id', contract: number}, {name: 'score', contract: score}];
const expected = [{id: 1, score: 20}, {id: 2, score: 10},
  {id: 3, score: null}, {id: 4, score: null}];
const data = 'WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 '
  + 'WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload '
  + 'FROM records WHERE id > @minimum) ';
const graph = ', g AS (GRAPH (NODE TABLES '
  + '(objects AS N KEY (id) LABEL Person PROPERTIES (id, payload)))) ';
const head = data + graph + 'FROM GRAPH g |> MATCH WALK (a:Person) |> ';
const results = rows => ({matched: {rows, columns}});
const sourceCase = (name, tail, rows = expected, extra = {}) => ({
  name: 'source-graph-member-' + name, format: 'aql-text',
  text: head + tail + ' |> ORDER BY id |> RESULT matched',
  parameterDeclarations, parameters, sourceRows, sourceReadSessionCount: 1,
  results: results(rows), ...extra,
});

// Authored ordinary Program, including actual Source acquisition and the
// original predicate/parameters. The compiler does not generate this control.
export const sourceGraphMemberProgram = {version: 'actql/0.1',
  id: 'fixture.source_graph_member', params: parameterDeclarations,
  stages: [{id: 'capture', inputs: {remote: {connector: 'crm/main', resource: 'r'}},
    steps: [{from: 'remote', filter: {gt: [{field: 'id'}, {$param: 'minimum'}]}},
      {select: ['id'], as: 'captured'}],
    results: {source: {from: 'captured', fields: ['id']}}},
  {id: 'main', inputs: {records: {result: {stage: 'capture', result: 'source'}}},
    steps: [{from: 'records', derive: {payload: {case: {when: [
      {when: {eq: [{field: 'id'}, {literal: 1}]}, then: {$param: 'p1'}},
      {when: {eq: [{field: 'id'}, {literal: 2}]}, then: {$param: 'p2'}},
      {when: {eq: [{field: 'id'}, {literal: 3}]}, then: {$param: 'p3'}},
    ], else: {$param: 'p4'}}}}},
    {select: ['id', 'payload'], as: 'objects'},
    {graph: {version: 'actql-graph-constructor/0.1',
      nodes: [{name: 'N', from: 'objects', key: ['id'], labels: [{name: 'Person',
        properties: {mode: 'columns', columns: [{from: 'id', to: 'id'},
          {from: 'payload', to: 'payload'}]}}]}], edges: []}, as: 'g'},
    {from: 'g', match_nodes: {definition: 'N', label: 'Person',
      where: {literal: true}, fields: ['id', 'payload']}, as: 'matched'},
    {from: 'matched', derive: {score: {property: {name: 'score', value: {field: 'payload'}}}}},
    {select: ['id', 'score']},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['id', 'score']}}}],
  results: {matched: {from: {stage: 'main', result: 'rows'}}}};

export const sourceGraphMemberSuccesses = [
  sourceCase('independent-json', '', expected, {format: 'json',
    text: JSON.stringify(sourceGraphMemberProgram), parameterDeclarations: undefined}),
  sourceCase('declared-member', 'SELECT a.id AS id, a.payload.score AS score'),
  sourceCase('folded-member', 'SELECT a.id AS id, a.payload.SCORE AS score'),
  sourceCase('quoted-member', 'SELECT `A`.`ID` AS id, `A`.`PAYLOAD`.`ScOrE` AS score'),
  sourceCase('projected-receiver',
    'SELECT a.id AS id, a.payload AS kept |> SELECT id, kept.SCORE AS score'),
  sourceCase('null-receiver-and-member',
    'WHERE a.payload.SCORE IS NULL |> SELECT a.id AS id, a.payload.SCORE AS score',
    [{id: 3, score: null}, {id: 4, score: null}]),
  sourceCase('typed-empty',
    // A strict comparison is TRUE only for a non-null receiver and member.
    // The checked output stays non-null even when no authored row passes.
    'WHERE a.payload.SCORE > 100 |> SELECT a.id AS id, a.payload.SCORE AS score', [],
    {results: {matched: {rows: [], columns: [
      {name: 'id', contract: number}, {name: 'score', contract: number},
    ]}}}),
];
export const sourceGraphMemberRefusals = [
  ['missing-member', 'SELECT a.payload.MISSING AS score'],
  ['scalar-receiver', 'SELECT a.id.score AS score'],
  ['removed-receiver', 'SELECT a.id AS id |> WHERE a.payload.SCORE > 0'],
  ['same-select-alias', 'SELECT a.payload AS kept, kept.SCORE AS score'],
].map(([name, tail]) => ({name: 'source-graph-member-invalid-' + name,
  format: 'aql-text', text: head + tail, parameterDeclarations, parameters, sourceRows}));
