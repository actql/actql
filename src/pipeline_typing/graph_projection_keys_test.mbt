///|
fn key_projection_graph() -> @carrier.Carrier {
  // Shared audit input is current definition-keyed Graph, never a tuple issuer.
  query_property_graph()
}

///|
test "retired edge row tuples cannot supply whole-tuple join coverage for Property Graph" {
  for on in ["[\"source\",\"target\"]", "[\"source\",\"target\",\"label\"]"] {
    let source = cursor(
      "[{\"edge_rows\":true,\"as\":\"edges\"},{\"join\":{\"with\":\"edges\",\"kind\":\"inner\",\"on\":" +
      on +
      "}}]",
    )
    assert_true(
      @pipeline_typing.check_carriers(
        source,
        [("g", query_property_graph())],
        None,
        None,
        limits(),
      )
      is Err({ kind: Projection(@projection.UnsupportedGraphOperation), .. }),
    )
  }
}

///|
test "historical role aliases cannot revive a retired Graph projection or its key evidence" {
  let original = query_property_graph()
  guard original is @carrier.GraphValue(graph) else { abort("Graph") }
  let names = @carrier.graph_row_names(
    Unqualified("node"),
    Unqualified("source"),
    Unqualified("target"),
    Some(Unqualified("label")),
    max_name_bytes=100,
  ).unwrap()
  for graph in [original, @carrier.with_graph_names(graph, Some(names))] {
    for
      (body, removed) in [
        ("node_rows", "[\"id\"]"),
        ("edge_rows", "[\"src\",\"dst\",\"rel\"]"),
      ] {
      assert_true(
        @pipeline_typing.check_carriers(
          cursor("[{\"" + body + "\":true},{\"drop\":" + removed + "}]"),
          [("g", graph)],
          None,
          None,
          limits(),
        )
        is Err({ kind: Projection(@projection.UnsupportedGraphOperation), .. }),
      )
    }
  }
}

///|
test "opaque Graph refusal and cross-family evidence do not invent projection keys" {
  for body in ["node_rows", "edge_rows"] {
    assert_true(
      @pipeline_typing.check_carriers(
        cursor("[{\"" + body + "\":true}]"),
        [("g", @carrier.unknown_carrier(GraphKind))],
        None,
        None,
        limits(),
      )
      is Err({ kind: Projection(@projection.IncompleteGraph), .. }),
    )
  }
  let vector = @pipeline_typing.check_carriers(
    cursor("[{\"vectors\":true}]"),
    [("v", vector_input())],
    None,
    None,
    limits(),
  ).unwrap()
  guard @pipeline_typing.step_at(vector, 0).unwrap().operation
    is Projection(operation) else {
    abort("projection")
  }
  assert_true(
    @evidence.graph_projection_keys(operation, {
      max_work: 100,
      max_name_bytes: 100,
    })
    is Err({ kind: InputContractMismatch, .. }),
  )
}
