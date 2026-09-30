///|
fn named_sga_text(named : Bool) -> String {
  let reach = if named {
    "reach(start: \"A\", direction: \"out\", max_depth: 2)"
  } else {
    "OP reach {\"start\":\"A\",\"direction\":\"out\",\"max_depth\":2}"
  }
  let subgraph = if named {
    "subgraph(nodes: {from: reached, id: \"node_id\"})"
  } else {
    "OP subgraph {\"nodes\":{\"from\":\"reached\",\"id\":\"node_id\"}}"
  }
  let rows = if named { "node_rows()" } else { "OP node_rows true" }
  let template =
    #|AQL '0.1'; PROGRAM 'sga-check' { STAGE s {
    #|  DATA nodes = OP values {"schema":{"id":{"type":"string","nullable":false}},"rows":[{"id":"A"},{"id":"B"}]};
    #|  DATA edges = OP values {"schema":{"src":{"type":"string","nullable":false},"dst":{"type":"string","nullable":false}},"rows":[{"src":"A","dst":"B"}]};
    #|  DATA g = OP graph {"nodes":{"from":"nodes","id":"id","fields":[]},"edges":{"from":"edges","source":"src","target":"dst","fields":[]}};
    #|  DATA reached = FROM g |> REACH_PLACEHOLDER;
    #|  DATA neighborhood = FROM g |> SUBGRAPH_PLACEHOLDER;
    #|  DATA rows = FROM neighborhood |> ROWS_PLACEHOLDER;
    #|  RESULT r = {"from":"rows","fields":["id"]};
    #|} RESULT r = {"from":{"stage":"s","result":"r"}}; }
  template
  .replace(old="REACH_PLACEHOLDER", new=reach)
  .replace(old="SUBGRAPH_PLACEHOLDER", new=subgraph)
  .replace(old="ROWS_PLACEHOLDER", new=rows)
}

///|
test "named SGA source and existing OP reach the same checked Program" {
  let (_, _, environment, _, base) = public_input_fixture(
    generated=true,
    graph_policy=true,
  )
  let limits = {
    ..base,
    compilation: {
      ..base.compilation,
      structure: { ..base.compilation.structure, steps: 12, },
    },
  }
  let named = @aql.parse(named_sga_text(true), structural_limits(limits)).unwrap()
  let existing = @aql.parse(named_sga_text(false), structural_limits(limits)).unwrap()
  let a = public_checked(
    check_parsed_with_evidence(
      @aql.program(named),
      environment,
      None,
      [],
      limits,
    ),
  )
  let b = public_checked(
    check_parsed_with_evidence(
      @aql.program(existing),
      environment,
      None,
      [],
      limits,
    ),
  )
  assert_eq(unit_count(a), 1)
  assert_eq(unit_count(a), unit_count(b))
  for i in 0..<unit_count(a) {
    assert_eq(unit_definition_cid(a, i), unit_definition_cid(b, i))
    assert_eq(unit_contracts_cid(a, i), unit_contracts_cid(b, i))
  }
}

///|
test "named SGA rejects a Relation where its Graph input is required" {
  let (_, _, environment, _, base) = public_input_fixture(
    generated=true,
    graph_policy=true,
  )
  let limits = {
    ..base,
    compilation: {
      ..base.compilation,
      structure: { ..base.compilation.structure, steps: 12, },
    },
  }
  let invalid = named_sga_text(true).replace(
    old="DATA reached = FROM g |> reach",
    new="DATA reached = FROM nodes |> reach",
  )
  let parsed = @aql.parse(invalid, structural_limits(limits)).unwrap()
  match
    check_parsed_with_evidence(
      @aql.program(parsed),
      environment,
      None,
      [],
      limits,
    ) {
    Rejected(_) => ()
    _ => fail("common checker must reject the wrong Graph input Carrier")
  }
}

///|
test "named Graph diff and apply keep the checked Delta producer" {
  let (_, _, environment, _, base) = public_input_fixture(
    generated=true,
    graph_policy=true,
  )
  let limits = {
    ..base,
    compilation: {
      ..base.compilation,
      structure: { ..base.compilation.structure, steps: 12, },
    },
  }
  let source = named_sga_text(true)
    .replace(
      old="DATA reached = FROM g |> reach(start: \"A\", direction: \"out\", max_depth: 2);",
      new="DATA target = FROM g |> normalize_graph();",
    )
    .replace(
      old="DATA neighborhood = FROM g |> subgraph(nodes: {from: reached, id: \"node_id\"});",
      new="DATA changes = FROM g |> graph_diff(with: target); DATA restored = FROM g |> apply_graph_delta(with: changes, field: \"delta\");",
    )
    .replace(
      old="DATA rows = FROM neighborhood |> node_rows();",
      new="DATA rows = FROM restored |> node_rows();",
    )
  assert_true(source.contains("apply_graph_delta"))
  let parsed = @aql.parse(source, structural_limits(limits)).unwrap()
  let checked = public_checked(
    check_parsed_with_evidence(
      @aql.program(parsed),
      environment,
      None,
      [],
      limits,
    ),
  )
  assert_eq(unit_count(checked), 1)
}

///|
test "named mean_graphs retains repeated checked Graph inputs" {
  let (_, _, environment, _, base) = public_input_fixture(
    generated=true,
    graph_policy=true,
  )
  let limits = {
    ..base,
    compilation: {
      ..base.compilation,
      structure: { ..base.compilation.structure, steps: 12, },
    },
  }
  let source = named_sga_text(true)
    .replace(
      old="DATA reached = FROM g |> reach(start: \"A\", direction: \"out\", max_depth: 2);",
      new="DATA average = mean_graphs(with: [g, g, g], weights: [1, 1, 1], support: {nodes: 0.5, edges: 0.5}, properties: {nodes: {}, edges: {}});",
    )
    .replace(
      old="DATA neighborhood = FROM g |> subgraph(nodes: {from: reached, id: \"node_id\"});",
      new="",
    )
    .replace(
      old="DATA rows = FROM neighborhood |> node_rows();",
      new="DATA rows = FROM average |> node_rows();",
    )
  assert_true(source.contains("mean_graphs"))
  let parsed = @aql.parse(source, structural_limits(limits)).unwrap()
  let checked = public_checked(
    check_parsed_with_evidence(
      @aql.program(parsed),
      environment,
      None,
      [],
      limits,
    ),
  )
  assert_eq(unit_count(checked), 1)
}

///|
test "named graphs_equal can reuse the checked Graph producer" {
  let (_, _, environment, _, base) = public_input_fixture(
    generated=true,
    graph_policy=true,
  )
  let limits = {
    ..base,
    compilation: {
      ..base.compilation,
      structure: { ..base.compilation.structure, steps: 12, },
    },
  }
  let source = named_sga_text(true)
    .replace(
      old="DATA reached = FROM g |> reach(start: \"A\", direction: \"out\", max_depth: 2);",
      new="DATA comparison = FROM g |> graphs_equal(with: g);",
    )
    .replace(
      old="DATA neighborhood = FROM g |> subgraph(nodes: {from: reached, id: \"node_id\"});",
      new="",
    )
    .replace(
      old="DATA rows = FROM neighborhood |> node_rows();",
      new="DATA rows = FROM comparison |> OP select [\"equal\"];",
    )
    .replace(old="[\"id\"]", new="[\"equal\"]")
  let parsed = @aql.parse(source, structural_limits(limits)).unwrap()
  let checked = public_checked(
    check_parsed_with_evidence(
      @aql.program(parsed),
      environment,
      None,
      [],
      limits,
    ),
  )
  assert_eq(unit_count(checked), 1)
}
