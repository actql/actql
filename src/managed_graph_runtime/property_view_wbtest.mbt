///|
fn property_view_carrier() -> @carrier.Carrier {
  let empty = @carrier.rows(
    [],
    field_set=@carrier.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let name = @carrier.rows(
    [
      (
        @schema.Unqualified("name"),
        Some(@contract.primitive(@contract.StringType, nullable=false)),
      ),
    ],
    field_set=@carrier.Closed,
    max_fields=1,
    max_name_bytes=4,
  ).unwrap()
  let weight = @carrier.rows(
    [(@schema.Unqualified("weight"), Some(number))],
    field_set=@carrier.Closed,
    max_fields=1,
    max_name_bytes=6,
  ).unwrap()
  let n = @carrier.property_node_definition(
    "N",
    [number],
    name,
    ["Node"],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let other = @carrier.property_node_definition(
    "Other",
    [number],
    empty,
    ["Other"],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let e = @carrier.property_node_definition(
    "E",
    [number],
    weight,
    ["R"],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  @carrier.property_graph(
    "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    [n, other],
    [@carrier.property_edge_definition(e, "N", "N").unwrap()],
    max_definitions=3,
    max_contract_work=1000,
  ).unwrap()
}

///|
// Empty checked pipelines bind an external input without claiming that an
// unimplemented SGA operation is accepted for the new profile.
fn property_view_owner() -> @lower.BoundPrepared {
  let checked = @pipeline.check_carriers(
    cursor("[]"),
    [("g", property_view_carrier())],
    None,
    Some(cursor("\"g\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn property_view_receiver(owner : @lower.BoundPrepared) -> @lower.BoundPrepared {
  let checked = @pipeline.check_with_evidence(
    cursor("[]"),
    [
      (
        "g",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(owner)),
            @pipeline.Input(0),
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(cursor("\"g\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "property graph view retains heterogeneous definitions and independent edge identity on one owner" {
  let owner = property_view_owner()
  let live = Ref(true)
  let output = prepare_output(
    owner,
    @pipeline.Input(0),
    @storage.DeclaredNodes,
    { ..graph_limits(), max_work: 10000, },
    4096L,
    () => live.val,
  ).unwrap()
  append_property_node(output, 0, [number(1.0)], [text("one")]).unwrap()
  append_property_node(output, 1, [number(1.0)], []).unwrap()
  append_property_edge(
    output,
    0,
    [number(10.0)],
    [number(1.0)],
    [number(1.0)],
    [number(3.0)],
  ).unwrap()
  append_property_edge(
    output,
    0,
    [number(11.0)],
    [number(1.0)],
    [number(1.0)],
    [number(4.0)],
  ).unwrap()
  let completed = finish_output(output).unwrap()
  let receiver = property_view_receiver(owner)
  let read = prepare_producer_read(receiver, 0, owner, completed).unwrap()
  let view = producer_read_view(read).unwrap()
  assert_eq(@lifecycle.producer_view_node_count(view), Some(2))
  assert_eq(@lifecycle.producer_view_edge_count(view), Some(2))
  assert_eq(@lifecycle.producer_view_node_definition(view, 0), Ok(0))
  assert_eq(@lifecycle.producer_view_node_definition(view, 1), Ok(1))
  assert_eq(@lifecycle.producer_view_edge_definition(view, 1), Ok(0))
  assert_true(
    @lifecycle.producer_view_node_key(view, 0, 0).unwrap().value
    is @value.Number(1.0),
  )
  assert_true(
    @lifecycle.producer_view_node_key(view, 1, 0).unwrap().value
    is @value.Number(1.0),
  )
  assert_true(
    @lifecycle.producer_view_edge_key(view, 0, 0).unwrap().value
    is @value.Number(10.0),
  )
  assert_true(
    @lifecycle.producer_view_edge_key(view, 1, 0).unwrap().value
    is @value.Number(11.0),
  )
  assert_true(
    @lifecycle.producer_view_node_key(view, 0, -1)
    is Err(@lifecycle.InvalidField),
  )
  assert_true(
    @lifecycle.producer_view_edge_key(view, 0, 1)
    is Err(@lifecycle.InvalidField),
  )
  assert_true(@lifecycle.producer_view_node_property(view, 0, 0) is Ok(_))
  assert_true(
    @lifecycle.producer_view_node_property(view, 1, 0)
    is Err(@lifecycle.InvalidField),
  )
  assert_eq(@lifecycle.producer_view_edge_endpoints(view, 0), Ok((0, 0)))
  assert_eq(@lifecycle.producer_view_edge_endpoints(view, 1), Ok((0, 0)))
  let first = @lifecycle.producer_view_edge_identity(view, 0).unwrap()
  let second = @lifecycle.producer_view_edge_identity(view, 1).unwrap()
  assert_true(
    @lifecycle.producer_view_node_identity_order_key(view, 0) is Ok(_),
  )
  assert_true(
    @lifecycle.producer_view_edge_identity_order_key(view, 0).unwrap() !=
    @lifecycle.producer_view_edge_identity_order_key(view, 1).unwrap(),
  )
  assert_true(
    @lifecycle.producer_view_node_identity_order_key(view, -1)
    is Err(@lifecycle.InvalidRecord),
  )
  assert_true(
    @lifecycle.producer_view_edge_identity_order_key(view, 2)
    is Err(@lifecycle.InvalidRecord),
  )
  assert_eq(
    @lifecycle.producer_view_edge_identity_index(view, first),
    Ok(Some(0)),
  )
  assert_eq(
    @lifecycle.producer_view_edge_identity_index(view, second),
    Ok(Some(1)),
  )
  assert_true(@lifecycle.producer_view_edge_property(view, 1, 0) is Ok(_))
  assert_true(
    @lifecycle.producer_view_edge_property(view, 1, 1)
    is Err(@lifecycle.InvalidField),
  )
  assert_true(
    @lifecycle.producer_view_edge_label(view, 0) is Err(@lifecycle.WrongCarrier),
  )
  assert_true(
    @lifecycle.producer_view_edge_index(view, first, first, None)
    is Err(@lifecycle.WrongCarrier),
  )
  assert_true(
    @lifecycle.producer_view_edge_identity(view, 2)
    is Err(@lifecycle.InvalidRecord),
  )
  let material = completed_material(completed).unwrap()
  let same = @lifecycle.material_prepare_view(material, receiver, 0, owner).unwrap()
  assert_eq(
    @lifecycle.producer_view_edge_identity_index(same, second),
    Ok(Some(1)),
  )
  let definition = @lifecycle.producer_view_property_graph_definition(view).unwrap()
  assert_eq(
    @carrier.property_definition_labels(
      @carrier.property_edge_element(
        @carrier.property_graph_edge_at(definition, 0).unwrap(),
      ),
    ),
    ["R"],
  )
  live.val = false
  assert_true(
    @lifecycle.producer_view_node_identity_order_key(view, 0)
    is Err(@lifecycle.Unavailable),
  )
  assert_true(
    @lifecycle.producer_view_edge_identity_order_key(view, 0)
    is Err(@lifecycle.Unavailable),
  )
  assert_true(
    @lifecycle.producer_view_node_key(view, 0, 0) is Err(@lifecycle.Unavailable),
  )
  assert_true(
    @lifecycle.producer_view_edge_key(view, 0, 0) is Err(@lifecycle.Unavailable),
  )
  assert_true(
    @lifecycle.producer_view_edge_identity(view, 0)
    is Err(@lifecycle.Unavailable),
  )
  assert_true(
    @lifecycle.producer_view_node_property(view, 0, 0)
    is Err(@lifecycle.Unavailable),
  )
  assert_true(
    @lifecycle.producer_view_property_graph_definition(view)
    is Err(@lifecycle.Unavailable),
  )
}

///|
test "property graph output failures reclaim the same builder without completing partial material" {
  let owner = property_view_owner()
  let output = prepare_output(
    owner,
    @pipeline.Input(0),
    @storage.DeclaredNodes,
    { ..graph_limits(), max_work: 10000, max_edges: 1, },
    4096L,
    () => true,
  ).unwrap()
  append_property_node(output, 0, [number(1.0)], [text("one")]).unwrap()
  append_property_edge(
    output,
    0,
    [number(10.0)],
    [number(1.0)],
    [number(1.0)],
    [number(3.0)],
  ).unwrap()
  assert_true(
    append_property_edge(
      output,
      0,
      [number(11.0)],
      [number(1.0)],
      [number(1.0)],
      [number(4.0)],
    )
    is Err(_),
  )
  assert_true(finish_output(output) is Err(_))
  assert_true(cancel_output(output))
  assert_true(finish_output(output) is Err(_))
}
