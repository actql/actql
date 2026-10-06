///|
fn keyed_script(text : String) -> Result[@program.Program, Issue] {
  compile_query_script(
    @query.parse_query_script(text, mapping_syntax_limits()).unwrap(),
    mapping_context(),
    mapping_limits(),
  )
}

///|
test "keyed properties reuse canonical spelling across labels of one definition" {
  let prefix = "DATA n = SELECT 1 AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Primary PROPERTIES (id AS ID) LABEL Secondary PROPERTIES (id AS id))); "
  for pattern in ["(a:secondary WHERE `Id` = 1)", "(a WHERE `Id` = 1)"] {
    let body = mapping_semantic(
      keyed_script(
        prefix +
        "FROM GRAPH g |> MATCH WALK " +
        pattern +
        " |> SELECT a.id AS id",
      ).unwrap(),
    )
    assert_true(body.contains("\"fields\":[\"aql_keyed_identity_1\",\"ID\"]"))
    assert_true(body.contains("\"eq\":[{\"field\":\"ID\"},{\"literal\":1}]"))
  }
}

///|
test "keyed node predicates resolve properties without replacing label membership" {
  let prefix = "DATA n = SELECT 1 AS id, 'Company' AS entity_type; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Person PROPERTIES (id, entity_type))); "
  for
    constraint in [
      "WHERE entity_type = 'Company'", "WHERE `a`.`ENTITY_TYPE` = 'Company'", "{entity_type: 'Company'}",
    ] {
    let actual = keyed_script(
      prefix +
      "FROM GRAPH g |> MATCH WALK (a:Person " +
      constraint +
      ") |> SELECT a.id",
    ).unwrap()
    let body = mapping_semantic(actual)
    assert_true(body.contains("\"label\":\"Person\""))
    assert_true(
      body.contains(
        "\"eq\":[{\"field\":\"entity_type\"},{\"literal\":\"Company\"}]",
      ),
    )
    assert_false(body.contains("\"literal\":\"Person\""))
  }
}

///|
test "keyed source node labels are membership and NODE_ID is the full identity slot" {
  let prefix = "DATA n = SELECT 1 AS id, 'Company' AS entity_type; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Person PROPERTIES (id, entity_type))); "
  let actual = keyed_script(
    prefix + "FROM GRAPH g |> MATCH WALK (a:Person) |> SELECT a.id",
  ).unwrap()
  // Independently authored ordinary Program. Person is static membership;
  // the unrelated Company property is preserved and never used as the label.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":"Company"}}},{"select":[{"id":"aql_query_expr_0"},{"entity_type":"aql_query_expr_1"}],"as":"aql_data_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["id"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"id","to":"id"},{"from":"entity_type","to":"entity_type"}]}}]}],"edges":[]},"as":"aql_data_2"},{"from":"aql_data_2","match_nodes":{"definition":"N","label":"Person","where":{"literal":true},"bindings":{"identity":"aql_keyed_identity_2"},"fields":["aql_keyed_identity_2","id","entity_type"]},"as":"aql_keyed_seeds_3"},{"from":"aql_keyed_seeds_3","select":["id"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    mapping_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(mapping_semantic(actual), mapping_semantic(expected))
  let default_mode = keyed_script(
    prefix + "FROM GRAPH g |> MATCH (a:Person) |> SELECT a.id",
  ).unwrap()
  assert_eq(mapping_semantic(default_mode), mapping_semantic(expected))
  let binding : GraphBinding = {
    variable: { value: "a", quoted: false, },
    prefix: "",
    fields: ["id", "entity_type"],
    kind: NodeIdentity("identity_slot"),
    hops: 0,
    label_field: None,
  }
  assert_true(
    graph_macro_value(
      [{ value: "NODE_ID", quoted: false, }],
      [{ value: "a", quoted: false, }],
      [binding],
    )
    is Some(@expression.Field("identity_slot")),
  )
}

///|
test "keyed source path modes lower to the existing traversal with full identity selectors" {
  // Two independent edge definitions share the endpoints. The existing
  // same-definition parallel-edge fixture is retained separately. This
  // test verifies source ownership/mode lowering, not path execution counts.
  let prefix = "DATA n = SELECT 1 AS id; DATA e = SELECT 10 AS key, 1 AS src, 1 AS dst; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES) EDGE TABLES (e AS E KEY (key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES, e AS F KEY (key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES)); "
  for
    (mode, wire) in [
      ("WALK", "walk"),
      ("", "walk"),
      ("TRAIL", "trail"),
      ("ACYCLIC", "acyclic"),
    ] {
    let program = keyed_script(
      prefix +
      "FROM GRAPH g |> MATCH p = " +
      mode +
      " (:Node)-[:R]->(:Node)-[:R]->(:Node) |> SELECT PATH_LENGTH(p) AS depth",
    ).unwrap()
    let body = mapping_semantic(program)
    assert_true(body.contains("\"path_mode\":\"" + wire + "\""))
    assert_true(body.contains("\"emit\":\"paths\""))
    assert_true(
      body.contains(
        "\"hops\":[{\"direction\":\"out\",\"edge_types\":[\"R\"]},{\"direction\":\"out\",\"edge_types\":[\"R\"]}]",
      ),
    )
    assert_true(
      body.contains(
        "\"start\":{\"from\":\"aql_keyed_seeds_5\",\"id\":\"aql_keyed_identity_0\"}",
      ),
    )
    assert_true(body.contains("\"fields\":[\"depth\"]"))
    assert_true(!body.contains("\"join\":") && !body.contains("\"sort\":"))
    assert_eq(@program.stage_count(program), 1)
    assert_eq(@program.export_count(program), 1)
  }
}

///|
test "keyed source refuses internal Graph star and unadapted identity binding" {
  let prefix = "DATA n = SELECT 1 AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node PROPERTIES (id))); "
  assert_true(
    keyed_script(prefix + "FROM GRAPH g |> MATCH WALK (a)")
    is Err(UnsupportedProjection),
  )
  assert_true(
    keyed_script(prefix + "FROM GRAPH g |> MATCH WALK (a) |> SELECT *")
    is Err(UnsupportedProjection),
  )
  assert_true(
    keyed_script(
      prefix + "FROM GRAPH g |> MATCH WALK (a) |> SELECT a.id |> SELECT *",
    )
    is Ok(_),
  )
  assert_true(
    keyed_script(
      prefix + "FROM GRAPH g |> MATCH WALK (a) |> SELECT aql_keyed_identity_1",
    )
    is Err(UnknownColumn),
  )
  assert_true(
    keyed_script(
      prefix +
      "FROM GRAPH g |> MATCH p = ACYCLIC (a)-[]->{0,2}(a) |> SELECT PATH_LENGTH(p) AS depth",
    )
    is Err(UnsupportedGraph),
  )
  assert_true(
    keyed_script(
      prefix +
      "FROM GRAPH g LABELS {\"node\":{\"field\":\"id\"}} |> MATCH WALK (a:Node) |> SELECT a.id",
    )
    is Err(UnsupportedGraph),
  )
}
