///|
fn graph_quantifier_forms_expected(
  minimum : Int64,
  maximum : Int64,
) -> @program.Program raise {
  // Replace the independently authored control's fixed-hop predicate with
  // explicit homogeneous bounds, without obtaining bytes from the frontend.
  let hop = "\"hops\":[{\"direction\":\"out\",\"edge_types\":[\"R\"],\"node_where\":{\"gt\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":10}]}}]"
  let base = semantic(graph_hop_node_expected())
  assert_true(base.contains(hop))
  @program.parse(
    base.replace(
      old=hop,
      new="\"direction\":\"out\",\"edge_types\":[\"R\"],\"min_hops\":" +
        minimum.to_string() +
        ",\"max_hops\":" +
        maximum.to_string(),
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "fixed and omitted-lower Graph bounds match independent complete Programs" {
  for
    (bounds, minimum, maximum) in [
      ("{2}", 2L, 2L),
      ("{,2}", 0L, 2L),
      ("{1,2}", 1L, 2L),
    ] {
    let expected = graph_quantifier_forms_expected(minimum, maximum)
    let source = graph_hop_node_source(
      "(a:Node WHERE id = 1)-[:R]->" + bounds + "(b:Node)",
    )
    let actual = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      graph_hop_node_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    match
      @check.check_parsed_with_evidence(
        expected,
        graph_rows_environment(),
        None,
        [],
        graph_rows_check_limits(),
      ) {
      Checked(_) => ()
      Rejected(diagnostic) => graph_rows_rejected(diagnostic)
      NeedsInputs(_) => fail("Bound Values require no acquisition")
    }
  }
}

///|
test "new finite forms do not turn terminal-only predicates into every-hop filters" {
  for bounds in ["{2}", "{,2}"] {
    assert_true(
      graph_hop_node_compile(
        "(a:Node WHERE id = 1)-[:R]->" +
        bounds +
        "(b:Node WHERE payload.score > 10)",
      )
      is Err(UnsupportedGraph),
    )
  }
}
