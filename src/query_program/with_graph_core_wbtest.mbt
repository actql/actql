///|
// Parallel edges and labels reach the existing Graph owner without a legacy
// graph adapter. These are static checks; path multiplicity is a Host obligation.
test "WITH core parallel Graph preserves declared path modes and keys" {
  let source = "WITH n AS (SELECT 1 AS id), e AS (SELECT 10 AS key, 1 AS src, 1 AS dst UNION ALL SELECT 11 AS key, 1 AS src, 1 AS dst), g AS (GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES) EDGE TABLES (e AS E KEY (key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES))) "
  for (mode, expected) in [("WALK", "walk"), ("", "walk"), ("TRAIL", "trail"), ("ACYCLIC", "acyclic")] {
    let actual = keyed_script(
      source + "FROM GRAPH g |> MATCH p = " + mode +
      " (:Node)-[:R]->{2,2}(:Node) |> SELECT PATH_LENGTH(p) AS depth",
    ).unwrap()
    let body = mapping_semantic(actual)
    assert_true(body.contains("\"key\":[\"key\"]"))
    assert_true(body.contains("\"path_mode\":\"" + expected + "\""))
    assert_true(body.contains("\"min_hops\":2"))
    assert_true(body.contains("\"max_hops\":2"))
  }
}

///|
test "WITH core composite node key retains ordered key components" {
  let body = mapping_semantic(keyed_script(
    "WITH n AS (SELECT 1 AS part, 23 AS id UNION ALL SELECT 12 AS part, 3 AS id), g AS (GRAPH (NODE TABLES (n AS N KEY (part, id) LABEL Node PROPERTIES (part, id)))) FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.part AS part, a.id AS id",
  ).unwrap())
  assert_true(body.contains("\"key\":[\"part\",\"id\"]"))
  assert_true(body.contains("\"label\":\"Node\""))
  assert_true(body.contains("\"fields\":[\"part\",\"id\"]"))
}

///|
test "WITH core NULL key admission retains conditional runtime obligations" {
  for relation in [
    "SELECT 1 AS id UNION ALL SELECT CAST(NULL AS FLOAT64) AS id",
    "SELECT CAST(NULL AS FLOAT64) AS id",
    "SELECT 1 AS id UNION ALL SELECT 1 AS id",
  ] {
    let actual = keyed_script(
      "WITH n AS (" + relation + "), g AS (GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node PROPERTIES (id)))) FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.id AS id",
    )
    // Duplicate keys are not proven unique by Frontend and are not made static
    // errors. The execution fixture separately requires owner rejection.
    assert_true(actual is Ok(_))
  }
}
