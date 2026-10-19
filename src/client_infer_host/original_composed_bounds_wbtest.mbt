///|
test "original composed bounds use the same Host and Plan clamps without issuing resources" {
  let prepared = fixture_prepared()
  let (occurrence, _) = original_composed_test_input(prepared)
  let graph = call_identity_plan(prepared)
  let (compiled, definition) = original_input_capacity_run(prepared, graph)
  let bounds = original_composed_bounds(compiled, definition, occurrence, graph).unwrap()
  assert_eq(bounds.model.max_items, 100)
  assert_eq(bounds.model.max_request_bytes, 1000L)
  assert_eq(bounds.model.max_response_bytes, 65536L)
  assert_eq(bounds.model.ledger.attempts, 4)
  assert_eq(bounds.model.ledger.transfer_bytes, 133072L)
  assert_eq(bounds.model.ledger.retained_bytes, 6553600L)
  assert_eq(bounds.model.ledger.execution_bytes, 6553600L)
  assert_eq(bounds.input.max_frames, 100)
  assert_eq(bounds.output_rows, 100)
}

///|
test "original composed bounds refuse foreign checked owners graphs and Run materials" {
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
    (run, actual_occurrence, actual_graph) in [
      (other_compiled, occurrence, graph),
      (compiled, other_occurrence, graph),
      (compiled, occurrence, other_graph),
    ] {
    assert_true(
      original_composed_bounds(run, definition, actual_occurrence, actual_graph)
      is Err(OriginalCapacity(@publication_host.ForeignInput)),
    )
  }
  assert_true(
    original_composed_bounds(compiled, other_definition, occurrence, graph)
    is Err(
      OriginalCapacity(@publication_host.Read(@publication_host.ForeignRun))
    ),
  )
}
