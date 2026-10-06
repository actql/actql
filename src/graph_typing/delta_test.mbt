///|
fn delta_input_rows(
  nullable : Bool,
  presence : @row.Presence,
) -> @carrier.Carrier {
  @carrier.relation(
    @carrier.typed_rows(
      @row.from_presence_fields(
        [
          (
            @row.Unqualified("changes"),
            @contract.primitive(JsonType, nullable~),
            presence,
          ),
        ],
        max_fields=1,
        max_name_bytes=7,
      ).unwrap(),
    ),
  )
}

///|
test "Delta check retains the current Graph contract and unresolved runtime admission" {
  let input = keyed_profile()
  let checked = @graph_typing.check_graph_diff(
    cursor("{\"with\":\"target\"}"),
    input,
    input,
    limits(),
  ).unwrap()
  assert_eq(@graph_typing.delta_operation(checked), @graph_typing.Difference)
  let output = @carrier.relation_rows(@graph_typing.delta_output(checked)).unwrap()
  guard @carrier.lookup(output, @row.Unqualified("delta"))
    is @carrier.Present(field) else {
    fail("missing Delta field")
  }
  assert_eq(field.presence, @row.Required)
  assert_true(!field.contract.unwrap().nullable)
  assert_true(field.contract.unwrap().shape is @contract.Json)
  assert_eq(@graph_typing.delta_pending_count(checked), 3)
  assert_eq(
    @graph_typing.delta_pending_at(checked, 0),
    Some(@graph_typing.AdmitDeltaGraphs),
  )
  assert_eq(
    @graph_typing.delta_pending_at(checked, 1),
    Some(@graph_typing.ResolveDeltaResources),
  )
  assert_eq(
    @graph_typing.delta_pending_at(checked, 2),
    Some(@graph_typing.EnforceDeltaRelationRows),
  )
  assert_eq(@graph_typing.delta_pending_at(checked, -1), None)
  assert_eq(@graph_typing.delta_pending_at(checked, 3), None)
}

///|
test "Delta check rejects different saved definitions and incomplete Graphs" {
  let input = keyed_profile()
  let graph = match input {
    @carrier.GraphValue(graph) => graph
    _ => abort("Graph")
  }
  let definition = @carrier.graph_definition(graph)
  let other = @carrier.graph(
    "sha256:" + "1".repeat(64),
    @carrier.graph_node_definitions(definition),
    [],
    max_definitions=1,
    max_contract_work=100,
  ).unwrap()
  assert_true(
    @graph_typing.check_graph_diff(
      cursor("{\"with\":\"target\"}"),
      input,
      other,
      limits(),
    )
    is Err({ kind: @graph_typing.DeltaContractMismatch, .. }),
  )
  assert_true(
    @graph_typing.check_graph_diff(
      cursor("{\"with\":\"target\"}"),
      input,
      @carrier.unknown_carrier(GraphKind),
      limits(),
    )
    is Err({ kind: @graph_typing.IncompleteGraph, .. }),
  )
  for body in ["{}", "{\"with\":\"\"}", "{\"with\":\"target\",\"extra\":true}"] {
    assert_true(
      @graph_typing.check_graph_diff(cursor(body), input, input, limits())
      is Err(_),
    )
  }
}

///|
test "Delta application requires a present nonnull typed field without granting data admission" {
  let body = cursor("{\"with\":\"updates\",\"field\":\"changes\"}")
  let input = keyed_profile()
  let checked = @graph_typing.check_apply_graph_delta(
    body,
    input,
    delta_input_rows(false, @row.Required),
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @graph_typing.delta_operation(checked),
    @graph_typing.Application(@row.Unqualified("changes")),
  )
  assert_true(physical_equal(@graph_typing.delta_output(checked), input))
  assert_eq(@graph_typing.delta_pending_count(checked), 5)
  assert_eq(
    @graph_typing.delta_pending_at(checked, 2),
    Some(@graph_typing.AdmitExactlyOneDeltaRow),
  )
  assert_eq(
    @graph_typing.delta_pending_at(checked, 3),
    Some(@graph_typing.AdmitDeltaActions),
  )
  assert_eq(
    @graph_typing.delta_pending_at(checked, 4),
    Some(@graph_typing.VerifyDeltaBaseBeforeTarget),
  )
  for
    rows in [
      delta_input_rows(true, @row.Required),
      delta_input_rows(false, @row.Conditional),
    ] {
    assert_true(
      @graph_typing.check_apply_graph_delta(body, input, rows, None, limits())
      is Err({ kind: @graph_typing.InvalidDeltaType, .. }),
    )
  }
  assert_true(
    @graph_typing.check_apply_graph_delta(
      cursor("{\"with\":\"updates\",\"field\":\"unknown\"}"),
      input,
      delta_input_rows(false, @row.Required),
      None,
      limits(),
    )
    is Err({ kind: @graph_typing.UnknownDeltaField("unknown"), .. }),
  )
}

///|
test "Delta check accounts for both saved contracts at exact and deficient budgets" {
  let body = cursor("{\"with\":\"target\"}")
  let input = keyed_profile()
  let checked = @graph_typing.check_graph_diff(body, input, input, limits()).unwrap()
  let used = @graph_typing.delta_usage(checked)
  let exact = {
    ..limits(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
  }
  assert_true(
    @graph_typing.check_graph_diff(body, input, input, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_graph_diff(body, input, input, cap)
      is Err({ kind: @graph_typing.BudgetExceeded, .. }),
    )
  }
}
