///|
fn analytic_lifetime_body() -> String {
  "[{\"from\":\"source\",\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"}}},\"as\":\"ranked\"},{\"from\":\"ranked\",\"select\":[\"id\",\"position\"],\"as\":\"out\"}]"
}

///|
// Analytic uses the same bounded group cleanup as aggregate kernels. Accepted
// output must survive that cleanup before another chain child starts.
test "analytic chain reclaims scratch without invalidating ranked output" {
  let (sequence, read, source) = chain_lifetime_fixture(
    analytic_lifetime_body(),
  )
  assert_true(relation_chain_reclaims_completed_scratch(sequence))
  let limits = chain_lifetime_limits()
  let measure = chain_lifetime_measurement()
  let count = @execution.generated_sequence_step_count(sequence)
  let mut retained = 0L
  let mut peak = 0L
  let mut sum = 0L
  for index in 0..<count {
    let step = @execution.generated_sequence_step_index_at(sequence, index).unwrap()
    let selected = @execution.select_generated_sequence_step(sequence, step).unwrap()
    let child = chain_lifetime_child_capacity(selected, limits, measure)
    retained += child.retained_bytes
    peak = Int64::max(peak, child.execution_bytes)
    sum += child.execution_bytes
  }
  let base = @execution.generated_sequence_capacity(sequence, limits, measure).unwrap()
  let handles = count.to_int64() * 256L + 512L
  let capacity = bounded_relation_chain_capacity(sequence, limits, measure, []).unwrap()
  assert_eq(
    capacity.execution_bytes,
    Int64::max(base.execution_bytes, retained + peak + handles),
  )
  assert_true(capacity.execution_bytes < retained + sum + handles)
  let (active, state) = chain_lifetime_start(sequence, read)
  let cleanups = Array::make(count, 0)
  let mut watched = -1
  let mut result = None
  for _ in 0..<100000 {
    if result is Some(_) {
      break
    }
    if !state.pending && watched != state.position {
      chain_lifetime_watch_child(state, cleanups)
      watched = state.position
    }
    let before = state.position
    match advance_managed_provider(active, 1).unwrap() {
      Continue(..) => ()
      Complete(output, ..) => result = Some(output)
      _ => fail("analytic lifetime chain did not complete")
    }
    if state.position != before {
      assert_eq(cleanups[before], 1)
      assert_true(state.children.is_empty())
      assert_true(
        @execution.completed_output_available(state.completed[before].unwrap()),
      )
    }
  }
  let output = result.unwrap()
  assert_eq(@execution.completed_row_count(output), 3)
  for (column, expected) in [(0, [2.0, 1.0, 2.0]), (1, [2.0, 1.0, 3.0])] {
    for row in 0..<3 {
      assert_true(
        @execution.completed_cell(output, row, column)
        is Some(@execution.Number(actual)) &&
        actual == expected[row],
      )
    }
  }
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_eq(cleanups, Array::make(count, 1))
  assert_true(@execution.completed_output_available(output))
  assert_true(@execution.completed_output_available(source))
}

///|
test "analytic intermediate cleanup false and error preserve child custody until parent retry" {
  let (sequence, read, source) = chain_lifetime_fixture(
    analytic_lifetime_body(),
  )
  let (active, state) = chain_lifetime_start(sequence, read)
  let child = state.current.unwrap()
  let calls = Ref(0)
  let advances = Ref(0)
  let watched = managed_provider_execution(
    q => {
      advances.val += 1
      advance_managed_provider(child, q)
    },
    () => cancel_managed_provider(child),
    () => managed_provider_stopped(child),
    () => {
      calls.val += 1
      match calls.val {
        1 | 2 => Ok(false)
        3 => Err(@connector.InvalidLimits)
        _ => cleanup_managed_provider(child)
      }
    },
  )
  state.current = Some(watched)
  state.children = [watched]
  for _ in 0..<10000 {
    if state.pending {
      break
    }
    assert_true(advance_managed_provider(active, 1).unwrap() is Continue(..))
  }
  assert_true(state.pending)
  assert_true(state.reclaiming)
  assert_eq(calls.val, 1)
  let output = state.completed[0].unwrap()
  let work = managed_provider_cumulative_work(active)
  let polls = advances.val
  assert_true(physical_equal(state.current.unwrap(), watched))
  assert_true(physical_equal(state.children[0], watched))
  assert_true(
    advance_managed_provider(active, 1).unwrap() is Waiting(work=0L, ..),
  )
  assert_eq(calls.val, 2)
  assert_false(managed_provider_stopped(active))
  assert_true(physical_equal(state.current.unwrap(), watched))
  assert_true(physical_equal(state.children[0], watched))
  assert_true(
    advance_managed_provider(active, 1).unwrap() is Failed(_, work=0L, ..),
  )
  assert_true(managed_provider_stopped(active))
  assert_eq(calls.val, 3)
  assert_eq(state.position, 1)
  assert_true(physical_equal(state.current.unwrap(), watched))
  assert_true(physical_equal(state.children[0], watched))
  assert_true(@execution.completed_output_available(output))
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_eq(calls.val, 4)
  assert_eq(advances.val, polls)
  assert_eq(managed_provider_cumulative_work(active), work)
  assert_true(state.current is None)
  assert_true(state.children.is_empty())
  assert_true(state.completed.is_empty())
  assert_true(@execution.completed_output_available(output))
  assert_true(@execution.producer_read_available(read))
  assert_true(@execution.completed_output_available(source))
}

///|
test "analytic cancelling pending intermediate cleanup preserves reclamation custody" {
  let (sequence, read, source) = chain_lifetime_fixture(
    analytic_lifetime_body(),
  )
  let (active, state) = chain_lifetime_start(sequence, read)
  let child = state.current.unwrap()
  let calls = Ref(0)
  let watched = managed_provider_execution(
    q => advance_managed_provider(child, q),
    () => cancel_managed_provider(child),
    () => managed_provider_stopped(child),
    () => {
      calls.val += 1
      if calls.val == 1 {
        Ok(false)
      } else {
        cleanup_managed_provider(child)
      }
    },
  )
  state.current = Some(watched)
  state.children = [watched]
  for _ in 0..<10000 {
    if state.pending {
      break
    }
    assert_true(advance_managed_provider(active, 1).unwrap() is Continue(..))
  }
  assert_true(state.pending)
  assert_true(state.reclaiming)
  let output = state.completed[0].unwrap()
  let work = managed_provider_cumulative_work(active)
  assert_eq(calls.val, 1)
  assert_true(cancel_managed_provider(active))
  assert_true(
    advance_managed_provider(active, 1).unwrap() is Stopped(work=0L, ..),
  )
  assert_eq(state.position, 1)
  assert_true(physical_equal(state.current.unwrap(), watched))
  assert_true(physical_equal(state.children[0], watched))
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_eq(calls.val, 2)
  assert_true(state.current is None)
  assert_true(state.children.is_empty())
  assert_true(state.completed.is_empty())
  assert_eq(managed_provider_cumulative_work(active), work)
  assert_true(@execution.completed_output_available(output))
  assert_true(@execution.producer_read_available(read))
  assert_true(@execution.completed_output_available(source))
}
