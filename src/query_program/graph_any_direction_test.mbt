///|
fn graph_any_direction_expected() -> @program.Program raise {
  // Reuse the independently authored Values/mapping control, changing only
  // the existing logical traversal direction in that complete Program.
  @program.parse(
    semantic(graph_hop_node_expected()).replace(
      old="\"direction\":\"out\"",
      new="\"direction\":\"both\"",
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "any-direction independent ordinary Program passes common checking" {
  match
    @check.check_parsed_with_evidence(
      graph_any_direction_expected(),
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    NeedsInputs(_) => fail("Bound Graph selectors do not acquire input")
  }
}

///|
test "any-direction MATCH retains its independent complete Program" {
  let actual = compile_query_script(
    @query.parse_query_script(
      graph_hop_node_source(
        "(a:Node WHERE id = 1)-[:R]-(b:Node WHERE b.payload.score > 10)",
      ),
      syntax_limits(),
    ).unwrap(),
    graph_hop_node_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(graph_any_direction_expected()))
}

///|
test "any-direction fixed hops retain both endpoint definitions for property checking" {
  let source = graph_hop_definition_prefix() +
    "FROM GRAPH g |> MATCH p = WALK (:Start)-[:R]-(b WHERE b.score > 10) |> SELECT PATH_LENGTH(p) AS depth"
  // Target has score, but Source does not. The any-direction common scope
  // excludes it. WITH static admission now reaches that checker before demand.
  let refusal = with_graph_predicate_refusal(
    compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ),
  )
  assert_eq(refusal, @pipeline.GraphMatch(UnknownField("score")))
  let parsed = @query.parse_query_script(
    graph_hop_definition_prefix() +
    "FROM GRAPH g |> MATCH p = WALK (:Start)-[:R]-(:Target) |> SELECT PATH_LENGTH(p) AS depth",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile_query_script(
      parsed,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(UnsupportedGraph),
  )
}

///|
test "any-direction bounded MATCH retains direction mode and finite bounds" {
  for
    (mode, lowered) in [
      ("WALK", "walk"),
      ("TRAIL", "trail"),
      ("ACYCLIC", "acyclic"),
    ] {
    let source = graph_hop_node_source(
      "(a:Node WHERE id = 1)-[:R]-{0,2}(b:Node)",
    ).replace(old="p = WALK", new="p = " + mode)
    let program = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      graph_hop_node_context(),
      construction_limits(),
    ).unwrap()
    let body = semantic(program)
    assert_true(body.contains("\"direction\":\"both\""))
    assert_true(body.contains("\"min_hops\":0"))
    assert_true(body.contains("\"max_hops\":2"))
    assert_true(body.contains("\"path_mode\":\"" + lowered + "\""))
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
      NeedsInputs(_) => fail("Bound Values do not acquire input")
    }
  }
}
