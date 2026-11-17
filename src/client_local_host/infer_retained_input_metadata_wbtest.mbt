///|
fn retained_metadata_test_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="retained-metadata.json",
    ).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn retained_metadata_test_output() -> (
  @execution.GeneratedSequence,
  @execution.CompletedOutput,
) raise {
  let contract = @contract.read_author(
    retained_metadata_test_cursor(
      (
        #|{"type":"object","nullable":false,"fields":{"id":{"type":"number","nullable":false},"bonus":{"type":"number","nullable":false}}}
      ),
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let schema = @schema.from_object(contract).unwrap()
  let checked = @pipeline.check(
    retained_metadata_test_cursor(
      (
        #|[{"from":"opportunities","join":{"kind":"inner","with":"files","on":[{"left":"id","right":"id"}],"select":{"id":"left.id","a":"left.bonus","b":"right.bonus"},"max_output_rows":2},"as":"pair"},{"from":"pair","join":{"kind":"inner","with":"contents","on":[{"left":"id","right":"id"}],"select":{"a":"left.a","b":"left.b","c":"right.bonus"},"max_output_rows":2},"as":"joined"}]
      ),
    ),
    [("opportunities", schema), ("files", schema), ("contents", schema)],
    None,
    Some(retained_metadata_test_cursor("\"opportunities\"")),
    {
      max_steps: 100,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let generated = @execution.prepare_generated_sequence(
    @execution.admit_relation_registry(
      content_recovery_registered_body(),
      content_recovery_registered_values(),
      { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, },
    ).unwrap(),
    @lower.prepare_sequence(
      owner,
      @publication_host.client_standard_values_sequence_limits(),
    ).unwrap(),
    [],
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(owner), 1).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  // All three checked input ports contribute independently visible values.
  // These are explicit captured inputs, not physical Connector acquisitions.
  let supplied = [
    ["{\"id\":1,\"bonus\":1}", "{\"id\":2,\"bonus\":2}"],
    ["{\"id\":1,\"bonus\":10}", "{\"id\":2,\"bonus\":20}"],
    ["{\"id\":1,\"bonus\":100}", "{\"id\":2,\"bonus\":200}"],
  ]
  let inputs = [0, 1, 2].map(index => {
    @execution.capture_input(
      owner,
      index,
      supplied[index].map(retained_metadata_test_cursor),
      max_rows=2,
      source_capture_values(),
    ).unwrap()
  })
  let output = @execution.completed_output(
    @execution.execute_generated_sequence(generated, inputs, {
      rows: {
        max_rows: 100,
        metadata_entries: 10000,
        retained_entries: 10000,
        operation_entries: 10000,
        input_values: source_capture_values(),
        output_values: source_capture_values(),
      },
      max_work: 100000,
      max_frames: 100,
    }).unwrap(),
    @pipeline.Step(1),
  ).unwrap()
  (generated, output)
}

///|
test "retained input export keeps input metadata independent of actual output rows" {
  let (_, input) = retained_metadata_test_output()
  let exported = export_client_infer_retained_input_owned(input, "metadata", 2).unwrap()
  let descriptor = read_client_infer_retained_input_descriptor(
    exported.descriptor_wire,
  ).unwrap()
  assert_eq(descriptor.input_count, 3)
  assert_eq(descriptor.rows, 2)
  assert_eq(descriptor.columns, 3)
  assert_eq(exported.rows.length(), 2)
  assert_true(exported.rows.contains("{\"a\":1,\"b\":10,\"c\":100}"))
  assert_true(exported.rows.contains("{\"a\":2,\"b\":20,\"c\":200}"))
  assert_true(client_infer_retained_input_export_matches(exported, input))
  // The selected row bound and standalone export retain their old behavior.
  assert_true(
    export_client_infer_retained_input_owned(input, "metadata", 1)
    is Err(Export(_)),
  )
  assert_true(export_client_infer_retained_input(input, "metadata") is Ok(_))
}

///|
test "all three input inventories survive export and restore with only two rows" {
  let (generated, input) = retained_metadata_test_output()
  let exported = export_client_infer_retained_input_owned(input, "metadata", 2).unwrap()
  let descriptor = read_client_infer_retained_input_descriptor(
    exported.descriptor_wire,
  ).unwrap()
  assert_eq(descriptor.input_count, 3)
  assert_eq(descriptor.rows, 2)
  assert_eq(descriptor.columns, 3)
  let custody = Ref(true)
  let restored = restore_client_retained_completion(
    @execution.generated_completion_preparation(generated),
    1,
    "metadata",
    exported.binding,
    exported.descriptor_wire,
    exported.rows,
    () => custody.val,
  ).unwrap()
  assert_eq(@execution.completed_row_count(restored.output), 2)
  assert_eq(@execution.completed_column_count(restored.output), 3)
  let names = ["a", "b", "c"]
  for index in 0..<names.length() {
    assert_eq(
      @execution.completed_column_name(restored.output, index),
      Some(names[index]),
    )
  }
  let roundtrip = export_client_infer_retained_input(
    restored.output,
    "restored-metadata",
  ).unwrap()
  assert_eq(roundtrip.rows, exported.rows)
  assert_true(roundtrip.rows.contains("{\"a\":1,\"b\":10,\"c\":100}"))
  assert_true(roundtrip.rows.contains("{\"a\":2,\"b\":20,\"c\":200}"))
  assert_true(@execution.completed_output_available(restored.output))
  custody.val = false
  assert_false(@execution.completed_output_available(restored.output))
  assert_true(close_client_infer_retained_input(restored))
  assert_true(@execution.completed_output_available(input))
}
