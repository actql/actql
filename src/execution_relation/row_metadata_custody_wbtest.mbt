///|
/// A delayed child cleanup keeps the existing parent owner responsible for
/// metadata cursors. This fault-injected callback is not a physical byte bound.
test "row metadata custody survives cancellation and delayed sort cleanup" {
  let execution = indexed_snapshot_fixture("x".repeat(256))
  let state = execution.state
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("x".repeat(256)),
        @contract.primitive(@contract.NumberType, nullable=false),
      ),
    ],
    max_fields=1,
    max_name_bytes=1000,
  ).unwrap()
  let lookup = start_row_metadata_lookup(
    schema,
    @schema.Unqualified("x".repeat(256)),
    state.workspace,
  ).unwrap()
  let charge = start_row_name_charge("x".repeat(256), state.workspace).unwrap()
  state.metadata_lookup = Some(lookup)
  state.name_charge = Some(charge)
  assert_true(advance_row_metadata_lookup(lookup) is None)
  assert_true(
    advance_row_name_charge(charge, None, Some(state.input_values)) is Ok(false),
  )
  let held = state.workspace.live
  assert_true(held >= 2)
  let cleanup_calls = Ref(0)
  let child_state : BoundedIndexSortState = {
    count: 1,
    compare: (_, _) => Ok(Some(0)),
    phase: Initialize,
    source: [0],
    target: [0],
    width: 1,
    start: 0,
    middle: 0,
    end: 0,
    left: 0,
    right: 0,
    output: 0,
  }
  let (session, token) = @bounded.start(
    state.engine,
    child_state,
    bounded_index_sort_step,
    value => {
      cleanup_calls.val += 1
      if cleanup_calls.val == 1 {
        false
      } else {
        value.source = []
        value.target = []
        true
      }
    },
    _ => true,
  )
  state.sort_execution = Some({ session, token: Some(token), })
  assert_true(@bounded.request_cancel(state.engine))
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  assert_false(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(bounded_binding_rows_cleanup_pending(execution))
  assert_true(state.sort_execution is Some(_))
  assert_true(physical_equal(state.metadata_lookup.unwrap(), lookup))
  assert_true(physical_equal(state.name_charge.unwrap(), charge))
  assert_false(lookup.closed)
  assert_false(charge.closed)
  assert_eq(state.workspace.live, held)
  assert_eq((child_state.source.length(), child_state.target.length()), (1, 1))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_false(bounded_binding_rows_cleanup_pending(execution))
  assert_true(lookup.closed)
  assert_true(charge.closed)
  assert_true(state.metadata_lookup is None)
  assert_true(state.name_charge is None)
  assert_true(state.sort_execution is None)
  assert_eq(state.workspace.live, 0)
  assert_eq(cleanup_calls.val, 2)
  cleanup_bounded_binding_rows(execution).unwrap() |> ignore
  close_row_metadata_lookup(lookup)
  close_row_name_charge(charge)
  assert_eq((state.workspace.live, cleanup_calls.val), (0, 2))
}
