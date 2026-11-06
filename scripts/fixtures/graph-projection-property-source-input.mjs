// Authored rows, type contracts and machine Program: no compiler/provider
// output is used to derive expectations.
const number = {type: 'number', nullable: false};
const score = {...number, nullable: true};
const payload = {type: 'object', nullable: true, fields: {score}};
const rows = [{id: 2, payload: {score: 10}}, {id: 1, payload: {score: 20}},
  {id: 3, payload: null}, {id: 4, payload: {score: null}}];
const declarations = {a: payload, b: payload, c: payload, d: payload};
const parameters = {a: {score: 10}, b: {score: 20}, c: null, d: {score: null}};
const columns = [{name: 'id', contract: number}, {name: 'score', contract: score}];
const expected = [{id: 1, score: 20}, {id: 2, score: 10},
  {id: 3, score: null}, {id: 4, score: null}];
const data = 'WITH objects AS (SELECT 2 AS id, @a AS payload '
  + 'UNION ALL SELECT 1 AS id, @b AS payload '
  + 'UNION ALL SELECT 3 AS id, @c AS payload '
  + 'UNION ALL SELECT 4 AS id, @d AS payload) ';
const graph = ', g AS (GRAPH (NODE TABLES '
  + '(objects AS N KEY (id) LABEL Person PROPERTIES (id, payload)))) ';
const head = data + graph + 'FROM GRAPH g |> MATCH WALK (a:Person) |> ';
const result = values => ({matched: {rows: values, columns}});
// A strict property comparison can be true only when receiver and member are
// non-null. Keep this checked contract even if the authored result is empty.
const filteredResult = values => ({matched: {rows: values,
  columns: [{name: 'id', contract: number}, {name: 'score', contract: number}]}});
const sourceCase = (name, tail, values = expected, extra = {}) => ({
  name: 'graph-projection-property-' + name, format: 'aql-text',
  text: head + tail + ' |> ORDER BY id |> RESULT matched',
  parameterDeclarations: declarations, parameters,
  results: result(values), sourceReadCount: 0, ...extra,
});
const filteredSourceCase = (name, tail, values, extra = {}) =>
  sourceCase(name, tail, values, {...extra, results: filteredResult(values)});
const program = {version: 'actql/0.1', id: 'fixture.graph_projection_property',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number, payload}, rows}, as: 'objects'},
    {graph: {version: 'actql-graph-constructor/0.1',
      nodes: [{name: 'N', from: 'objects', key: ['id'], labels: [{name: 'Person',
        properties: {mode: 'columns', columns: [{from: 'id', to: 'id'}, {from: 'payload', to: 'payload'}]}}]}],
      edges: []}, as: 'g'},
    {from: 'g', match_nodes: {definition: 'N', label: 'Person',
      where: {literal: true}, fields: ['id', 'payload']}, as: 'matched'},
    {from: 'matched', derive: {score: {property: {name: 'score', value: {field: 'payload'}}}}},
    {select: ['id', 'score']},
    {sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['id', 'score']}}}],
  results: {matched: {from: {stage: 'main', result: 'rows'}}}};
// Independently attach the common typed identity role and ordinary predicate.
const identityProgram = structuredClone(program);
identityProgram.id = 'fixture.graph_quoted_identity';
identityProgram.stages[0].steps[2].match_nodes.bindings = {identity: 'identity'};
identityProgram.stages[0].steps[2].match_nodes.fields = ['identity', 'id', 'payload'];
identityProgram.stages[0].steps.splice(3, 0, {from: 'matched', filter: {and: [
  {not: {is_null: {field: 'identity'}}},
  {gt: [{property: {name: 'score', value: {field: 'payload'}}}, {literal: 10}]},
]}});
// Continue from the filtered current row, not the original matched producer.
delete identityProgram.stages[0].steps[4].from;
// Two independently keyed self-loops produce two one-hop WALK occurrences.
const pathData = 'WITH n AS (SELECT 1 AS id) , e AS (SELECT 10 AS key, 1 AS src, 1 AS dst '
  + 'UNION ALL SELECT 11 AS key, 1 AS src, 1 AS dst) ';
const pathGraph = ', g AS (GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES) '
  + 'EDGE TABLES (e AS E KEY (key) SOURCE KEY (src) REFERENCES N '
  + 'DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES))) ';
const pathResult = {matched: {rows: [{depth: 1}, {depth: 1}],
  columns: [{name: 'depth', contract: number}]}};
const pathProgram = {version: 'actql/0.1', id: 'fixture.graph_quoted_path', stages: [
  {id: 'main', inputs: {}, steps: [
    {values: {schema: {id: number}, rows: [{id: 1}]}, as: 'n'},
    {values: {schema: {key: number, src: number, dst: number},
      rows: [{key: 10, src: 1, dst: 1}, {key: 11, src: 1, dst: 1}]}, as: 'e'},
    {graph: {version: 'actql-graph-constructor/0.1', nodes: [
      {name: 'N', from: 'n', key: ['id'], labels: [{name: 'Node', properties: {mode: 'no_properties'}}]}],
    edges: [{name: 'E', from: 'e', key: ['key'],
      source: {definition: 'N', key: ['src']}, target: {definition: 'N', key: ['dst']},
      labels: [{name: 'R', properties: {mode: 'no_properties'}}]}]}, as: 'g'},
    {from: 'g', match_nodes: {definition: 'N', label: 'Node', where: {literal: true},
      bindings: {identity: 'identity'}, fields: ['identity']}, as: 'seeds'},
    {from: 'g', traverse: {start: {from: 'seeds', id: 'identity'}, path_mode: 'walk', emit: 'paths',
      hops: [{direction: 'out', edge_types: ['R']}]}, as: 'paths'},
    {from: 'paths', select: [{depth: 'hop_count'}]},
    {sort: [{field: 'depth', dir: 'asc', nulls: 'first'}], as: 'ordered'},
  ], results: {rows: {from: 'ordered', fields: ['depth']}}}],
results: {matched: {from: {stage: 'main', result: 'rows'}}}};
export const graphProjectionPropertySuccesses = [
  {name: 'graph-projection-property-independent-json', format: 'json',
    text: JSON.stringify(program), results: result(expected), sourceReadCount: 0},
  sourceCase('qualified', 'SELECT a.id AS id, a.payload.score AS score'),
  sourceCase('local', 'SELECT id, payload.score AS score'),
  sourceCase('quoted', 'SELECT `A`.`ID` AS id, `A`.`PAYLOAD`.`score` AS score'),
  filteredSourceCase('identity-macro-and-parameter',
    'WHERE NODE_ID(a) IS NOT NULL AND a.payload.score > @min '
      + '|> SELECT a.id AS id, a.payload.score AS score', [{id: 1, score: 20}],
    {parameterDeclarations: {...declarations, min: number}, parameters: {...parameters, min: 10}}),
  {name: 'graph-projection-property-grouped-identity-independent-json', format: 'json',
    text: JSON.stringify({...identityProgram, id: 'fixture.graph_grouped_identity'}), results: filteredResult([{id: 1, score: 20}]), sourceReadCount: 0},
  ...['(a)', '(((a)))', '(`A`)'].map((argument, index) =>
    filteredSourceCase('grouped-identity-' + index,
      'WHERE NODE_ID(' + argument + ') IS NOT NULL AND a.payload.score > @min '
        + '|> SELECT a.id AS id, a.payload.score AS score', [{id: 1, score: 20}],
      {parameterDeclarations: {...declarations, min: number}, parameters: {...parameters, min: 10}})),
  filteredSourceCase('grouped-identity-typed-empty',
    'WHERE NODE_ID((a)) IS NOT NULL AND a.payload.score > 100 '
      + '|> SELECT a.id AS id, a.payload.score AS score', []),
  {name: 'graph-projection-property-grouped-path-independent-json', format: 'json',
    text: JSON.stringify({...pathProgram, id: 'fixture.graph_grouped_path'}), results: pathResult, sourceReadCount: 0},
  ...['p', '((p))', '(`P`)'].map((argument, index) => ({
    name: 'graph-projection-property-grouped-path-' + index, format: 'aql-text',
    text: pathData + pathGraph + 'FROM GRAPH g |> MATCH p = WALK (a:Node)-[:R]->(b:Node) '
      + '|> SELECT PATH_LENGTH(' + argument + ') AS depth |> ORDER BY depth |> RESULT matched',
    results: pathResult, sourceReadCount: 0,
  })),
  {name: 'graph-projection-property-identity-independent-json', format: 'json',
    text: JSON.stringify(identityProgram), results: filteredResult([{id: 1, score: 20}]), sourceReadCount: 0},
  ...['`NODE_ID`', '`nOdE_iD`', '`\\x4eODE_ID`'].map((name, index) =>
    filteredSourceCase('quoted-identity-' + index,
      'WHERE ' + name + '(`A`) IS NOT NULL AND a.payload.score > @min '
        + '|> SELECT a.id AS id, a.payload.score AS score', [{id: 1, score: 20}],
      {parameterDeclarations: {...declarations, min: number}, parameters: {...parameters, min: 10}})),
  filteredSourceCase('quoted-identity-typed-empty',
    'WHERE `NODE_ID`(a) IS NOT NULL AND a.payload.score > 100 '
      + '|> SELECT a.id AS id, a.payload.score AS score', []),
  {name: 'graph-projection-property-path-independent-json', format: 'json',
    text: JSON.stringify(pathProgram), results: pathResult, sourceReadCount: 0},
  ...['PATH_LENGTH', '`pAtH_lEnGtH`', '`\\x50ATH_LENGTH`'].map((name, index) => ({
    name: 'graph-projection-property-quoted-path-' + index, format: 'aql-text',
    text: pathData + pathGraph + 'FROM GRAPH g |> MATCH p = WALK (a:Node)-[:R]->(b:Node) '
      + '|> SELECT ' + name + '(`P`) AS depth |> ORDER BY depth |> RESULT matched',
    results: pathResult, sourceReadCount: 0,
  })),
  sourceCase('null-receiver-and-member',
    'WHERE a.payload.score IS NULL |> SELECT a.id AS id, a.payload.score AS score',
    [{id: 3, score: null}, {id: 4, score: null}]),
  filteredSourceCase('typed-empty',
    'WHERE a.payload.score > 100 |> SELECT a.id AS id, a.payload.score AS score', []),
  sourceCase('projected-object-current-scope',
    'SELECT a.id AS id, a.payload AS kept |> SELECT id, kept.score AS score'),
  sourceCase('folded-qualified-member', 'SELECT a.id AS id, a.payload.SCORE AS score'),
  sourceCase('folded-quoted-member', 'SELECT `A`.`ID` AS id, `A`.`PAYLOAD`.`ScOrE` AS score'),
  sourceCase('folded-projected-receiver',
    'SELECT a.id AS id, a.payload AS kept |> SELECT id, kept.SCORE AS score'),
  sourceCase('folded-null-receiver-and-member',
    'WHERE a.payload.SCORE IS NULL |> SELECT a.id AS id, a.payload.SCORE AS score',
    [{id: 3, score: null}, {id: 4, score: null}]),
  filteredSourceCase('folded-typed-empty',
    'WHERE a.payload.SCORE > 100 |> SELECT a.id AS id, a.payload.SCORE AS score', []),
];
export const graphProjectionPropertyRefusals = [
  ['foreign-receiver', 'SELECT other.payload.score AS score'],
  ['missing-member', 'SELECT a.payload.missing AS score'],
  ['folded-missing-member', 'SELECT a.payload.MISSING AS score'],
  ['scalar-receiver', 'SELECT a.id.score AS score'],
  ['removed-graph-variable', 'SELECT a.id AS id |> WHERE a.payload.score > 0'],
  ['grouped-macro-property', 'SELECT NODE_ID((a.payload)) AS score'],
  ['grouped-macro-expression', 'SELECT NODE_ID((a + 1)) AS score'],
  ['grouped-macro-wrong-role', 'SELECT PATH_LENGTH((a)) AS score'],
  ['grouped-macro-wrong-arity', 'SELECT NODE_ID((a), (a)) AS score'],
  ['grouped-macro-removed-binding', 'SELECT a.id AS id |> WHERE NODE_ID((a)) IS NOT NULL'],
  ['same-select-alias', 'SELECT a.payload AS kept, kept.score AS score'],
  ['quoted-unknown-macro', 'SELECT `UNKNOWN`(a) AS score'],
  ['quoted-macro-namespace', 'SELECT `ACTQL`.`NODE_ID`(a) AS score'],
  ['quoted-macro-wrong-role', 'SELECT `PATH_LENGTH`(a) AS score'],
  ['quoted-macro-wrong-arity', 'SELECT `NODE_ID`(a, a) AS score'],
  ['quoted-macro-removed-binding', 'SELECT a.id AS id |> WHERE `NODE_ID`(a) IS NOT NULL'],
].map(([name, tail]) => ({name: 'graph-projection-property-invalid-' + name,
  format: 'aql-text', text: head + tail, parameterDeclarations: declarations, parameters,
  ...(name === 'grouped-macro-property'
    ? {expectedCode: 'ClientProgramImplementationLimit'} : {})}));
