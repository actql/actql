///|
test "managed provider bridge yields a scoped ordinary reader for Local" {
  let producer = capture_fixture()
  let receiver = projected_consumer(
    producer,
    "[{\"renamed\":\"s\"}]",
    "[{\"select\":[\"renamed\"]}]",
    target=Step(1),
  )
  let input = prepare_managed_producer_read(
    receiver,
    0,
    producer,
    managed_read_fixture(producer, Ref(true)),
    1000,
    10000,
  ).unwrap()
  let bridge = prepare_managed_producer_bridge(
    input,
    2,
    stream_value_limits(),
    1000,
    10000,
  ).unwrap()
  for row in ["{\"n\":1,\"s\":\"é\"}", "{\"n\":2,\"s\":\"😀\"}"] {
    append_managed_producer_bridge_wire(bridge, row, retained_row_test_limits()).unwrap()
  }
  let read = finish_managed_producer_bridge(bridge, 1000, 10000).unwrap()
  assert_true(producer_read_available(read))
  assert_eq(producer_read_row_count(read), 2)
  assert_true(producer_read_cell(read, 1, 0) is Some(Text("😀")))
  close_managed_producer_bridge(bridge)
  assert_false(producer_read_available(read))
  assert_true(producer_read_cell(read, 0, 0) is None)
}

///|
test "managed bridge accepts a reference-free summary-backed view" {
  let owner = capture_fixture()
  let live = Ref(true)
  let source = managed_read_fixture(owner, live, index_cells=4)
  let selected_owner = typed_receiver(
    owner, "[{\"take\":1},{\"select\":[\"n\",\"s\"]}]",
  )
  let selected_input = prepare_managed_producer_read(
    selected_owner, 0, owner, source, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    selected_input,
    [row_kernel(selected_owner, 0), row_kernel(selected_owner, 1)],
    1000,
    10000,
    100,
  ).unwrap()
  let selection = prepare_managed_view_selection(plan, [0], 2, 100).unwrap()
  let stream = prepare_managed_output_values(
    selected_owner,
    Step(1),
    1,
    stream_value_limits(),
    100,
    managed_test_measure_limits(),
  ).unwrap()
  let retention = prepare_managed_output_retention_port(stream, (
    receipt : ManagedOutputValueReceipt,
  ) => Some((receipt, 8, 5L, fn() { true }))).unwrap()
  let token = Ref(())
  let port = prepare_managed_selected_view_output_port(selection, stream, (
    proof : Ref[Unit],
  ) => physical_equal(proof, token)).unwrap()
  let receipt = finish_managed_view_output(port, token).unwrap()
  assert_eq(receipt.rows, 1)
  assert_eq(receipt.reference_rows.length(), 0)
  let material = retain_managed_output(retention, receipt).unwrap()
  let generated = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(selected_owner),
    ["select_1"],
    10000,
    1000,
  ).unwrap()
  let completion = prepare_managed_completion_port(
    managed_test_profile(),
    generated,
    Step(1),
    1000,
    10000,
    (_ : Unit) => Some(material),
    managed_inputs=[selected_input],
  ).unwrap()
  let selected = complete_managed_output(completion, ()).unwrap()
  let consumer = typed_receiver(selected_owner, "[{\"select\":[\"s\"]}]")
  let input = prepare_managed_producer_read(
    consumer, 0, selected_owner, selected, 1000, 10000,
  ).unwrap()
  let bridge = prepare_managed_producer_bridge(
    input,
    1,
    stream_value_limits(),
    1000,
    10000,
  ).unwrap()
  append_managed_producer_bridge_wire(
    bridge,
    "{\"n\":1,\"s\":\"é\"}",
    retained_row_test_limits(),
  ).unwrap()
  let read = finish_managed_producer_bridge(bridge, 1000, 10000).unwrap()
  assert_true(producer_read_cell(read, 0, 1) is Some(Text("é")))
  close_managed_producer_bridge(bridge)
  assert_false(producer_read_available(read))
}

///|
fn managed_reference_owner() -> @lower.BoundPrepared {
  let contract = select_checked_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
  )
  let schema = @schema.from_fields(
    [(@schema.Unqualified("r"), contract)],
    max_fields=1,
    max_name_bytes=10,
  ).unwrap()
  let checked = @pipeline.check(
    input_cursor("[{\"select\":[\"r\"]}]"),
    [("source", schema)],
    None,
    Some(input_cursor("\"source\"")),
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
fn managed_reference_wire_with_identity(identity : String) -> String {
  "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"identity_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"provider_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"provider_namespace\":\"mail\",\"resource_kind\":\"mail/message\",\"version\":\"actql-resource-ref/0.1\"}".replace_all(
    old="sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    new=identity,
  )
}

///|
fn managed_reference_wire() -> String {
  managed_reference_wire_with_identity(
    "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  )
}

///|
fn managed_reference_output(
  owner : @lower.BoundPrepared,
  live : Ref[Bool],
) -> ManagedCompletedOutput[Int] raise {
  let schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    Step(0),
  ).unwrap()
  let contract = @schema.field_at(schema, 0).unwrap().contract
  let wire = managed_reference_wire()
  let checked = @admitted.issue_reference(
    @admitted.bind_reference_issuer((_, candidate) => candidate == wire, _ => {
      live.val
    }),
    contract,
    wire,
    { max_bytes: 4096, max_nodes: 64, max_depth: 4, max_text_units: 4096, },
  ).unwrap()
  managed_checked_output(owner, checked, live)
}

///|
fn managed_checked_output(
  owner : @lower.BoundPrepared,
  checked : @admitted.CheckedValue,
  live : Ref[Bool],
) -> ManagedCompletedOutput[Int] raise {
  let preparation = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["select_0"],
    10000,
    1000,
  ).unwrap()
  let values = prepare_managed_output_values(
    owner,
    Step(0),
    1,
    { max_nodes: 100, max_text_bytes: 10000, max_depth: 10, max_work: 10000, },
    8192,
    managed_test_measure_limits(),
  ).unwrap()
  let retention = prepare_managed_output_retention_port(values, receipt => {
    Some((receipt, 9, 1024L, fn() { live.val }))
  }).unwrap()
  append_managed_output_values(values, 1, _ => Some(checked)).unwrap()
  let material = retain_managed_output(
    retention,
    finish_managed_output_values(values).unwrap(),
  ).unwrap()
  let port = prepare_managed_completion_port(
    managed_test_profile(),
    preparation,
    Step(0),
    1000,
    10000,
    (_ : Unit) => Some(material),
  ).unwrap()
  complete_managed_output(port, ()).unwrap()
}

///|
fn managed_nested_reference_owner() -> @lower.BoundPrepared {
  let reference = "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}"
  let contract = select_checked_contract(
    "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"refs\":{\"type\":\"array\",\"nullable\":false,\"items\":" +
    reference +
    ",\"max_items\":2}}}",
  )
  let schema = @schema.from_fields(
    [(@schema.Unqualified("nested"), contract)],
    max_fields=1,
    max_name_bytes=10,
  ).unwrap()
  let checked = @pipeline.check(
    input_cursor("[{\"select\":[\"nested\"]}]"),
    [("source", schema)],
    None,
    Some(input_cursor("\"source\"")),
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
test "managed bridge preserves exact reference authority after input release" {
  let producer = managed_reference_owner()
  let producer_live = Ref(true)
  let output = managed_reference_output(producer, producer_live)
  let receiver = projected_consumer(
    producer,
    "[\"r\"]",
    "[{\"select\":[\"r\"]}]",
    target=Step(0),
  )
  let input = prepare_managed_producer_read(
    receiver, 0, producer, output, 1000, 10000,
  ).unwrap()
  let bridge = prepare_managed_producer_bridge(
    input,
    1,
    { max_nodes: 100, max_text_bytes: 10000, max_depth: 10, max_work: 10000, },
    1000,
    10000,
  ).unwrap()
  append_managed_producer_bridge_wire(
    bridge,
    "{\"r\":" + managed_reference_wire() + "}",
    { max_bytes: 8192, max_nodes: 100, max_depth: 10, max_text_bytes: 8192, },
  ).unwrap()
  let read = finish_managed_producer_bridge(bridge, 1000, 10000).unwrap()
  guard producer_read_cell(read, 0, 0)
    is Some(Captured(@admitted.Reference(reference))) else {
    fail("managed reference")
  }
  assert_eq(
    @admitted.reference_identity_cid(reference),
    "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  )
  assert_true(@admitted.reference_available(reference))
  close_managed_producer_bridge(bridge)
  assert_true(@admitted.reference_available(reference))
  assert_false(producer_read_available(read))
  producer_live.val = false
  assert_false(@admitted.reference_available(reference))
}

///|
test "managed bridge preserves nested reference occurrences in wire order" {
  let producer = managed_nested_reference_owner()
  let producer_live = Ref(true)
  let first = managed_reference_wire_with_identity(
    "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  )
  let second = managed_reference_wire_with_identity(
    "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
  )
  let schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(producer)),
    Step(0),
  ).unwrap()
  let contract = @schema.field_at(schema, 0).unwrap().contract
  let checked = @admitted.admit_host(
    @admitted.bind_reference_issuer(
      (_, candidate) => candidate == first || candidate == second,
      _ => producer_live.val,
    ),
    contract,
    input_cursor("{\"refs\":[" + first + "," + second + "]}"),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 10000, },
    { max_bytes: 4096, max_nodes: 64, max_depth: 4, max_text_units: 4096, },
  ).unwrap()
  let output = managed_checked_output(producer, checked, producer_live)
  let receiver = projected_consumer(
    producer,
    "[\"nested\"]",
    "[{\"select\":[\"nested\"]}]",
    target=Step(0),
  )
  let input = prepare_managed_producer_read(
    receiver, 0, producer, output, 1000, 10000,
  ).unwrap()
  let bridge = prepare_managed_producer_bridge(
    input,
    1,
    { max_nodes: 100, max_text_bytes: 10000, max_depth: 10, max_work: 10000, },
    1000,
    10000,
  ).unwrap()
  append_managed_producer_bridge_wire(
    bridge,
    "{\"nested\":{\"refs\":[" + first + "," + second + "]}}",
    { max_bytes: 16384, max_nodes: 100, max_depth: 10, max_text_bytes: 16384, },
  ).unwrap()
  let read = finish_managed_producer_bridge(bridge, 1000, 10000).unwrap()
  guard producer_read_cell(read, 0, 0)
    is Some(Captured(@admitted.Object(fields))) &&
    @admitted.element_at(fields, 0) is Some(("refs", @admitted.Array(items))) &&
    @admitted.element_at(items, 0) is Some(@admitted.Reference(left)) &&
    @admitted.element_at(items, 1) is Some(@admitted.Reference(right)) else {
    fail("nested managed references")
  }
  assert_eq(
    @admitted.reference_identity_cid(left),
    "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  )
  assert_eq(
    @admitted.reference_identity_cid(right),
    "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
  )
  close_managed_producer_bridge(bridge)
  assert_true(@admitted.reference_available(left))
  assert_true(@admitted.reference_available(right))
  let mismatched_input = prepare_managed_producer_read(
    receiver, 0, producer, output, 1000, 10000,
  ).unwrap()
  let mismatched = prepare_managed_producer_bridge(
    mismatched_input,
    1,
    { max_nodes: 100, max_text_bytes: 10000, max_depth: 10, max_work: 10000, },
    1000,
    10000,
  ).unwrap()
  assert_true(
    append_managed_producer_bridge_wire(
      mismatched,
      "{\"nested\":{\"refs\":[" + second + "," + first + "]}}",
      {
        max_bytes: 16384,
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 16384,
      },
    )
    is Err(Wire(Value(0, @admitted.ValueIssue(@admitted.InvalidReference, ..)))),
  )
  producer_live.val = false
  assert_false(@admitted.reference_available(left))
  assert_false(@admitted.reference_available(right))
}

///|
test "managed output rejects a reference revoked before completion" {
  let owner = managed_reference_owner()
  let live = Ref(true)
  let values = prepare_managed_output_values(
    owner,
    Step(0),
    1,
    { max_nodes: 100, max_text_bytes: 10000, max_depth: 10, max_work: 10000, },
    8192,
    managed_test_measure_limits(),
  ).unwrap()
  let schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    Step(0),
  ).unwrap()
  let contract = @schema.field_at(schema, 0).unwrap().contract
  let wire = managed_reference_wire()
  let checked = @admitted.issue_reference(
    @admitted.bind_reference_issuer((_, candidate) => candidate == wire, _ => {
      live.val
    }),
    contract,
    wire,
    { max_bytes: 4096, max_nodes: 64, max_depth: 4, max_text_units: 4096, },
  ).unwrap()
  append_managed_output_values(values, 1, _ => Some(checked)).unwrap()
  live.val = false
  assert_true(
    finish_managed_output_values(values) is Err(ReferenceUnavailable(0, 0)),
  )
}

///|
test "managed bridge rejects a reference absent from the producer receipt" {
  let producer = managed_reference_owner()
  let output = managed_reference_output(producer, Ref(true))
  let receiver = projected_consumer(
    producer,
    "[\"r\"]",
    "[{\"select\":[\"r\"]}]",
    target=Step(0),
  )
  let input = prepare_managed_producer_read(
    receiver, 0, producer, output, 1000, 10000,
  ).unwrap()
  let bridge = prepare_managed_producer_bridge(
    input,
    1,
    { max_nodes: 100, max_text_bytes: 10000, max_depth: 10, max_work: 10000, },
    1000,
    10000,
  ).unwrap()
  let foreign = managed_reference_wire().replace_all(
    old="sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    new="sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
  )
  assert_true(
    append_managed_producer_bridge_wire(bridge, "{\"r\":" + foreign + "}", {
      max_bytes: 8192,
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 8192,
    })
    is Err(Wire(Value(0, @admitted.ValueIssue(@admitted.InvalidReference, ..)))),
  )
}

///|
test "managed bridge rejects missing authority for reference-bearing rows" {
  let producer = managed_reference_owner()
  let output = managed_reference_output(producer, Ref(true))
  output.material.receipt.reference_rows.clear()
  let receiver = projected_consumer(
    producer,
    "[\"r\"]",
    "[{\"select\":[\"r\"]}]",
    target=Step(0),
  )
  let input = prepare_managed_producer_read(
    receiver, 0, producer, output, 1000, 10000,
  ).unwrap()
  assert_true(
    prepare_managed_producer_bridge(
      input,
      1,
      { max_nodes: 100, max_text_bytes: 10000, max_depth: 10, max_work: 10000, },
      1000,
      10000,
    )
    is Err(Wire(InvalidShape)),
  )
}
