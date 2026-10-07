///|
fn graph_abbreviated_expected(direction : String) -> @program.Program raise {
  // The complete independently authored control has the same starting and
  // reached-node predicates, with no implicit edge label selection.
  @program.parse(
    semantic(graph_hop_node_expected()).replace(
      old="\"direction\":\"out\",\"edge_types\":[\"R\"]",
      new="\"direction\":\"" + direction + "\"",
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "abbreviated and full empty edges match independent complete Programs" {
  for
    (abbreviated, full, direction) in [
      ("-", "-[]-", "both"),
      ("<-", "<-[]-", "in"),
      ("->", "-[]->", "out"),
    ] {
    let expected = graph_abbreviated_expected(direction)
    for edge in [abbreviated, full] {
      let actual = graph_hop_node_compile(
        "(a:Node WHERE id = 1)" + edge + "(b:Node WHERE b.payload.score > 10)",
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected))
    }
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
test "bounded abbreviated edges retain common traversal arguments" {
  for (abbreviated, full) in [("-", "-[]-"), ("<-", "<-[]-"), ("->", "-[]->")] {
    for mode in ["WALK", "TRAIL", "ACYCLIC"] {
      let compile = edge => {
        compile_query_script(
          @query.parse_query_script(
            graph_hop_node_source(
              "(a:Node WHERE id = 1)" + edge + "{0,2}(b:Node)",
            ).replace(old="p = WALK", new="p = " + mode),
            syntax_limits(),
          ).unwrap(),
          graph_hop_node_context(),
          construction_limits(),
        ).unwrap()
      }
      let actual = compile(abbreviated)
      assert_eq(semantic(actual), semantic(compile(full)))
      match
        @check.check_parsed_with_evidence(
          actual,
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
}

///|
test "abbreviated edges preserve unsupported terminal predicate refusal" {
  assert_true(
    graph_hop_node_compile(
      "(a:Node WHERE id = 1)->{2,2}(b:Node WHERE payload.score > 10)",
    )
    is Err(UnsupportedGraph),
  )
}
