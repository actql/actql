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
  // Reach a populated columns buffer while the real metadata cursor still
  // belongs to the pending chain. This is a phase selection, not a relaxed
  // product budget or an arbitrary fixture-derived upper bound.
  for _ in 0..<100 {
    if current_columns_count(metadata) > 0 {
      break
    }
    assert_true(advance_managed_provider(active, 1).unwrap() is Continue(..))
  }
  assert_eq(current_columns_count(metadata), 1)
  assert_true(state.pending)
  assert_true(physical_equal(preparation.read.unwrap(), metadata))
  println(
    current_preparation_storage_probe(preparation, metadata, None, 0, 1, 1),
  )
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
  assert_eq(current_columns_count(metadata), 1)
  current_chain_observe(active, state, 2)
  assert_false(cleanup_managed_provider(active).unwrap())
  assert_eq(current_columns_count(metadata), 1)
  current_chain_observe(active, state, 3)
  assert_true(cleanup_managed_provider(active) is Err(@connector.InvalidLimits))
  assert_eq(current_columns_count(metadata), 1)
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
  println(
    current_preparation_storage_probe(preparation, metadata, None, 1, 1, 1),
  )
  assert_eq(current_columns_count(metadata), 0)

  // Reuse the same independently completed occurrence with the existing
  // preparation API. Completion transfers columns into a ProducerRead without
  // copying them. The probe keeps explicit references and makes no GC claim.
  let transferred_preparation = start_relation_chain_inputs(
    sequence,
    1,
    [managed_provider_relation_input(read)],
    completed,
    1000,
    10000,
  ).unwrap()
  let mut transferred_metadata : @execution.ProducerReadPreparation? = None
  for _ in 0..<100 {
    if !transferred_preparation.selected.is_empty() {
      break
    }
    assert_true(
      advance_relation_chain_inputs(transferred_preparation).unwrap() is None,
    )
    if transferred_preparation.read is Some(cursor) {
      transferred_metadata = Some(cursor)
    }
  }
  assert_eq(transferred_preparation.selected.length(), 1)
  let final_read = match transferred_preparation.selected[0] {
    RelationInput(value) => value
    _ => fail("expected the exact transferred producer input")
  }
  let final_metadata = transferred_metadata.unwrap()
  assert_eq(current_columns_count(final_metadata), 1)
  assert_true(
    @execution.producer_read_cell(final_read, 0, 0)
    is Some(@execution.Number(2)),
  )
  println(
    current_preparation_storage_probe(
      transferred_preparation,
      final_metadata,
      Some(final_read),
      2,
      1,
      1,
    ),
  )
  cancel_relation_chain_inputs(transferred_preparation)
  @execution.cancel_prepare_producer_read(final_metadata)
  assert_true(transferred_preparation.selected.is_empty())
  assert_eq(current_columns_count(final_metadata), 1)
  assert_true(@execution.producer_read_available(final_read))
  assert_true(
    @execution.producer_read_cell(final_read, 0, 0)
    is Some(@execution.Number(2)),
  )
  println(
    current_preparation_storage_probe(
      transferred_preparation,
      final_metadata,
      Some(final_read),
      3,
      1,
      1,
    ),
  )
}
