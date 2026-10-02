///|
fn property_source_check_environment() -> @check.CheckEnvironment {
  @check.checking_environment(
    @check.checking_environment_wire(graph_check_environment()),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    property_graph=true,
  )
}

///|
test "Property Graph DATA sets preserve typed composite and nullable inputs through checker" {
  for
    source in [
      "DATA n = SELECT 1 AS part, 23 AS id UNION ALL SELECT 12 AS part, 3 AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (part, id) LABEL Node PROPERTIES (part, id))); FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.part, a.id",
      "DATA n = SELECT 1 AS id UNION ALL SELECT CAST(NULL AS FLOAT64) AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node PROPERTIES (id))); FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.id",
      "DATA n = SELECT 1 AS id; DATA e = SELECT 10 AS key, 1 AS src, 1 AS dst UNION ALL SELECT 11 AS key, 1 AS src, 1 AS dst; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES) EDGE TABLES (e AS E KEY (key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES)); FROM GRAPH g |> MATCH p = TRAIL (:Node)-[:R]->(:Node)-[:R]->(:Node) |> SELECT PATH_LENGTH(p) AS depth",
      "DATA n = SELECT 1 AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Person PROPERTIES (id) LABEL Account PROPERTIES (id))); FROM GRAPH g |> MATCH WALK (a:account) |> SELECT a.id",
    ] {
    let program = compile_data_set(source)
    match
      @check.check_parsed(
        program,
        property_source_check_environment(),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      NeedsInputs(_) => fail("DATA set does not create an acquisition")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "Property Graph source reaches ordinary checker with static label membership" {
  let source = "DATA n = SELECT 1 AS id, 'Company' AS entity_type; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Person PROPERTIES (id, entity_type))); FROM GRAPH g |> MATCH WALK (a:Person WHERE id > 0) |> SELECT a.id, a.entity_type"
  let program = compile_query_script(
    @query.parse_query_script(source, syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(
      program,
      property_source_check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    NeedsInputs(_) => fail("pure constructor must not acquire inputs")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "Property Graph source traversal reaches ordinary checker with explicit path modes" {
  let prefix = "DATA n = SELECT 1 AS id; DATA e = SELECT 10 AS key, 1 AS src, 1 AS dst; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES) EDGE TABLES (e AS E KEY (key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES, e AS F KEY (key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES)); "
  for mode in ["WALK", "TRAIL", "ACYCLIC"] {
    let source = prefix +
      "FROM GRAPH g |> MATCH p = " +
      mode +
      " (:Node)-[:R]->(:Node)-[:R]->(:Node) |> SELECT PATH_LENGTH(p) AS depth"
    let program = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        program,
        property_source_check_environment(),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      NeedsInputs(_) => fail("pure constructor must not acquire inputs")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "Property Graph NODE_ID projects full identity separately from an id property" {
  let source = "DATA n = SELECT 1 AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node PROPERTIES (id))); FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.id AS property_id, NODE_ID(a) AS element"
  let program = compile_query_script(
    @query.parse_query_script(source, syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(program).contains("\"fields\":[\"property_id\",\"element\"]"),
  )
  match
    @check.check_parsed(
      program,
      property_source_check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    NeedsInputs(_) => fail("pure constructor must not acquire inputs")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}
