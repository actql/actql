///|
test "stopped selected Filter exposes only counted private retirement" {
  let rows = Array::makei(64, index => {
    "{\"id\":" + (index + 2).to_string() + ",\"left\":[1,2],\"right\":[3,4]}"
  }).join(",")
  let (source_owner, source) = bounded_binding_rows_source("[" + rows + "]")
  let receiver = bounded_binding_rows_receiver(source_owner, filter=true)
  let sequence = prepared_sequence(receiver)
  let fragment = @lower.prepare_fragment_pipeline(sequence, 0, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  // This fixture has 64 actual rows. Its original request and runtime ceiling
  // must agree; the existing two-row fixture's ten-row request cannot bind it.
  let request = @lower.prepare_fragment_request(fragment, 64L, 1000L).unwrap()
  let context = prepare_runtime_fragment(
    request,
    test_fragment_contract(),
    material_demands(),
    registry_limits(),
    {
      max_input_rows: 64L,
      max_value_bytes: 1000L,
      max_live_value_bytes: 10000L,
      max_work: 100000L,
    },
  ).unwrap()
  let node = @lower.node_at(@lower.bound_preparation(receiver), 0).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [context],
    [@lower.node_id(node)],
    100000,
    10000,
  ).unwrap()
  let bound = bind_completed_input(receiver, 0, source_owner, source).unwrap()
  let read = prepare_producer_read(receiver, bound, 100, 10000).unwrap()
  let control = @bounded.control()
  let active = start_bounded_binding_rows(
    control,
    generated,
    read,
    100,
    run_limits().input_values,
    run_limits().output_values,
    100000,
    100,
    10000,
    10000,
  ).unwrap()
  assert_eq(bounded_binding_rows_cleanup_continuation(active), -1L)
  let mut partial = false
  for _ in 0..<100000 {
    guard advance_bounded_binding_rows(active, 1).unwrap()
      is BoundedBindingRowsContinue(..) else {
      fail("the original partial Filter must not publish")
    }
    if active.state.output.unwrap().buffer.rows.length() >= 24 {
      partial = true
      break
    }
  }
  assert_true(partial)
  @bounded.request_cancel(control) |> ignore
  assert_true(
    advance_bounded_binding_rows(active, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  assert_eq(bounded_binding_rows_cleanup_continuation(active), -1L)
  assert_false(cleanup_bounded_binding_rows(active).unwrap())
  let output = active.state.output.unwrap()
  let work = output.buffer.budget.work
  let mut previous = bounded_binding_rows_cleanup_continuation(active)
  assert_true(previous > 0L && previous <= 64L)
  for _ in 0..<100 {
    if cleanup_bounded_binding_rows(active).unwrap() {
      break
    }
    let current = bounded_binding_rows_cleanup_continuation(active)
    assert_true(current > previous && current - previous <= 64L)
    previous = current
  }
  assert_false(bounded_binding_rows_cleanup_pending(active))
  assert_eq(bounded_binding_rows_cleanup_continuation(active), -1L)
  assert_eq(output.buffer.budget.work, work)
  assert_true(producer_read_available(read))
}
