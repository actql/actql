///|
test "prepared composed bounds precede Run construction with the same Host and Plan clamps" {
  let prepared = fixture_prepared()
  let (occurrence, _) = original_composed_test_input(prepared)
  let graph = call_identity_plan(prepared)
  let bounds = prepared_composed_bounds(occurrence, graph).unwrap()
  assert_eq(bounds.model.max_items, 100)
  assert_eq(bounds.model.max_request_bytes, 1000L)
  assert_eq(
    @node_fixture.client_local_resource_policy_model_request_byte_ceiling(
      @input.client_local_resource_policy(),
    ),
    standard_limits().model.max_request_bytes,
  )
  assert_eq(standard_limits().model.max_request_bytes, 65536L)
  assert_eq(bounds.model.max_response_bytes, 65536L)
  assert_eq(bounds.model.ledger.attempts, 4)
  assert_eq(bounds.model.ledger.transfer_bytes, 133072L)
  assert_eq(bounds.model.ledger.retained_bytes, 6553600L)
  assert_eq(bounds.model.ledger.execution_bytes, 6553600L)
  assert_eq(bounds.input.max_frames, 100)
  assert_eq(bounds.output_rows, 100)
  let (compiled, definition) = original_input_capacity_run(prepared, graph)
  check_original_composed_preparation(compiled, definition, occurrence, graph).unwrap()
}

///|
test "prepared bounds and later original binding refuse foreign owners graphs and Run materials" {
  let prepared = fixture_prepared()
  let (occurrence, _) = original_composed_test_input(prepared)
  let graph = call_identity_plan(prepared)
  let (compiled, definition) = original_input_capacity_run(prepared, graph)
  let other = fixture_prepared(
    source=infer_fixture_program.replace(old="hello", new="foreign"),
  )
  let (other_occurrence, _) = original_composed_test_input(other)
  let other_graph = call_identity_plan(other)
  let (other_compiled, other_definition) = original_input_capacity_run(
    other, other_graph,
  )
  for
    (actual_occurrence, actual_graph) in [
      (other_occurrence, graph),
      (occurrence, other_graph),
    ] {
    assert_true(
      prepared_composed_bounds(actual_occurrence, actual_graph)
      is Err(OriginalCapacity(@publication_host.ForeignInput)),
    )
  }
  for
    (run, actual_occurrence, actual_graph) in [
      (other_compiled, occurrence, graph),
      (compiled, other_occurrence, graph),
      (compiled, occurrence, other_graph),
    ] {
    assert_true(
      check_original_composed_preparation(
        run, definition, actual_occurrence, actual_graph,
      )
      is Err(OriginalCapacity(@publication_host.ForeignInput)),
    )
  }
  assert_true(
    check_original_composed_preparation(
      compiled, other_definition, occurrence, graph,
    )
    is Err(
      OriginalCapacity(@publication_host.Read(@publication_host.ForeignRun))
    ),
  )
  assert_true(
    check_original_composed_preparation(
      compiled, other_definition, occurrence, other_graph,
    )
    is Err(OriginalCapacity(@publication_host.ForeignInput)),
  )
}

///|
test "actual typed Node prepared Model bounds and late binder keep their original tokens" {
  let prepared = fixture_prepared()
  let (occurrence, _) = original_composed_test_input(prepared)
  let graph = call_identity_plan(prepared)
  let bounds = @node_fixture.client_program_prepared_composed_infer_bounds(
    occurrence, graph,
  ).unwrap()
  assert_eq(bounds.model.max_items, 100)
  assert_eq(bounds.model.ledger.attempts, 4)
  assert_eq(bounds.model.ledger.transfer_bytes, 133072L)
  let (compiled, definition) = original_input_capacity_run(prepared, graph)
  @node_fixture.client_program_check_original_composed_infer_preparation(
    compiled, definition, occurrence, graph,
  ).unwrap()
  // The still-migrating late consumer uses its actual one binding/selection
  // adapter; it cannot substitute a different checked tuple.
  let late = @node_fixture.client_program_original_composed_infer_bounds(
    compiled, definition, occurrence, graph,
  ).unwrap()
  assert_eq(late.model.ledger, bounds.model.ledger)
  let other = fixture_prepared(
    source=infer_fixture_program.replace(old="hello", new="foreign"),
  )
  let other_graph = call_identity_plan(other)
  let (_, other_definition) = original_input_capacity_run(other, other_graph)
  assert_true(
    @node_fixture.client_program_check_original_composed_infer_preparation(
      compiled, other_definition, occurrence, graph,
    )
    is Err(
      OriginalCapacity(@publication_host.Read(@publication_host.ForeignRun))
    ),
  )
}
