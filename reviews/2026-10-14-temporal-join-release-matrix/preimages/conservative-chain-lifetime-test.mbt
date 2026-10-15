test "unaudited chain steps keep conservative capacity and child custody" {
  let (sequence, read, source) = chain_lifetime_fixture(
    "[{\"from\":\"source\",\"select\":[\"id\"],\"as\":\"first\"},{\"from\":\"first\",\"intersect\":{\"with\":\"first\",\"duplicates\":\"all\"},\"as\":\"out\"}]",
  )
  assert_false(relation_chain_reclaims_completed_scratch(sequence))
  let limits = chain_lifetime_limits()
  let measure = chain_lifetime_measurement()
  let capacity = bounded_relation_chain_capacity(sequence, limits, measure, []).unwrap()
  let count = @execution.generated_sequence_step_count(sequence)
  // Existing parent handles plus the two fixed metadata preparation handles.
  let mut overlap = count.to_int64() * 256L + 512L
  for index in 0..<count {
    let step = @execution.generated_sequence_step_index_at(sequence, index).unwrap()
    let selected = @execution.select_generated_sequence_step(sequence, step).unwrap()
    let child = @execution.generated_sequence_capacity(
      selected, limits, measure,
    ).unwrap()
    overlap += child.retained_bytes + child.execution_bytes
  }
  assert_eq(capacity.execution_bytes, overlap)
  let (active, state) = chain_lifetime_start(sequence, read)
  let mut result = None
  for _ in 0..<100000 {
    if result is Some(_) {
      break
    }
    match advance_managed_provider(active, 1).unwrap() {
      Continue(..) => ()
      Complete(output, ..) => result = Some(output)
      _ => fail("conservative set chain did not complete")
    }
    if state.pending {
      assert_eq(state.children.length(), state.position)
      assert_false(state.reclaiming)
    }
  }
  assert_eq(@execution.completed_row_count(result.unwrap()), 3)
  assert_eq(state.children.length(), count)
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_true(state.children.is_empty())
  assert_true(@execution.completed_output_available(source))
}
