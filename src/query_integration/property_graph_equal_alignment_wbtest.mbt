///|
fn equality_alignment_carrier(
  edge : Bool,
  reverse : Bool,
) -> @carrier_contract.Carrier {
  let number = @value_contract.primitive(
    @value_contract.NumberType,
    nullable=false,
  )
  let properties = @carrier_contract.rows(
    (if reverse { ["q", "p"] } else { ["p", "q"] }).map(name => {
      (@schema.Unqualified(name), Some(number))
    }),
    field_set=@carrier_contract.Closed,
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let empty = @carrier_contract.rows(
    [],
    field_set=@carrier_contract.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let node = @carrier_contract.property_node_definition(
    "N",
    [number],
    if edge {
      empty
    } else {
      properties
    },
    ["Node"],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let link = @carrier_contract.property_node_definition(
    "E",
    [number],
    if edge {
      properties
    } else {
      empty
    },
    ["Edge"],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  @carrier_contract.property_graph(
    "sha256:" + "0".repeat(64),
    [node],
    [@carrier_contract.property_edge_definition(link, "N", "N").unwrap()],
    max_definitions=2,
    max_contract_work=10000,
  ).unwrap()
}

///|
fn equality_alignment_owner(
  carrier : @carrier_contract.Carrier,
) -> @lower.BoundPrepared {
  let checked = @pipeline.check_carriers(
    input_cursor("[]"),
    [("g", carrier)],
    None,
    Some(input_cursor("\"g\"")),
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 100000,
      max_identifier_bytes: 100000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn equality_alignment_output(
  owner : @lower.BoundPrepared,
  edge : Bool,
  values : Array[Int],
) -> @graphs.Completed {
  let number = @value_contract.primitive(
    @value_contract.NumberType,
    nullable=false,
  )
  let key = [@admitted.checked_number_value(1, number).unwrap()]
  let properties = values.map(value => {
    @admitted.checked_number_value(value.to_double(), number).unwrap()
  })
  let output = @graphs.prepare_output(
    owner,
    @pipeline.Input(0),
    @graph_storage.DeclaredNodes,
    carrier_graph_storage_limits(),
    4096L,
    () => true,
  ).unwrap()
  @graphs.append_property_node(
    output,
    0,
    key,
    if edge {
      []
    } else {
      properties
    },
  ).unwrap()
  if edge {
    @graphs.append_property_edge(output, 0, key, key, key, properties).unwrap()
  }
  @graphs.finish_output(output).unwrap()
}

///|
fn equality_alignment_receiver(
  left : @lower.BoundPrepared,
  right : @lower.BoundPrepared,
) -> @lower.BoundPrepared {
  let produced = fn(owner) {
    @pipeline.ProducedInput(
      @pipeline.produced_input(
        @lower.pipeline(@lower.bound_preparation(owner)),
        @pipeline.Input(0),
      ).unwrap(),
    )
  }
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{\"graphs_equal\":{\"with\":\"other\"}}]"),
    [("g", produced(left)), ("other", produced(right))],
    None,
    Some(input_cursor("\"g\"")),
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 100000,
      max_identifier_bytes: 100000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn equality_alignment_case(
  edge : Bool,
  equal : Bool,
  cancel? : Bool = false,
) -> Unit raise {
  let first_carrier = equality_alignment_carrier(edge, false)
  let second_carrier = equality_alignment_carrier(edge, true)
  // Both declaration orders are admitted into the same canonical property
  // index order. Appending values uses that order, not the authored order.
  for carrier in [first_carrier, second_carrier] {
    guard carrier is @carrier_contract.GraphValue(graph) else {
      fail("expected a current Graph")
    }
    let definition = @carrier_contract.graph_property_definition(graph)
    let element = if edge {
      @carrier_contract.property_edge_element(
        @carrier_contract.property_graph_edge_at(definition, 0).unwrap(),
      )
    } else {
      @carrier_contract.property_graph_node_at(definition, 0).unwrap()
    }
    let properties = @carrier_contract.property_definition_properties(element)
    assert_eq(
      @carrier_contract.field_at(properties, 0).unwrap().name,
      @schema.Unqualified("p"),
    )
    assert_eq(
      @carrier_contract.field_at(properties, 1).unwrap().name,
      @schema.Unqualified("q"),
    )
  }
  let first_owner = equality_alignment_owner(first_carrier)
  let second_owner = equality_alignment_owner(second_carrier)
  let first = equality_alignment_output(first_owner, edge, [1, 2])
  let second = equality_alignment_output(
    second_owner,
    edge,
    if equal {
      [1, 2]
    } else {
      [2, 1]
    },
  )
  // The two producers deliberately share domain and element identity. A
  // provenance mismatch cannot shortcut the property comparison under test.
  let first_storage = @graphs.completed_storage(first).unwrap()
  let second_storage = @graphs.completed_storage(second).unwrap()
  assert_eq(
    @graph_storage.node_identity_order_key(first_storage, 0),
    @graph_storage.node_identity_order_key(second_storage, 0),
  )
  if edge {
    assert_eq(
      @graph_storage.edge_identity_order_key(first_storage, 0),
      @graph_storage.edge_identity_order_key(second_storage, 0),
    )
  }
  let receiver = equality_alignment_receiver(first_owner, second_owner)
  let left = @graphs.prepare_producer_read(receiver, 0, first_owner, first).unwrap()
  let right = @graphs.prepare_producer_read(receiver, 1, second_owner, second).unwrap()
  let limits : @execution.ValueLimits = {
    max_work: 100000,
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 50,
  }
  // The unchanged kernel admits its existing single live comparison cursor.
  assert_true(
    @local_sga.start_property_equality_views(
      @bounded.control(),
      task_test_completion(receiver),
      prepared_sequence(receiver),
      0,
      @graphs.producer_read_view(left).unwrap(),
      @graphs.producer_read_view(right).unwrap(),
      1,
      limits,
      0,
      10000,
      10000,
      100000,
    )
    is Err(@local_sga.PropertyEqualityWorkspaceLimit),
  )
  let control = @bounded.control()
  let active = @local_sga.start_property_equality_views(
    control,
    task_test_completion(receiver),
    prepared_sequence(receiver),
    0,
    @graphs.producer_read_view(left).unwrap(),
    @graphs.producer_read_view(right).unwrap(),
    1,
    limits,
    1,
    10000,
    10000,
    100000,
  ).unwrap()
  let mut result = None
  let mut stopped = false
  let mut prior_work = 0L
  for tick in 0..<10000 {
    if cancel && tick == 8 {
      assert_true(@bounded.request_cancel(control))
    }
    match @local_sga.advance_property_equality(active, 1).unwrap() {
      @local_sga.PropertyEqualityContinue(work~, ..) => {
        assert_true(work > prior_work && work - prior_work <= 1L)
        prior_work = work
      }
      @local_sga.PropertyEqualityComplete(output, ..) => {
        assert_false(cancel)
        result = Some(output)
        break
      }
      @local_sga.PropertyEqualityStopped(_, ..) => {
        assert_true(cancel)
        stopped = true
        break
      }
      _ => fail("property alignment comparison failed")
    }
  }
  if cancel {
    assert_true(stopped)
    assert_true(result is None)
  } else {
    let wire = @execution.completed_output_row_wire(
      result.unwrap(),
      0,
      10000,
      10000,
      50,
    ).unwrap()
    assert_eq(
      wire,
      if equal {
        "{\"equal\":true}"
      } else {
        "{\"equal\":false}"
      },
    )
  }
  assert_true(@local_sga.cleanup_property_equality(active).unwrap())
  assert_false(@local_sga.property_equality_cleanup_pending(active))
  assert_true(@graphs.producer_read_available(left))
  assert_true(@graphs.producer_read_available(right))
  assert_true(@graphs.discard_completed(first))
  assert_true(@graphs.discard_completed(second))
}

///|
test "property Graph equality compares canonical node properties after reversed declarations" {
  equality_alignment_case(false, true)
}

///|
test "property Graph equality distinguishes swapped canonical node property values" {
  equality_alignment_case(false, false)
}

///|
test "property Graph equality compares canonical edge properties after reversed declarations" {
  equality_alignment_case(true, true)
}

///|
test "property Graph equality distinguishes swapped canonical edge property values" {
  equality_alignment_case(true, false)
}

///|
test "property Graph equality cancels canonical node properties without releasing inputs" {
  equality_alignment_case(false, true, cancel=true)
}

///|
test "property Graph equality cancels canonical edge properties without releasing inputs" {
  equality_alignment_case(true, true, cancel=true)
}
