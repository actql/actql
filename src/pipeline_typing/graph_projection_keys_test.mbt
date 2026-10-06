///|
fn key_projection_graph() -> @carrier.Carrier {
  // Shared audit input is current definition-keyed Graph, never a tuple issuer.
  query_graph()
}

///|
test "Graph definition presence permits guaranteed projection but never sample-based reference" {
  let number = @contract.primitive(NumberType, nullable=false)
  let optional = @carrier.rows(
    [
      (
        @schema.Unqualified("p"),
        Some(@contract.primitive(NumberType, nullable=true)),
      ),
    ],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let graph = @carrier.graph(
    "sha256:" + "0".repeat(64),
    [
      @carrier.graph_node_definition(
        "N",
        [number],
        optional,
        ["Person"],
        key_columns=["person_key"],
        max_fields=4,
        max_name_bytes=100,
      ).unwrap(),
      @carrier.graph_node_definition(
        "M",
        [number],
        empty,
        [],
        key_columns=["company_key"],
        max_fields=4,
        max_name_bytes=100,
      ).unwrap(),
    ],
    [],
    max_definitions=2,
    max_contract_work=1000,
  ).unwrap()
  for
    (suffix, expected) in [
      ("{\"select\":[\"p\"]}", @relation.PresenceRequired("p")),
      ("{\"filter\":\"p IS NOT NULL\"}", @relation.PresenceRequired("p")),
    ] {
    assert_true(
      @pipeline_typing.check_carriers(
        cursor("[{\"node_rows\":true}," + suffix + "]"),
        [("g", graph)],
        None,
        None,
        limits(),
      )
      is Err({ kind: Operation(issue), .. }) &&
      issue == expected,
    )
  }
  assert_true(
    @pipeline_typing.check_carriers(
      cursor("[{\"node_rows\":true},{\"select\":[\"id\",\"labels\"]}]"),
      [("g", graph)],
      None,
      None,
      limits(),
    )
    is Ok(_),
  )
}

///|
test "Graph row projection requires true with exact public diagnostics" {
  for key in ["node_rows", "edge_rows"] {
    assert_true(
      @pipeline_typing.check_carriers(
        cursor("[{\"" + key + "\":true}]"),
        [("g", query_graph())],
        None,
        None,
        limits(),
      )
      is Ok(_),
    )
    for body in ["false", "null", "{}", "[]", "1", "\"true\""] {
      let issue = @pipeline_typing.check_carriers(
        cursor("[{\"" + key + "\":" + body + "}]"),
        [("g", query_graph())],
        None,
        None,
        limits(),
      ).unwrap_err()
      assert_eq(issue.kind, Projection(@projection.InvalidBody))
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
          [("g", query_graph())],
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
test "Graph edge row roles do not invent retired endpoint names for joins" {
  for on in ["[\"source\",\"target\"]", "[\"source\",\"target\",\"label\"]"] {
    let source = cursor(
      "[{\"edge_rows\":true,\"as\":\"edges\"},{\"join\":{\"with\":\"edges\",\"kind\":\"inner\",\"on\":" +
      on +
      "}}]",
    )
    assert_true(
      @pipeline_typing.check_carriers(
        source,
        [("g", query_graph())],
        None,
        None,
        limits(),
      )
      is Err(_),
    )
  }
}

///|
test "Graph row projections do not manufacture global candidate key evidence" {
  for graph in [query_graph()] {
    for
      (body, removed) in [
        ("node_rows", "[\"id\"]"),
        ("edge_rows", "[\"id\",\"src\",\"dst\"]"),
      ] {
      let checked = @pipeline_typing.check_carriers(
        cursor("[{\"" + body + "\":true},{\"drop\":" + removed + "}]"),
        [("g", graph)],
        None,
        None,
        limits(),
      ).unwrap()
      assert_true(@pipeline_typing.candidate_key(checked, Step(0)) is None)
      assert_true(@pipeline_typing.candidate_key(checked, Step(1)) is None)
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
