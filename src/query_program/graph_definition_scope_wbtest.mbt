///|
fn definition_scope_prefix(label : String) -> String {
  "DATA p = SELECT 1 AS id, 'Person' AS tag; DATA c = SELECT 1 AS id, 'Firmxx' AS tag; DATA g = PROPERTY GRAPH (NODE TABLES (p AS P KEY (id) LABEL Node PROPERTIES (id, tag), c AS C KEY (id) LABEL " +
  label +
  " PROPERTIES (tag, id))); "
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
test "keyed equivalent property spelling is projected before definition append" {
  let source = "DATA p = SELECT 1 AS id, 'Person' AS tag; DATA c = SELECT 1 AS id, 'Firmxx' AS tag; DATA g = PROPERTY GRAPH (NODE TABLES (p AS P KEY (id) LABEL Node PROPERTIES (id, tag), c AS C KEY (id) LABEL Node PROPERTIES (id AS ID, tag AS TAG))); FROM GRAPH g |> MATCH WALK (a:Node WHERE `Id` = 1) |> SELECT a.id, a.tag"
  let actual = keyed_script(source).unwrap()
  // Independently authored Program. Each predicate uses its own checked
  // property name, then ordinary projection aligns equivalent names before
  // append. The complete Graph identity binding is retained unchanged.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":"Person"}}},{"select":[{"id":"aql_query_expr_0"},{"tag":"aql_query_expr_1"}],"as":"aql_data_0"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_3"},{"from":"aql_script_seed_3","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":"Firmxx"}}},{"select":[{"id":"aql_query_expr_0"},{"tag":"aql_query_expr_1"}],"as":"aql_data_2"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"P","from":"aql_data_0","key":["id"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"id","to":"id"},{"from":"tag","to":"tag"}]}}]},{"name":"C","from":"aql_data_2","key":["id"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"id","to":"ID"},{"from":"tag","to":"TAG"}]}}]}],"edges":[]},"as":"aql_data_4"},{"from":"aql_data_4","match_nodes":{"definition":"P","label":"Node","where":{"eq":[{"field":"id"},{"literal":1}]},"bindings":{"identity":"aql_keyed_identity_2"},"fields":["aql_keyed_identity_2","id","tag"]},"as":"aql_keyed_seeds_5"},{"from":"aql_data_4","match_nodes":{"definition":"C","label":"Node","where":{"eq":[{"field":"ID"},{"literal":1}]},"bindings":{"identity":"aql_keyed_identity_2"},"fields":["aql_keyed_identity_2","ID","TAG"]},"as":"aql_keyed_seeds_6"},{"from":"aql_keyed_seeds_6","select":["aql_keyed_identity_2",{"id":"ID"},{"tag":"TAG"}],"as":"aql_keyed_seeds_7"},{"from":"aql_keyed_seeds_5","append":{"with":"aql_keyed_seeds_7"},"as":"aql_keyed_seeds_8"},{"from":"aql_keyed_seeds_8","select":["id","tag"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id","tag"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    mapping_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(mapping_semantic(actual), mapping_semantic(expected))
}

///|
test "keyed shared label preserves two definition-scoped matches with ordinary append" {
  let actual = keyed_script(
    definition_scope_prefix("Node") +
    "FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.id, a.tag",
  ).unwrap()
  // Independent ordinary Program: each definition is matched once. Appending
  // the two Relations retains duplicate scalar IDs and full scoped identities;
  // neither DISTINCT nor a guessed scalar identity join belongs here.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":"Person"}}},{"select":[{"id":"aql_query_expr_0"},{"tag":"aql_query_expr_1"}],"as":"aql_data_0"},{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_3"},{"from":"aql_script_seed_3","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":"Firmxx"}}},{"select":[{"id":"aql_query_expr_0"},{"tag":"aql_query_expr_1"}],"as":"aql_data_2"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"P","from":"aql_data_0","key":["id"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"id","to":"id"},{"from":"tag","to":"tag"}]}}]},{"name":"C","from":"aql_data_2","key":["id"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"tag","to":"tag"},{"from":"id","to":"id"}]}}]}],"edges":[]},"as":"aql_data_4"},{"from":"aql_data_4","match_nodes":{"definition":"P","label":"Node","where":{"literal":true},"bindings":{"identity":"aql_keyed_identity_2"},"fields":["aql_keyed_identity_2","id","tag"]},"as":"aql_keyed_seeds_5"},{"from":"aql_data_4","match_nodes":{"definition":"C","label":"Node","where":{"literal":true},"bindings":{"identity":"aql_keyed_identity_2"},"fields":["aql_keyed_identity_2","id","tag"]},"as":"aql_keyed_seeds_6"},{"from":"aql_keyed_seeds_5","append":{"with":"aql_keyed_seeds_6"},"as":"aql_keyed_seeds_7"},{"from":"aql_keyed_seeds_7","select":["id","tag"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id","tag"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    mapping_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(mapping_semantic(actual), mapping_semantic(expected))
}

///|
test "keyed node label selects the corresponding definition with case-insensitive lookup" {
  let source = definition_scope_prefix("Company")
  for (label, definition) in [("Node", "P"), ("`coMPaNY`", "C")] {
    let body = mapping_semantic(
      keyed_script(
        source +
        "FROM GRAPH g |> MATCH WALK (a:" +
        label +
        ") |> SELECT a.id, a.tag",
      ).unwrap(),
    )
    assert_true(body.contains("\"definition\":\"" + definition + "\""))
    assert_false(body.contains("\"append\":"))
  }
}

///|
test "keyed multiple definitions do not erase unsupported endpoint label constraints" {
  let source = "DATA n = SELECT 1 AS id; DATA e = SELECT 10 AS key, 1 AS src, 1 AS dst; DATA g = PROPERTY GRAPH (NODE TABLES (n AS P KEY (id) LABEL Person NO PROPERTIES, n AS C KEY (id) LABEL Company NO PROPERTIES) EDGE TABLES (e AS E KEY (key) SOURCE KEY (src) REFERENCES P DESTINATION KEY (dst) REFERENCES C LABEL R NO PROPERTIES)); "
  assert_true(
    keyed_script(
      source +
      "FROM GRAPH g |> MATCH p = ACYCLIC (:Person)-[:R]->() |> SELECT PATH_LENGTH(p) AS depth",
    )
    is Ok(_),
  )
  assert_true(
    keyed_script(
      source +
      "FROM GRAPH g |> MATCH p = ACYCLIC (:Person)-[:R]->(:Company) |> SELECT PATH_LENGTH(p) AS depth",
    )
    is Err(UnsupportedGraph),
  )
}
