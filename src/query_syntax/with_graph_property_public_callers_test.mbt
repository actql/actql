///|
// Exact authored public sources. Parsing is executed here; installed Source
// acquisition, Graph admission and Host publication remain separate obligations.

///|
test "WITH Graph/property public caller acquired-graph-direct-source-static-label" {
  let script = parse_query_script("WITH g AS (GRAPH (NODE TABLES (records AS N KEY (id) LABEL Person PROPERTIES (amount, id)))) FROM GRAPH g |> MATCH (a:Person) |> SELECT a.amount AS amount, a.id AS id |> ORDER BY id |> RESULT people", query_limits()).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH Graph/property public caller acquired-graph-null-key-exclusion" {
  let script = parse_query_script("WITH g AS (GRAPH (NODE TABLES (records AS N KEY (amount) LABEL Person PROPERTIES (amount, id)))) FROM GRAPH g |> MATCH (a:Person) |> SELECT a.amount AS amount, a.id AS id |> RESULT people", query_limits()).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH Graph/property public caller acquired-graph-parallel-edge-trail" {
  let script = parse_query_script("WITH n AS (SELECT 1 AS id), e AS (FROM records |> SELECT id AS key, 1 AS src, 1 AS dst), g AS (GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES) EDGE TABLES (e AS E KEY (key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES))) FROM GRAPH g |> MATCH p = TRAIL (:Node)-[:R]->(:Node)-[:R]->(:Node) |> SELECT PATH_LENGTH(p) AS depth |> RESULT paths", query_limits()).unwrap()
  assert_eq(query_binding_count(script_query(script)), 3)
}

///|
test "WITH Graph/property public caller order-property-selected-property-receiver-collision" {
  let script = parse_query_script("WITH objects AS (SELECT 2 AS id, @a AS payload, @oa AS other UNION ALL SELECT 1 AS id, @b AS payload, @ob AS other UNION ALL SELECT 3 AS id, @c AS payload, @oc AS other) SELECT id, payload.score AS original_score, other AS payload FROM objects ORDER BY payload.score NULLS LAST", query_limits()).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH Graph/property public caller analytic-property-sql-lag" {
  let script = parse_query_script("WITH objects AS (SELECT 2 AS id, @a AS payload, @oa AS other UNION ALL SELECT 1 AS id, @b AS payload, @ob AS other UNION ALL SELECT 3 AS id, @c AS payload, @oc AS other) SELECT id, LAG(payload.score) OVER (ORDER BY id) AS previous FROM objects ORDER BY id", query_limits()).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH Graph/property public caller distinct-order-member-sql-path" {
  let script = parse_query_script("WITH objects AS (SELECT id, amount AS score, CASE WHEN id = 2 THEN @a WHEN id = 1 OR id = 4 THEN @b WHEN id = 5 THEN @d ELSE @c END AS payload, CASE WHEN id = 2 THEN @b ELSE @a END AS other FROM records WHERE id > 0) SELECT DISTINCT payload.score AS score FROM objects ORDER BY -payload.score NULLS LAST", query_limits()).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}

///|
test "WITH Graph/property public caller distinct-order-receiver-unshadowed-input" {
  let script = parse_query_script("WITH objects AS (SELECT amount AS score FROM records WHERE id > 0) SELECT DISTINCT score AS original_score, -score AS payload FROM objects AS original ORDER BY original.score + 1 NULLS LAST", query_limits()).unwrap()
  assert_eq(query_binding_count(script_query(script)), 1)
}
