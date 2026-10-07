///|
test "native census binds real chain captures and retains producer metadata through cleanup retry" {
  let name = "x".repeat(256)
  let body = "[{\"from\":\"source\",\"select\":[\"" +
    name +
    "\"],\"as\":\"first\"},{\"from\":\"first\",\"select\":[\"" +
    name +
    "\"],\"as\":\"out\"}]"
  let (sequence, read, source) = chain_lifetime_fixture(body, source_name=name)
  let (active, state) = chain_lifetime_start(sequence, read)
  current_chain_observe(active, state, 0)
  for _ in 0..<10000 {
    if state.pending {
      break
    }
    assert_true(advance_managed_provider(active, 1).unwrap() is Continue(..))
  }
  assert_true(state.pending)
  for _ in 0..<6 {
    assert_true(advance_managed_provider(active, 1).unwrap() is Continue(..))
  }
  let preparation = state.input_preparation.unwrap()
  let metadata = preparation.read.unwrap()
  let completed = state.completed
  let output = completed[0].unwrap()
  let cleanup_calls = Ref(0)
  let polls = Ref(0)
  // A delayed existing child-owner cleanup makes the parent release boundary
  // observable while real metadata preparation is pending. It adds no product
  // owner, scheduler or recovery path.
  let delayed = managed_provider_execution(
    _ => {
      polls.val += 1
      Ok(managed_provider_stopped_poll(0L, 0L))
    },
    () => false,
    () => true,
    () => {
      cleanup_calls.val += 1
      match cleanup_calls.val {
        1 => Ok(false)
        2 => Err(@connector.InvalidLimits)
        _ => Ok(true)
      }
    },
  )
  state.children = [delayed]
  state.current = Some(delayed)
  let children = state.children
  current_chain_observe(active, state, 1)
  assert_true(cancel_managed_provider(active))
  assert_true(advance_managed_provider(active, 1).unwrap() is Stopped(..))
  current_chain_observe(active, state, 2)
  assert_false(cleanup_managed_provider(active).unwrap())
  current_chain_observe(active, state, 3)
  assert_true(cleanup_managed_provider(active) is Err(@connector.InvalidLimits))
  current_chain_observe(active, state, 4)
  assert_eq(cleanup_calls.val, 2)
  assert_true(physical_equal(state.children, children))
  assert_true(physical_equal(state.completed, completed))
  assert_true(physical_equal(state.completed[0].unwrap(), output))
  assert_true(physical_equal(state.current.unwrap(), delayed))
  assert_true(physical_equal(state.input_preparation.unwrap(), preparation))
  assert_true(physical_equal(preparation.read.unwrap(), metadata))
  assert_true(@execution.completed_output_available(output))
  assert_eq(polls.val, 0)
  let work = managed_provider_cumulative_work(active)
  assert_true(cleanup_managed_provider(active).unwrap())
  current_chain_observe(active, state, 5)
  assert_true(state.current is None)
  assert_true(state.input_preparation is None)
  assert_true(state.completed.is_empty())
  assert_true(state.children.is_empty())
  assert_true(preparation.read is None)
  assert_true(preparation.matched is None)
  assert_true(preparation.selected.is_empty())
  assert_true(cleanup_managed_provider(active).unwrap())
  current_chain_observe(active, state, 6)
  assert_eq(cleanup_calls.val, 3)
  assert_eq(polls.val, 0)
  assert_eq(managed_provider_cumulative_work(active), work)
  assert_true(@execution.completed_output_available(source))
  assert_true(@execution.producer_read_available(read))
  assert_true(@execution.completed_output_available(output))
}
