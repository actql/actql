///|
test "prepared inference array retirement waits for every original consumer" {
  let (input, source) = infer_preflight_fixture(
    (
      #|[{"id":"b","text":null,"secret":"private-b"},{"id":"a","text":"urgent","secret":"private-a"}]
    ),
  )
  let execution = start_infer_rows_preparation(
    @bounded.control(),
    input,
    infer_preflight_limits(),
  ).unwrap()
  let prepared = infer_preflight_drain(execution).unwrap()
  let first = acquire_prepared_infer_rows(prepared).unwrap()
  let second = acquire_prepared_infer_rows(prepared).unwrap()
  let keys = prepared.keys
  let values = prepared.values
  let key = prepared_infer_rows_key(prepared, 0, 0).unwrap()
  let owner = prepared_infer_rows_owner(prepared)
  assert_true(key.value is @admitted.Text("a"))
  assert_true(
    prepared_infer_rows_value(prepared, 0, 0).unwrap().value
    is @admitted.Text("urgent"),
  )
  assert_true(
    prepared_infer_rows_value(prepared, 1, 0).unwrap().value is @admitted.Null,
  )
  assert_true(cleanup_infer_rows_preparation(execution).unwrap())
  assert_false(cleanup_prepared_infer_rows(prepared))
  assert_true(release_prepared_infer_rows_use(first))
  assert_false(release_prepared_infer_rows_use(first))
  assert_false(cleanup_prepared_infer_rows(prepared))
  assert_true(physical_equal(keys, prepared.keys))
  assert_true(physical_equal(values, prepared.values))
  assert_eq(keys.length(), 2)
  assert_eq(values.length(), 2)
  assert_true(infer_rows_preparation_usage(execution).1 > 0)
  assert_true(prepared_infer_rows_key(prepared, 0, 0) is Some(_))
  assert_true(release_prepared_infer_rows_use(second))
  assert_true(cleanup_prepared_infer_rows(prepared))
  assert_true(acquire_prepared_infer_rows(prepared) is None)
  assert_true(prepared_infer_rows_key(prepared, 0, 0) is None)
  assert_true(prepared_infer_rows_value(prepared, 0, 0) is None)
  assert_eq(prepared.roots.capacity(), 0)
  assert_eq(keys.capacity(), 0)
  assert_eq(prepared.order.capacity(), 0)
  assert_eq(values.capacity(), 0)
  assert_eq(infer_rows_preparation_usage(execution).1, 0)
  assert_eq(infer_rows_preparation_logical_usage(execution).1, 0L)
  // Escaped immutable values and the borrowed source are not this owner's
  // backing arrays. Retirement must not invalidate or deep-clear them.
  assert_true(key.value is @admitted.Text("a"))
  assert_true(physical_equal(owner, prepared_infer_rows_owner(prepared)))
  assert_eq(captured_row_count(source), 2)
  assert_true(captured_cell(source, 0, 1) is Some(@admitted.Text("private-b")))
  assert_true(cleanup_prepared_infer_rows(prepared))
  assert_eq(keys.capacity(), 0)
  assert_eq(values.capacity(), 0)
  assert_eq(execution.state.mapped.capacity(), 0)
  assert_eq(execution.state.key_columns.capacity(), 0)
  assert_eq(execution.state.source_columns.capacity(), 0)
}

///|
test "cancelled inference preparation retires populated arrays without reclaiming input" {
  let (input, source) = infer_preflight_fixture(
    (
      #|[{"id":"a","text":"urgent","secret":"private-a"},{"id":"b","text":null,"secret":"private-b"}]
    ),
  )
  let control = @bounded.control()
  let execution = start_infer_rows_preparation(
    control,
    input,
    infer_preflight_limits(),
  ).unwrap()
  let mut reached = false
  for _ in 0..<1000 {
    if execution.state.values.length() == 1 {
      reached = true
      break
    }
    assert_true(
      advance_infer_rows_preparation(execution, 1).unwrap()
      is InferRowsContinue(..),
    )
  }
  assert_true(reached)
  assert_true(infer_rows_preparation_usage(execution).0 > 0)
  assert_true(infer_rows_preparation_usage(execution).1 > 0)
  let keys = execution.state.keys
  let values = execution.state.values
  let key = keys[0][0]
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_infer_rows_preparation(execution, 1).unwrap()
    is InferRowsStopped(Cancelled, ..),
  )
  // Cancellation observation alone is not physical retirement.
  assert_true(keys.length() > 0)
  assert_eq(values.length(), 1)
  assert_true(cleanup_infer_rows_preparation(execution).unwrap())
  assert_eq(keys.capacity(), 0)
  assert_eq(values.capacity(), 0)
  assert_eq(execution.state.roots.capacity(), 0)
  assert_eq(execution.state.order.capacity(), 0)
  assert_eq(execution.state.mapped.capacity(), 0)
  assert_eq(execution.state.key_columns.capacity(), 0)
  assert_eq(execution.state.source_columns.capacity(), 0)
  assert_eq(infer_rows_preparation_usage(execution).1, 0)
  assert_eq(infer_rows_preparation_logical_usage(execution).1, 0L)
  assert_true(key.value is @admitted.Text("a"))
  assert_eq(captured_row_count(source), 2)
  assert_true(captured_cell(source, 1, 1) is Some(@admitted.Text("private-b")))
  assert_false(@bounded.cleanup_pending(execution.session))
  assert_false(cleanup_infer_rows_preparation(execution).unwrap())
  assert_true(
    advance_infer_rows_preparation(execution, 1) is Err(Session(Terminal)),
  )
}

///|
test "rejected inference keys retire partial arrays under the original cleanup" {
  let (input, source) = infer_preflight_fixture(
    (
      #|[{"id":"same","text":"first","secret":"private-a"},{"id":"same","text":"second","secret":"private-b"}]
    ),
  )
  let execution = start_infer_rows_preparation(
    @bounded.control(),
    input,
    infer_preflight_limits(),
  ).unwrap()
  assert_true(infer_preflight_drain(execution) is Err(DuplicateKey(0, 1)))
  assert_true(execution.state.keys.length() > 0)
  assert_true(infer_rows_preparation_usage(execution).0 > 0)
  assert_true(cleanup_infer_rows_preparation(execution).unwrap())
  assert_eq(execution.state.roots.capacity(), 0)
  assert_eq(execution.state.keys.capacity(), 0)
  assert_eq(execution.state.order.capacity(), 0)
  assert_eq(execution.state.values.capacity(), 0)
  assert_eq(execution.state.mapped.capacity(), 0)
  assert_eq(execution.state.key_columns.capacity(), 0)
  assert_eq(execution.state.source_columns.capacity(), 0)
  assert_eq(infer_rows_preparation_usage(execution).1, 0)
  assert_eq(infer_rows_preparation_logical_usage(execution).1, 0L)
  assert_eq(captured_row_count(source), 2)
  assert_false(@bounded.cleanup_pending(execution.session))
  assert_false(cleanup_infer_rows_preparation(execution).unwrap())
}
