// Independent expectations for the new source route. This app does not
// import the frontend or manufacture a checked Program/Graph at runtime.
const number = name => ({name, contract: {type: 'number', nullable: false}});
const nodes = "DATA n = SELECT 1 AS id, 'Company' AS entity_type; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Person PROPERTIES (id, entity_type))); ";
// These are distinct element definitions with distinct keys. They exercise
// definition-scoped identity through source routing. Same-definition,
// two-row parallel edges are a separate obligation, not proved by this case.
const loops = "DATA n = SELECT 1 AS id; DATA e = SELECT 10 AS key, 1 AS src, 1 AS dst; DATA f = SELECT 11 AS key, 1 AS src, 1 AS dst; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES) EDGE TABLES (e AS E KEY (key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES, f AS F KEY (key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES)); ";
const parallel = "DATA n = SELECT 1 AS id; DATA e = SELECT 10 AS key, 1 AS src, 1 AS dst UNION ALL SELECT 11 AS key, 1 AS src, 1 AS dst; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES) EDGE TABLES (e AS E KEY (key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES)); ";
const nodeGraph = data => data + ' DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node PROPERTIES (id))); ';
const edgeGraph = data => 'DATA n = SELECT 1 AS id; ' + data +
  ' DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES) EDGE TABLES (e AS E KEY (key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES)); ';
const scopedNodes = label => "DATA p = SELECT 1 AS id, 'Person' AS tag; DATA c = SELECT 1 AS id, 'Firmxx' AS tag; DATA g = PROPERTY GRAPH (NODE TABLES (p AS P KEY (id) LABEL Node PROPERTIES (id, tag), c AS C KEY (id) LABEL " + label + ' PROPERTIES (tag, id))); ';
const scopedEndpoint = 'DATA n = SELECT 1 AS id; DATA e = SELECT 10 AS key, 1 AS src, 1 AS dst; DATA g = PROPERTY GRAPH (NODE TABLES (n AS P KEY (id) LABEL Person NO PROPERTIES, n AS C KEY (id) LABEL Company NO PROPERTIES) EDGE TABLES (e AS E KEY (key) SOURCE KEY (src) REFERENCES P DESTINATION KEY (dst) REFERENCES C LABEL R NO PROPERTIES)); ';
const labelSpelling = 'DATA n = SELECT 1 AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Primary PROPERTIES (id AS ID) LABEL Secondary PROPERTIES (id AS id))); ';
const scopedColumns = [number('id'), {name: 'tag', contract: {type: 'string', nullable: false, max_utf8_bytes: 6}}];
export const graphSourceSuccesses = [
  {name: 'data-set-order-reuses-hidden-slot', format: 'aql-text',
    text: 'DATA n = SELECT 2 AS id UNION ALL SELECT 1 AS other ORDER BY id + 1, id + 1 DESC LIMIT 1; FROM n |> SELECT id |> RESULT nodes',
    results: {nodes: {rows: [{id: 1}], columns: [number('id')]}}, sourceReadCount: 0},
  {name: 'data-quoted-set-order', format: 'aql-text',
    text: 'DATA `n` = SELECT 2 AS id UNION ALL SELECT 1 AS other ORDER BY id; FROM `n` |> SELECT id |> RESULT nodes',
    results: {nodes: {rows: [{id: 1}, {id: 2}], columns: [number('id')]}}, sourceReadCount: 0},
  {name: 'data-retained-results', format: 'aql-text',
    text: 'DATA n = SELECT 2 AS id; FROM n |> RESULT original |> WHERE id > 0 |> RESULT active',
    results: {original: {rows: [{id: 2}], columns: [number('id')]},
      active: {rows: [{id: 2}], columns: [number('id')]}}, sourceReadCount: 0},
  {name: 'keyed-static-label', format: 'aql-text',
    text: nodes + 'FROM GRAPH g |> MATCH WALK (a:Person) |> SELECT a.id AS id, a.entity_type AS category |> RESULT people',
    results: {people: {rows: [{id: 1, category: 'Company'}], columns: [number('id'),
      {name: 'category', contract: {type: 'string', nullable: false, max_utf8_bytes: 7}}]}},
    sourceReadCount: 0},
  {name: 'keyed-normalized-graph-consumer', format: 'aql-text',
    text: nodes + 'FROM GRAPH g |> normalize_graph() |> MATCH WALK (a:Person) |> SELECT a.id AS id |> RESULT people',
    results: {people: {rows: [{id: 1}], columns: [number('id')]}},
    sourceReadCount: 0},
  {name: 'keyed-empty-property-filter', format: 'aql-text',
    text: nodes + "FROM GRAPH g |> MATCH WALK (a:Person WHERE entity_type = 'Person') |> SELECT a.id AS id |> RESULT people",
    results: {people: {rows: [], columns: [number('id')]}}, sourceReadCount: 0},
  {name: 'keyed-default-node-mode', format: 'aql-text',
    text: nodes + 'FROM GRAPH g |> MATCH (a:Person) |> SELECT a.id AS id, a.entity_type AS category |> RESULT people',
    results: {people: {rows: [{id: 1, category: 'Company'}], columns: [number('id'),
      {name: 'category', contract: {type: 'string', nullable: false, max_utf8_bytes: 7}}]}}, sourceReadCount: 0},
  {name: 'keyed-explicit-projection-star', format: 'aql-text',
    text: nodes + 'FROM GRAPH g |> MATCH WALK (`a`:Person) |> SELECT `a`.`ID` AS id |> SELECT * |> RESULT people',
    results: {people: {rows: [{id: 1}], columns: [number('id')]}}, sourceReadCount: 0},
  ...[['WALK', 4], ['', 4], ['TRAIL', 2], ['ACYCLIC', 0]].map(([mode, count]) => ({
    name: 'keyed-scoped-loops-' + (mode ? mode.toLowerCase() : 'default-walk'), format: 'aql-text',
    text: loops + 'FROM GRAPH g |> MATCH p = ' + mode +
      ' (:Node)-[:R]->(:Node)-[:R]->(:Node) |> SELECT PATH_LENGTH(p) AS depth |> RESULT paths',
    results: {paths: {rows: Array.from({length: count}, () => ({depth: 2})),
      columns: [number('depth')]}}, sourceReadCount: 0,
  })),
  ...[['WALK', 4], ['', 4], ['TRAIL', 2], ['ACYCLIC', 0]].map(([mode, count]) => ({
    name: 'keyed-parallel-one-definition-' + (mode ? mode.toLowerCase() : 'default-walk'), format: 'aql-text',
    text: parallel + 'FROM GRAPH g |> MATCH p = ' + mode +
      ' (:Node)-[:R]->(:Node)-[:R]->(:Node) |> SELECT PATH_LENGTH(p) AS depth |> RESULT paths',
    results: {paths: {rows: Array.from({length: count}, () => ({depth: 2})),
      columns: [number('depth')]}}, sourceReadCount: 0,
  })),
  {name: 'keyed-composite-node-keys', format: 'aql-text',
    text: 'DATA n = SELECT 1 AS part, 23 AS id UNION ALL SELECT 12 AS part, 3 AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (part, id) LABEL Node PROPERTIES (part, id))); FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.part AS part, a.id AS id |> RESULT nodes',
    results: {nodes: {rows: [{part: 1, id: 23}, {part: 12, id: 3}],
      columns: [number('part'), number('id')], unordered: true}}, sourceReadCount: 0},
  {name: 'keyed-composite-edge-keys', format: 'aql-text',
    text: 'DATA n = SELECT 1 AS id; DATA e = SELECT 7 AS part, 1 AS seq, 1 AS src, 1 AS dst UNION ALL SELECT 7 AS part, 2 AS seq, 1 AS src, 1 AS dst; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES) EDGE TABLES (e AS E KEY (part, seq) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES)); FROM GRAPH g |> MATCH p = TRAIL (:Node)-[:R]->(:Node)-[:R]->(:Node) |> SELECT PATH_LENGTH(p) AS depth |> RESULT paths',
    results: {paths: {rows: [{depth: 2}, {depth: 2}], columns: [number('depth')]}}, sourceReadCount: 0},
  {name: 'keyed-null-node-key-exclusion', format: 'aql-text',
    text: nodeGraph('DATA n = SELECT 1 AS id UNION ALL SELECT CAST(NULL AS FLOAT64) AS id;') +
      'FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.id AS id |> RESULT nodes',
    results: {nodes: {rows: [{id: 1}], columns: [{name: 'id', contract: {type: 'number', nullable: true}}]}}, sourceReadCount: 0},
  {name: 'keyed-all-null-key-typed-empty', format: 'aql-text',
    text: nodeGraph('DATA n = SELECT CAST(NULL AS FLOAT64) AS id;') +
      'FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.id AS id |> RESULT nodes',
    results: {nodes: {rows: [], columns: [{name: 'id', contract: {type: 'number', nullable: true}}]}}, sourceReadCount: 0},
  {name: 'keyed-null-key-and-unmatched-endpoint-exclusion', format: 'aql-text',
    text: edgeGraph('DATA e = SELECT 10 AS key, 1 AS src, 1 AS dst UNION ALL SELECT CAST(NULL AS FLOAT64) AS key, 1 AS src, 1 AS dst UNION ALL SELECT 11 AS key, 2 AS src, 1 AS dst UNION ALL SELECT 12 AS key, CAST(NULL AS FLOAT64) AS src, 1 AS dst;') +
      'FROM GRAPH g |> MATCH p = WALK (:Node)-[:R]->(:Node) |> SELECT PATH_LENGTH(p) AS depth |> RESULT paths',
    results: {paths: {rows: [{depth: 1}], columns: [number('depth')]}}, sourceReadCount: 0},
  {name: 'keyed-static-label-set', format: 'aql-text',
    text: 'DATA n = SELECT 1 AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Person PROPERTIES (id) LABEL Account PROPERTIES (id))); FROM GRAPH g |> MATCH WALK (a:account) |> SELECT a.id AS id |> RESULT nodes',
    results: {nodes: {rows: [{id: 1}], columns: [number('id')]}}, sourceReadCount: 0},
  ...[['Node', 'Person'], ['`coMPaNY`', 'Firmxx']].map(([label, tag]) => ({
    name: 'keyed-definition-label-' + tag, format: 'aql-text',
    text: scopedNodes('Company') + 'FROM GRAPH g |> MATCH WALK (a:' + label + ') |> SELECT a.id, a.tag |> RESULT nodes',
    results: {nodes: {rows: [{id: 1, tag}], columns: scopedColumns}}, sourceReadCount: 0,
  })),
  {name: 'keyed-shared-label-definition-multiplicity', format: 'aql-text',
    text: scopedNodes('Node') + 'FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.id, a.tag |> RESULT nodes',
    results: {nodes: {rows: [{id: 1, tag: 'Person'}, {id: 1, tag: 'Firmxx'}],
      columns: scopedColumns, unordered: true}}, sourceReadCount: 0},
  {name: 'keyed-definition-scoped-endpoint', format: 'aql-text',
    text: scopedEndpoint + 'FROM GRAPH g |> MATCH p = ACYCLIC (:Person)-[:R]->() |> SELECT PATH_LENGTH(p) AS depth |> RESULT paths',
    results: {paths: {rows: [{depth: 1}], columns: [number('depth')]}}, sourceReadCount: 0},
  ...[['secondary', '(a:secondary WHERE `Id` = 1)'], ['all-labels', '(a WHERE `Id` = 1)']].map(([name, pattern]) => ({
    name: 'keyed-property-spelling-' + name, format: 'aql-text',
    text: labelSpelling + 'FROM GRAPH g |> MATCH WALK ' + pattern + ' |> SELECT a.id AS id |> RESULT nodes',
    results: {nodes: {rows: [{id: 1}], columns: [number('id')]}}, sourceReadCount: 0,
  })),
  {name: 'keyed-property-spelling-definitions', format: 'aql-text',
    text: scopedNodes('Node').replace('PROPERTIES (tag, id)', 'PROPERTIES (id AS ID, tag AS TAG)') +
      'FROM GRAPH g |> MATCH WALK (a:Node WHERE `Id` = 1) |> SELECT a.id, a.tag |> ORDER BY tag |> RESULT nodes',
    results: {nodes: {rows: [{id: 1, tag: 'Firmxx'}, {id: 1, tag: 'Person'}],
      columns: scopedColumns}}, sourceReadCount: 0},
];
export const graphSourceExecutionFailures = [
  {name: 'keyed-duplicate-node-key', format: 'aql-text',
    text: nodeGraph('DATA n = SELECT 1 AS id UNION ALL SELECT 1 AS id;') +
      'FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.id AS id |> RESULT nodes', resultNames: ['nodes'], sourceReadCount: 0},
  {name: 'keyed-duplicate-edge-key', format: 'aql-text',
    text: edgeGraph('DATA e = SELECT 10 AS key, 1 AS src, 1 AS dst UNION ALL SELECT 10 AS key, 1 AS src, 1 AS dst;') +
      'FROM GRAPH g |> MATCH p = WALK (:Node)-[:R]->(:Node) |> SELECT PATH_LENGTH(p) AS depth |> RESULT paths', resultNames: ['paths'], sourceReadCount: 0},
  {name: 'keyed-duplicate-before-endpoint-exclusion', format: 'aql-text',
    text: edgeGraph('DATA e = SELECT 10 AS key, 1 AS src, 1 AS dst UNION ALL SELECT 10 AS key, 2 AS src, 1 AS dst;') +
      'FROM GRAPH g |> MATCH p = WALK (:Node)-[:R]->(:Node) |> SELECT PATH_LENGTH(p) AS depth |> RESULT paths', resultNames: ['paths'], sourceReadCount: 0},
];
export const graphSourceRefusals = [
  {name: 'keyed-property-spelling-source-collision', format: 'aql-text',
    text: 'DATA n = SELECT 1 AS id, 2 AS other; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Primary PROPERTIES (id AS ID) LABEL Secondary PROPERTIES (other AS id))); FROM GRAPH g |> MATCH WALK (a:secondary) |> SELECT a.id AS id'},
  {name: 'keyed-unadapted-endpoint-label', format: 'aql-text', text: scopedEndpoint + 'FROM GRAPH g |> MATCH p = ACYCLIC (:Person)-[:R]->(:Person) |> SELECT PATH_LENGTH(p) AS depth'},
  {name: 'keyed-unadapted-heterogeneous-binding', format: 'aql-text',
    text: scopedNodes('Company').replace('LABEL Company PROPERTIES (tag, id)', 'LABEL Company PROPERTIES (id)') +
      'FROM GRAPH g |> MATCH WALK (a) |> SELECT a.tag'},
  {name: 'unsupported-mean-consumer', format: 'aql-text', text: nodes + 'DATA combined = mean_graphs(with: [g, g]); FROM GRAPH combined |> MATCH WALK (a:Person) |> SELECT a.id'},
  {name: 'keyed-star', format: 'aql-text', text: nodes + 'FROM GRAPH g |> MATCH WALK (a) |> SELECT *'},
  {name: 'keyed-implicit-element-export', format: 'aql-text', text: nodes + 'FROM GRAPH g |> MATCH WALK (a)'},
  {name: 'keyed-missing-binding', format: 'aql-text', text: nodes + 'FROM GRAPH missing |> MATCH WALK (a) |> SELECT a.id'},
  {name: 'keyed-missing-property', format: 'aql-text', text: nodes + 'FROM GRAPH g |> MATCH WALK (a) |> SELECT a.missing'},
  {name: 'keyed-private-slot', format: 'aql-text', text: nodes + 'FROM GRAPH g |> MATCH WALK (a) |> SELECT aql_keyed_identity_2'},
  {name: 'retired-constructor', format: 'aql-text', text: 'DATA g = graph(nodes: n); FROM GRAPH g |> MATCH WALK (a) |> SELECT a.id'},
  {name: 'data-forward-reference', format: 'aql-text', text: 'DATA n = FROM later |> SELECT id; DATA later = SELECT 1 AS id; FROM n |> SELECT id'},
  {name: 'data-duplicate', format: 'aql-text', text: 'DATA n = SELECT 1 AS id; DATA `N` = SELECT 2 AS id; FROM n |> SELECT id'},
  {name: 'data-sql-format', format: 'sql', text: 'DATA n = SELECT 1 AS id; FROM n |> SELECT id'},
];
