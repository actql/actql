///|
fn key_projection_graph() -> @carrier.Carrier {
  // Shared audit input is current definition-keyed Graph, never a tuple issuer.
  query_property_graph()
}

///|
test "retired Graph projection refuses at the public checker with exact diagnostics" {
  for key in ["node_rows", "edge_rows"] {
    for body in ["true", "false", "null", "{}", "[]", "1", "\"true\""] {
      let issue = @pipeline_typing.check_carriers(
        cursor("[{\"" + key + "\":" + body + "}]"),
        [("g", query_property_graph())],
        None,
        None,
        limits(),
      ).unwrap_err()
      assert_eq(
        issue.kind,
        Projection(
          if body == "true" {
            @projection.UnsupportedGraphOperation
          } else {
            @projection.InvalidBody
          },
        ),
      )
      assert_eq(issue.path, [Index(0), Key(key)])
    }
    for
      kind in [@carrier.RelationKind, @carrier.EventsKind, @carrier.VectorsKind] {
      let issue = @pipeline_typing.check_carriers(
        cursor("[{\"" + key + "\":true}]"),
        [("other", @carrier.unknown_carrier(kind))],
        None,
        None,
        limits(),
      ).unwrap_err()
      assert_eq(issue.kind, Projection(@projection.WrongCarrier(kind)))
      assert_eq(issue.path, [Index(0), Key(key)])
    }
    for cap in [{ ..limits(), max_work: 0, }, { ..limits(), max_nodes: 0, }] {
      assert_true(
        @pipeline_typing.check_carriers(
          cursor("[{\"" + key + "\":true}]"),
          [("g", query_property_graph())],
          None,
          None,
          cap,
        )
        is Err({ kind: BudgetExceeded, .. }),
      )
    }
  }
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
test "retired Graph projections cannot manufacture key evidence" {
  for graph in [query_property_graph()] {
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
  let key = @pipeline_typing.candidate_key(vector, Step(0)).unwrap()
  assert_eq(@evidence.key_origin(key), VectorProjectionResult)
  assert_true(@evidence.key_vector_projection_producer(key) is Some(_))
  assert_true(@evidence.key_graph_query_producer(key) is None)
}
