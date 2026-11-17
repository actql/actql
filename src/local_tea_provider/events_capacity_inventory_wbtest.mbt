///|
test "Events record quote keeps two storage generations and finite metadata" {
  let limits : @storage.Limits = {
    max_input_records: 100,
    max_records: 100,
    max_fields_per_record: 100,
    max_value_bytes: 10000,
    max_total_value_bytes: 100000,
    max_retained_value_bytes: 100000,
    max_value_nodes: 10000,
    max_value_depth: 100,
    max_contract_work: 10000,
    max_work: 100000,
    max_workspace_slots: 10000,
  }
  // Two byte quotas; two record/ref and checked-value generations; two
  // independent input-index and append packets; four bounded identity spans.
  let expected = 2L * 100000L +
    2L * 100L * 256L +
    2L * 10000L * 256L +
    2L * 10000L * 256L +
    2L * 100000L * 8L +
    2L * 10000L * 256L +
    4L * 512L * 8L +
    2L * 100L * 71L * 8L
  assert_eq(events_projection_record_workspace(limits, 100000L), Some(expected))
  assert_eq(expected, 17341184L)
  assert_eq(
    events_projection_record_workspace(
      { ..limits, max_retained_value_bytes: 100001, },
      100000L,
    ),
    Some(expected + 16L),
  )
  assert_eq(
    events_projection_record_workspace(
      { ..limits, max_workspace_slots: 10001, },
      100000L,
    ),
    Some(expected + 512L),
  )
  assert_true(events_projection_record_workspace(limits, -1L) is None)
  assert_true(
    events_projection_record_workspace(limits, 9223372036854775807L) is None,
  )
  assert_true(
    events_projection_record_workspace({ ..limits, max_input_records: -1, }, 1L)
    is None,
  )
}
