///|
fn retained_metadata_test_cursor(text : String) -> @decode.Cursor raise {
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
fn retained_metadata_test_output() -> @execution.CompletedOutput raise {
  let contract = @contract.read_author(
    retained_metadata_test_cursor(
      (
        #|{"type":"object","nullable":false,"fields":{"id":{"type":"number","nullable":false}}}
      ),
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let schema = @schema.from_object(contract).unwrap()
  let checked = @pipeline.check(
    retained_metadata_test_cursor(
      (
        #|[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"seed"}]
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
        @lower.node_at(@lower.bound_preparation(owner), 0).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let inputs = [0, 1, 2].map(index => {
    @execution.capture_input(
      owner,
      index,
      [],
      max_rows=0,
      source_capture_values(),
    ).unwrap()
  })
  @execution.completed_output(
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
    @pipeline.Step(0),
  ).unwrap()
}

///|
test "retained input export keeps input metadata independent of actual output rows" {
  let input = retained_metadata_test_output()
  let exported = export_client_infer_retained_input_owned(input, "metadata", 2).unwrap()
  let descriptor = read_client_infer_retained_input_descriptor(
    exported.descriptor_wire,
  ).unwrap()
  assert_eq(descriptor.input_count, 3)
  assert_eq(descriptor.rows, 2)
  assert_eq(exported.rows, ["{\"id\":1}", "{\"id\":2}"])
  assert_true(client_infer_retained_input_export_matches(exported, input))
  // The selected row bound and standalone export retain their old behavior.
  assert_true(
    export_client_infer_retained_input_owned(input, "metadata", 1)
    is Err(Export(_)),
  )
  assert_true(export_client_infer_retained_input(input, "metadata") is Ok(_))
}
