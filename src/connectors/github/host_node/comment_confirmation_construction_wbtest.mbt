///|
test "confirmed native profile preserves original four roles and separates all three new constructors" {
  let original = installed_standard_create_construction_profile().unwrap()
  let confirmed = installed_standard_create_confirmed_construction_profile().unwrap()
  assert_eq(original.length(), 4)
  assert_eq(confirmed.length(), 7)
  for i in 0..<4 {
    let (before, _, _) = original[i]
    let (after, _, _) = confirmed[i]
    assert_eq(
      @execution.execution_capacity_retained_bytes(before),
      @execution.execution_capacity_retained_bytes(after),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(before),
      @execution.execution_capacity_execution_bytes(after),
    )
  }
  let (_, request_input, request_output) = confirmed[4]
  assert_true(request_input is None)
  assert_eq(request_output.unwrap().max_nodes, 2)
  let (_, reply_input, _) = confirmed[5]
  let (_, saved_input, _) = confirmed[6]
  assert_eq(reply_input.unwrap().max_input_bytes, 100000)
  assert_eq(saved_input.unwrap().max_input_bytes, 300000)
  assert_eq(saved_input.unwrap().max_nodes, 10000)
  for i in 4..<7 {
    let (capacity, _, _) = confirmed[i]
    assert_true(@execution.execution_capacity_retained_bytes(capacity) > 0L)
    assert_true(
      @execution.execution_capacity_execution_bytes(capacity) >=
      @execution.execution_capacity_retained_bytes(capacity),
    )
  }
}

///|
test "confirmation request native quantity bounds both escaped original node and exported JSON" {
  let node = "\u{1}".repeat(256)
  let inner = @catalog.comment_confirmation_request(node).unwrap()
  let outer = github_comment_confirmation_request_json(node)
  let (_, old_outer) = github_comment_request_wire_bounds(true)
  let delta = Int64::max(
    0L,
    @catalog.comment_confirmation_query.length().to_int64() -
    @catalog.comment_subject_query.length().to_int64(),
  )
  assert_true(outer.length().to_int64() <= old_outer + delta)
  let inventory = github_comment_confirmation_request_inventory().unwrap()
  assert_true(
    inventory.owned_utf16_units >=
    2L * inner.length().to_int64() + 2L * outer.length().to_int64(),
  )
  let (_, _, shape) = installed_standard_create_confirmed_construction_profile().unwrap()[4]
  assert_true(@utf8.encode(outer).length() <= shape.unwrap().max_input_bytes)
}

///|
test "confirmed native semantic workspace includes failed marked-body and supplied-width decoder paths" {
  //131072 UTF16 input units plus95 actual marker units; all three Source
  // concat alternatives remain charged even on the before-decode refusal.
  let expected_text = 3L * (131072L + 95L)
  for saved in [false, true] {
    let workspace = github_comment_confirmation_semantic_workspace(saved).unwrap()
    assert_eq(workspace.owned_utf16_units, expected_text)
    assert_true(workspace.record_headers > 10000L)
    assert_true(workspace.reference_slots > workspace.record_headers)
    assert_true(
      @execution.preparation_representation_cost(workspace).unwrap() >
      2L * expected_text,
    )
  }
  let (before, _, _) = installed_standard_create_construction_profile().unwrap()[2]
  for i in [5, 6] {
    let (after, _, _) = installed_standard_create_confirmed_construction_profile().unwrap()[i]
    assert_eq(
      @execution.execution_capacity_retained_bytes(after),
      @execution.execution_capacity_retained_bytes(before),
    )
    assert_true(
      @execution.execution_capacity_execution_bytes(after) >
      @execution.execution_capacity_execution_bytes(before),
    )
  }
}
