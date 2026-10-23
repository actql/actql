///|
fn cleanup_progress_cursor(raw : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      raw,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="cleanup-progress.aql",
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
test "managed cleanup progress observes actual bounded retirement without acknowledging release" {
  let checked = @pipeline.check(
    cleanup_progress_cursor(
      "[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"n\":1}]},\"as\":\"rows\"}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 10,
      max_references: 10,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let values = prepare_managed_output_values(
    owner,
    Step(0),
    500,
    {
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 10,
      max_work: 100000,
    },
    100,
    { max_work: 100000, max_bytes: 100000, max_nodes: 10000, max_depth: 10, },
  ).unwrap()
  let contract = @schema.field_at(managed_output_values_schema(values), 0).unwrap().contract
  let cell = @admitted.admit(contract, cleanup_progress_cursor("1"), {
    max_nodes: 10,
    max_text_bytes: 100,
    max_depth: 2,
  }).unwrap()
  for _ in 0..<500 {
    append_managed_output_values(values, 1, _ => Some(cell)).unwrap()
  }
  let receipt = finish_managed_output_values(values).unwrap()
  assert_eq(managed_output_values_reclamation_steps(values), 0L)
  assert_false(advance_managed_output_values_reclamation(values, 1))
  assert_eq(managed_output_values_reclamation_steps(values), 0L)
  dispose_managed_output_values_scratch(values)
  assert_eq(managed_output_values_reclamation_steps(values), 64L)
  assert_false(managed_output_values_scratch_released(values))
  values.active_uses = 1
  assert_false(advance_managed_output_values_reclamation(values, 64))
  assert_eq(managed_output_values_reclamation_steps(values), 64L)
  values.active_uses = 0
  while !managed_output_values_scratch_released(values) {
    let previous = managed_output_values_reclamation_steps(values)
    advance_managed_output_values_reclamation(values, 7) |> ignore
    let current = managed_output_values_reclamation_steps(values)
    assert_true(current > previous && current - previous <= 7L)
    assert_true(current <= 1004L)
  }
  // One buffer boundary, two containers per row, and three column counters.
  assert_eq(managed_output_values_reclamation_steps(values), 1004L)
  assert_true(advance_managed_output_values_reclamation(values, 64))
  assert_eq(managed_output_values_reclamation_steps(values), 1004L)
  assert_eq(managed_output_value_row_count(receipt), 500)
  assert_eq(receipt.reference_rows.length(), 500)
}
