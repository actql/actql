///|
test "bounded Graph modes lower to the existing traversal without changing bounds" {
  let prefix = "DATA n = SELECT 1 AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES)); "
  for
    (mode, wire) in [
      ("WALK", "walk"),
      ("", "walk"),
      ("TRAIL", "trail"),
      ("ACYCLIC", "acyclic"),
    ] {
    let actual = compile_data_set(
      prefix +
      "FROM GRAPH g |> MATCH p = " +
      mode +
      " (:Node)-[:R]->{0,2}(:Node) |> SELECT PATH_LENGTH(p) AS depth",
    )
    // The complete ordinary Program is authored independently. Its selector
    // retains the Graph's identity, and the quantifier preserves both bounds.
    let expected = @program.parse(
      (
        #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_data_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["id"],"labels":[{"name":"Node","properties":{"mode":"no_properties"}}]}],"edges":[]},"as":"aql_data_2"},{"from":"aql_data_2","match_nodes":{"definition":"N","label":"Node","where":{"literal":true},"bindings":{"identity":"aql_keyed_identity_0"},"fields":["aql_keyed_identity_0"]},"as":"aql_keyed_seeds_3"},{"from":"aql_data_2","traverse":{"start":{"from":"aql_keyed_seeds_3","id":"aql_keyed_identity_0"},"path_mode":"MODE","emit":"paths","direction":"out","min_hops":0,"max_hops":2,"edge_types":["R"]},"as":"aql_keyed_paths_4"},{"from":"aql_keyed_paths_4","derive":{"aql_query_expr_0":{"field":"hop_count"}}},{"select":[{"depth":"aql_query_expr_0"}],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["depth"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
      ).replace(old="MODE", new=wire),
      construction_limits().program,
      format=Json,
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    for program in [actual, expected] {
      match
        @check.check_parsed_with_evidence(
          program,
          graph_rows_environment(),
          None,
          [],
          graph_rows_check_limits(),
        ) {
        Checked(_) => ()
        Rejected(diagnostic) => graph_rows_rejected(diagnostic)
        NeedsInputs(_) =>
          fail("The traversal must reuse its bound Graph selector")
      }
    }
  }
}
