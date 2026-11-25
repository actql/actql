import assert from 'node:assert/strict';
import {open} from '@actql/node';

const graph = `WITH nodes AS (SELECT 1 AS node_key, 7 AS p UNION ALL SELECT 2, 8),
  edges AS (SELECT 1 AS edge_key, 1 AS from_key, 2 AS to_key),
  g AS (GRAPH (NODE TABLES (nodes AS N KEY (node_key) LABEL Person PROPERTIES (p))
    EDGE TABLES (edges AS E KEY (edge_key)
      SOURCE KEY (from_key) REFERENCES N DESTINATION KEY (to_key) REFERENCES N
      LABEL Knows NO PROPERTIES)))
FROM GRAPH g`;

export const originalPathLength = graph +
  ' |> MATCH x = ACYCLIC (:Person)-[:Knows]->(:Person) |> SELECT PATH_LENGTH(x) AS depth';

export async function checkGraphEndpointMatch(stateDir) {
  const db = await open({stateDir});
  try {
    assert.deepEqual(await db.aql(`${graph} |> MATCH WALK (a:Person)-[:Knows]->(b:Person)
|> SELECT a.p AS source, b.p AS reached`).all(), [{source: 7, reached: 8}]);
    assert.deepEqual(await db.aql(`${graph} |> MATCH WALK (a:Person)<-[:Knows]-(b:Person)
|> SELECT a.p AS source, b.p AS reached`).all(), [{source: 8, reached: 7}]);
    const nonTraversalRows = await db.aql(
      `${graph} |> MATCH WALK (a:Person) |> SELECT a.p AS p`).all();
    assert.deepEqual(nonTraversalRows.toSorted((a, b) => a.p - b.p), [{p: 7}, {p: 8}]);
    assert.deepEqual(await db.aql(originalPathLength).all(), [{depth: 1}]);
  } finally {
    await db.close();
  }
}
