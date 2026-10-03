///|
test "graph diagnostics retain typed identity, order and exact threshold forms" {
  let graph = current_scope_graph()
  let bounds_source = cursor(
    "{\"max_nodes\":0,\"max_edges\":2,\"max_degree\":4}",
  )
  let bounds = @graph_typing.check_graph_bounds(
    bounds_source,
    graph,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @decode.cursor_path(@graph_typing.graph_bounds_source(bounds)),
    @decode.cursor_path(bounds_source),
  )
  assert_eq(
    @carrier.kind(@graph_typing.graph_bounds_input(bounds)),
    @carrier.GraphKind,
  )
  let (nodes, edges, degree) = @graph_typing.graph_bounds_thresholds(bounds)
  assert_true(nodes is Some(@graph_typing.Literal(0L)))
  assert_true(edges is Some(@graph_typing.Literal(2L)))
  assert_true(degree is Some(@graph_typing.Literal(4L)))
  assert_eq(@graph_typing.graph_bounds_pending_count(bounds), 3)
  assert_eq(
    @graph_typing.graph_bounds_pending_at(bounds, 2),
    Some(@graph_typing.EnforceDiagnosticRelationRows),
  )
  let rows = @carrier.complete_schema(
    @carrier.relation_rows(@graph_typing.graph_bounds_output(bounds)).unwrap(),
  ).unwrap()
  assert_eq(@row.field_count(rows), 4)
  assert_true(@row.lookup(rows, Unqualified("kind")) is Some(_))
  assert_true(@row.lookup(rows, Unqualified("actual")) is Some(_))
  assert_true(@row.lookup(rows, Unqualified("max")) is Some(_))
  let node_id = @row.lookup(rows, Unqualified("node_id")).unwrap()
  assert_true(node_id.nullable)
  assert_true(node_id.shape is @contract.Json)

  let degree_source = cursor("{\"direction\":\"both\"}")
  let checked = @graph_typing.check_degree(degree_source, graph, limits()).unwrap()
  assert_eq(
    @decode.cursor_path(@graph_typing.degree_source(checked)),
    @decode.cursor_path(degree_source),
  )
  assert_eq(
    @carrier.kind(@graph_typing.degree_input(checked)),
    @carrier.GraphKind,
  )
  assert_eq(@graph_typing.degree_direction(checked), @graph_typing.Both)
  assert_eq(@graph_typing.degree_pending_count(checked), 3)
  assert_eq(
    @graph_typing.degree_pending_at(checked, 0),
    Some(@graph_typing.AdmitDiagnosticGraph),
  )
  let degree_rows = @carrier.complete_schema(
    @carrier.relation_rows(@graph_typing.degree_output(checked)).unwrap(),
  ).unwrap()
  assert_eq(@row.field_count(degree_rows), 2)
  assert_true(@row.lookup(degree_rows, Unqualified("node")) is Some(_))
  assert_true(@row.lookup(degree_rows, Unqualified("degree")) is Some(_))
}

///|
test "graph diagnostic checkers reject missing and invalid authored bounds" {
  let graph = current_scope_graph()
  for
    body in [
      "{}", "{\"max_nodes\":-1}", "{\"max_edges\":1.5}", "{\"max_degree\":null}",
      "{\"max_nodes\":1,\"unknown\":0}",
    ] {
    assert_true(
      @graph_typing.check_graph_bounds(cursor(body), graph, None, limits())
      is Err(_),
    )
  }
  for
    body in [
      "{}", "{\"direction\":\"sideways\"}", "{\"direction\":\"in\",\"extra\":true}",
    ] {
    assert_true(
      @graph_typing.check_degree(cursor(body), graph, limits()) is Err(_),
    )
  }
  assert_true(
    @graph_typing.check_degree(
      cursor("{\"direction\":\"out\"}"),
      @carrier.unknown_carrier(@carrier.GraphKind),
      limits(),
    )
    is Err({ kind: @graph_typing.IncompleteGraph, .. }),
  )
}

///|
test "graph bounds retain declared parameter references without observing values" {
  let declarations = @parameter.read_declarations(
    Some(cursor("{\"n\":{\"type\":\"number\"}}")),
    { max_parameters: 1, max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let checked = @graph_typing.check_graph_bounds(
    cursor("{\"max_degree\":{\"$param\":\"n\"}}"),
    current_scope_graph(),
    Some(declarations),
    limits(),
  ).unwrap()
  let (nodes, edges, degree) = @graph_typing.graph_bounds_thresholds(checked)
  assert_true(nodes is None)
  assert_true(edges is None)
  assert_true(degree is Some(@graph_typing.Parameter("n")))
  assert_eq(@graph_typing.graph_bounds_pending_count(checked), 4)
  assert_eq(
    @graph_typing.graph_bounds_pending_at(checked, 3),
    Some(@graph_typing.BindDiagnosticThreshold("n")),
  )
  assert_true(
    @graph_typing.check_graph_bounds(
      cursor("{\"max_nodes\":{\"$param\":\"missing\"}}"),
      current_scope_graph(),
      Some(declarations),
      limits(),
    )
    is Err({ kind: @graph_typing.UnknownParameter("missing"), .. }),
  )
  let nullable = @parameter.read_declarations(
    Some(cursor("{\"n\":{\"type\":\"number\",\"nullable\":true}}")),
    { max_parameters: 1, max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  assert_true(
    @graph_typing.check_graph_bounds(
      cursor("{\"max_nodes\":{\"$param\":\"n\"}}"),
      current_scope_graph(),
      Some(nullable),
      limits(),
    )
    is Err({ kind: @graph_typing.IncompatibleParameter("n"), .. }),
  )
}

///|
test "graph diagnostic checkers preserve exact work and structure budgets" {
  let graph = current_scope_graph()
  let bounds_source = cursor("{\"max_nodes\":0,\"max_edges\":0}")
  let bounds = @graph_typing.check_graph_bounds(
    bounds_source,
    graph,
    None,
    limits(),
  ).unwrap()
  let usage = @graph_typing.graph_bounds_usage(bounds)
  let exact = {
    ..limits(),
    max_work: usage.work,
    max_nodes: usage.nodes,
    max_text_bytes: usage.text_bytes,
  }
  assert_true(
    @graph_typing.check_graph_bounds(bounds_source, graph, None, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: usage.work - 1, },
      { ..exact, max_nodes: usage.nodes - 1, },
      { ..exact, max_text_bytes: usage.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_graph_bounds(bounds_source, graph, None, cap)
      is Err({ kind: @graph_typing.BudgetExceeded, .. }),
    )
  }
}
