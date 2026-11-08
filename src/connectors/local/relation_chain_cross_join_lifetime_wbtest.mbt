///|
fn cross_join_lifetime_body() -> String {
  "[{\"from\":\"source\",\"cross_join\":{\"with\":\"source\",\"select\":{\"id\":\"left.id\"}},\"as\":\"pairs\"},{\"from\":\"pairs\",\"select\":[\"id\"],\"as\":\"selected\"},{\"from\":\"selected\",\"select\":[\"id\"]}]"
}

///|
test "Cross Join chain retires actual child scratch while preserving every output" {
  let (sequence, read, source) = chain_lifetime_fixture(
    cross_join_lifetime_body(),
  )
  let count = @execution.generated_sequence_step_count(sequence)
  assert_eq(count, 3)
  assert_eq(relation_chain_reclaimed_prefix(sequence), count)
  let limits = chain_lifetime_limits()
  let measure = chain_lifetime_measurement()
  let mut retained = 0L
  let mut peak = 0L
  for index in 0..<count {
    let step = @execution.generated_sequence_step_index_at(sequence, index).unwrap()
    let selected = @execution.select_generated_sequence_step(sequence, step).unwrap()
    let child = chain_lifetime_child_capacity(selected, limits, measure)
    retained += child.retained_bytes
    peak = Int64::max(peak, child.execution_bytes)
  }
  let base = @execution.generated_sequence_capacity(sequence, limits, measure).unwrap()
  let quote = bounded_relation_chain_capacity(sequence, limits, measure, []).unwrap()
  assert_eq(quote.retained_bytes, base.retained_bytes)
  assert_eq(
    quote.execution_bytes,
    Int64::max(
      base.execution_bytes,
      retained + peak + count.to_int64() * 256L + 512L,
    ),
  )
  let (active, state) = chain_lifetime_start(sequence, read)
  let cleanups = Array::make(count, 0)
  let mut watched = -1
  let mut output = None
  for _ in 0..<100000 {
    if output is Some(_) {
      break
    }
    if !state.pending && watched != state.position {
      chain_lifetime_watch_child(state, cleanups)
      watched = state.position
    }
    match advance_managed_provider(active, 1).unwrap() {
      Continue(..) | Waiting(..) => ()
      Complete(result, ..) => output = Some(result)
      _ => fail("the original Cross Join chain must complete")
    }
    for index in 0..<state.position {
      let original = state.completed[index].unwrap()
      assert_true(@execution.completed_output_available(original))
      assert_eq(@execution.completed_row_count(original), 9)
    }
    if state.pending {
      assert_true(state.current is None)
      assert_true(state.children.is_empty())
    }
  }
  let output = output.unwrap()
  assert_eq(@execution.completed_row_count(output), 9)
  let mut ones = 0
  let mut twos = 0
  for row in 0..<9 {
    match @execution.completed_cell(output, row, 0).unwrap() {
      @execution.Number(1.0) => ones += 1
      @execution.Number(2.0) => twos += 1
      _ => fail("same original input values")
    }
  }
  assert_eq((ones, twos), (3, 6))
  assert_eq(cleanups, [1, 1, 0])
  let earlier = state.completed[0].unwrap()
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_eq(cleanups, [1, 1, 1])
  assert_true(state.children.is_empty())
  assert_true(state.completed.is_empty())
  assert_true(@execution.completed_output_available(earlier))
  assert_true(@execution.completed_output_available(output))
  assert_true(@execution.producer_read_available(read))
  assert_true(@execution.completed_output_available(source))
}

///|
test "Cross Join cleanup refusal retains original child and cannot start its successor" {
  let (sequence, read, source) = chain_lifetime_fixture(
    cross_join_lifetime_body(),
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
  for _ in 0..<100000 {
    if state.pending {
      break
    }
    assert_true(advance_managed_provider(active, 1).unwrap() is Continue(..))
  }
  assert_true(state.pending && state.reclaiming)
  assert_eq(calls.val, 1)
  let earlier = state.completed[0].unwrap()
  let polls = advances.val
  assert_true(
    advance_managed_provider(active, 1).unwrap() is Waiting(work=0L, ..),
  )
  assert_eq(calls.val, 2)
  assert_eq(state.position, 1)
  assert_true(physical_equal(state.current.unwrap(), watched))
  assert_true(
    advance_managed_provider(active, 1).unwrap() is Failed(_, work=0L, ..),
  )
  assert_true(managed_provider_stopped(active))
  assert_eq((calls.val, state.position), (3, 1))
  assert_true(physical_equal(state.children[0], watched))
  assert_true(@execution.completed_output_available(earlier))
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_eq((calls.val, advances.val), (4, polls))
  assert_true(state.current is None)
  assert_true(state.children.is_empty())
  assert_true(state.completed.is_empty())
  assert_true(@execution.completed_output_available(earlier))
  assert_true(@execution.producer_read_available(read))
  assert_true(@execution.completed_output_available(source))
}
