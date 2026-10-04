///|
fn carrier_projection_owner(
  source : String,
  inputs : Array[(String, @carrier.Carrier)],
) -> @lowering_relation.BoundPrepared {
  let checked = @pipeline.check_carriers(cursor(source), inputs, None, None, {
    max_steps: 10,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  }).unwrap()
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "Vectors projection retains its registered typed operation" {
  let vectors = carrier_projection_owner(
    "[{\"from\":\"rows\",\"to_vectors\":{\"id\":\"product_id\",\"vector\":\"embedding\"}},{\"vectors\":true}]",
    [("rows", vector_relation())],
  )
  let vector_sequence = @lowering_relation.prepare_sequence(
    vectors,
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(vector_sequence, 1)
    is Some(@lowering_relation.CarrierProjectionStep(projected)) else {
    fail("expected vector projection")
  }
  assert_eq(
    @lowering_relation.carrier_projection_operation(projected),
    @projection.Vectors,
  )
}

///|
test "Graph row projections lower to registered typed Carrier bridges" {
  for operation in ["node_rows", "edge_rows"] {
    let owner = carrier_projection_owner(
      "[{\"from\":\"g\",\"" + operation + "\":true}]",
      [("g", graph_match_carrier())],
    )
    let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
    guard @lowering_relation.sequence_step(sequence, 0)
      is Some(@lowering_relation.CarrierProjectionStep(checked)) else {
      fail("typed Graph bridge")
    }
    assert_eq(
      @lowering_relation.carrier_projection_operation(checked),
      if operation == "node_rows" {
        @projection.NodeRows
      } else {
        @projection.EdgeRows
      },
    )
    let node = @lowering_relation.node_at(
      @lowering_relation.bound_preparation(owner),
      0,
    ).unwrap()
    assert_true(@lowering_relation.node_accepts_managed_carrier_view(node, 0))
    assert_false(@lowering_relation.node_accepts_managed_carrier_view(node, 1))
    assert_true(
      @lowering_relation.node_supports_selected_managed_execution(node),
    )
    assert_eq(
      @lowering_relation.operation(node),
      if operation == "node_rows" {
        "BRIDGE.graph.to_node_rows"
      } else {
        "BRIDGE.graph.to_edge_rows"
      },
    )
  }
}

///|
test "selected Graph definition is retained in checked and emitted Plan parameters" {
  for operation in ["node_rows", "edge_rows"] {
    let name = if operation == "node_rows" { "N" } else { "E" }
    let owner = carrier_projection_owner(
      "[{\"from\":\"g\",\"" +
      operation +
      "\":{\"definition\":\"" +
      name.to_lower() +
      "\"}}]",
      [("g", graph_match_carrier())],
    )
    let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
    guard @lowering_relation.sequence_step(sequence, 0)
      is Some(@lowering_relation.CarrierProjectionStep(projected)) else {
      fail("selected Graph Bridge")
    }
    assert_eq(
      @lowering_relation.carrier_projection_definition(projected),
      Some(name),
    )
    let writer = @encode.writer(10000, 1000, 100)
    @lowering_relation.emit_sequence_steps(sequence, writer)
    assert_true(
      @encode.finish(writer).contains(
        "\"params\":{\"definition\":\"" + name + "\"}",
      ),
    )
  }
}

///|
test "same-schema definition selection is stable and not erased from Plan meaning" {
  let properties = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let definitions = ["N", "M"].map(name => {
    @carrier.property_node_definition(
      name,
      [@contract.primitive(NumberType, nullable=false)],
      properties,
      [],
      max_fields=2,
      max_name_bytes=100,
    ).unwrap()
  })
  let graph = @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    definitions,
    [],
    max_definitions=2,
    max_contract_work=1000,
  ).unwrap()
  let emitted = ["N", "N", "M"].map(name => {
    let owner = carrier_projection_owner(
      "[{\"from\":\"g\",\"node_rows\":{\"definition\":\"" + name + "\"}}]",
      [("g", graph)],
    )
    let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
    let writer = @encode.writer(10000, 1000, 100)
    @lowering_relation.emit_sequence_steps(sequence, writer)
    @encode.finish(writer)
  })
  assert_eq(emitted[0], emitted[1])
  assert_false(emitted[0] == emitted[2])
}

///|
test "label selection is canonical and retained in node and edge Plan parameters" {
  for (operation, label) in [("node_rows", "Node"), ("edge_rows", "owns")] {
    let emitted = [label.to_lower(), label, label.to_lower()].map(name => {
      let owner = carrier_projection_owner(
        "[{\"from\":\"g\",\"" + operation + "\":{\"label\":\"" + name + "\"}}]",
        [("g", graph_match_carrier())],
      )
      let sequence = @lowering_relation.prepare_sequence(
        owner,
        sequence_limits(),
      ).unwrap()
      guard @lowering_relation.sequence_step(sequence, 0)
        is Some(@lowering_relation.CarrierProjectionStep(projected)) else {
        abort("selected label Bridge")
      }
      assert_eq(
        @lowering_relation.carrier_projection_definition(projected),
        None,
      )
      assert_eq(
        @lowering_relation.carrier_projection_label(projected),
        Some(label),
      )
      let writer = @encode.writer(10000, 1000, 100)
      @lowering_relation.emit_sequence_steps(sequence, writer)
      @encode.finish(writer)
    })
    assert_eq(emitted[0], emitted[1])
    assert_eq(emitted[1], emitted[2])
    assert_true(emitted[0].contains("\"params\":{\"label\":\"" + label + "\"}"))
  }
}

///|
test "different same-schema labels remain distinct Plan selections" {
  let properties = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let definition = @carrier.property_node_definition(
    "N",
    [@contract.primitive(NumberType, nullable=false)],
    properties,
    ["A", "B"],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let graph = @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [definition],
    [],
    max_definitions=1,
    max_contract_work=1000,
  ).unwrap()
  let emitted = ["A", "a", "B"].map(label => {
    let owner = carrier_projection_owner(
      "[{\"from\":\"g\",\"node_rows\":{\"label\":\"" + label + "\"}}]",
      [("g", graph)],
    )
    let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
    let writer = @encode.writer(10000, 1000, 100)
    @lowering_relation.emit_sequence_steps(sequence, writer)
    @encode.finish(writer)
  })
  assert_eq(emitted[0], emitted[1])
  assert_false(emitted[0] == emitted[2])
}
