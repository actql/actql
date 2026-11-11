///|
test "failed chain forwards only the same stopped Cross Join cleanup cursor" {
  let (sequence, read, source) = chain_lifetime_fixture(
    "[{\"from\":\"source\",\"cross_join\":{\"with\":\"source\",\"select\":{\"id\":\"left.id\"}},\"as\":\"pairs\"}," +
    "{\"from\":\"pairs\",\"cross_join\":{\"with\":\"source\",\"select\":{\"id\":\"left.id\"}},\"as\":\"triples\"}," +
    "{\"from\":\"triples\",\"cross_join\":{\"with\":\"source\",\"select\":{\"id\":\"left.id\"}},\"as\":\"quads\"}," +
    "{\"from\":\"quads\",\"select\":[\"id\"]}]",
  )
  let base = chain_lifetime_limits()
  let limits = {
    ..base,
    rows: {
      ..base.rows,
      output_values: { ..base.rows.output_values, max_nodes: 100, },
    },
  }
  let (active, state) = bounded_relation_chain_execution_state(
    sequence,
    [managed_provider_relation_input(read)],
    limits,
    chain_lifetime_measurement(),
    10000,
    None,
    [],
  ).unwrap()
  assert_eq(managed_provider_cleanup_continuation(active), -1L)
  let failed = Ref(false)
  for _ in 0..<100000 {
    match advance_managed_provider(active, 1).unwrap() {
      Continue(..) | Waiting(..) => ()
      Failed(
        @connector.Execution(@execution.Capture(2, @execution.CaptureLimit)),
        ..
      ) => {
        failed.val = true
        break
      }
      _ => fail("the third original Cross Join must retain CaptureLimit")
    }
  }
  assert_true(failed.val)
  assert_true(managed_provider_stopped(active))
  let work = managed_provider_cumulative_work(active).unwrap()
  assert_false(cleanup_managed_provider(active).unwrap())
  let cursor = managed_provider_cleanup_continuation(active)
  assert_eq(cursor, 64L)
  assert_true(state.current is Some(_))
  let mut reclaimed = false
  for _ in 0..<10 {
    if cleanup_managed_provider(active).unwrap() {
      reclaimed = true
      break
    }
    assert_true(managed_provider_cleanup_continuation(active) > cursor)
  }
  assert_true(reclaimed)
  assert_true(state.children.is_empty())
  assert_eq(managed_provider_cleanup_continuation(active), -1L)
  assert_eq(managed_provider_cumulative_work(active).unwrap(), work)
  assert_true(@execution.completed_output_available(source))
  // Family providers without this actual local cursor remain blocked even
  // after an independently confirmed stop; no retry or ACK is invented.
  let unknown = managed_provider_execution(
    _ => Err(@connector.InvalidLimits),
    () => false,
    () => true,
    () => Ok(false),
  )
  assert_eq(managed_provider_cleanup_continuation(unknown), -1L)
}
