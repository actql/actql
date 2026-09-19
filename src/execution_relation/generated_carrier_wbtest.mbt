///|
test "generated preparation retains Carrier steps without executing them" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"event_id\":{\"type\":\"number\",\"nullable\":false},\"occurred_at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"event_id\":1,\"occurred_at\":2}]},\"as\":\"seed\"},{\"from\":\"seed\",\"to_events\":{\"id\":\"event_id\",\"time\":\"occurred_at\"}},{\"watermark_events\":{\"watermark_ms\":1,\"policy\":\"mark\"}},{\"events\":true}]",
  )
  let sequence = prepared_sequence(owner)
  let last = @lower.node_at(
    @lower.bound_preparation(owner),
    @lower.sequence_count(sequence) - 1,
  ).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    [@lower.node_id(last)],
    10000,
    1000,
  ).unwrap()
  assert_true(physical_equal(generated_sequence_owner(generated), owner))
  assert_false(generated_sequence_is_projection_only(generated))
  assert_true(
    execute_generated_sequence(generated, [], {
      rows: run_limits(),
      max_work: 10000,
      max_frames: 100,
    })
    is Err(InputSet),
  )
}
