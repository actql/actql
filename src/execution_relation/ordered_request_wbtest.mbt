///|
test "ordered request embeds exact same-step limits and retains source rather than machine params" {
  let sequence = prepared_sequence(
    row_owner(",{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"}]}"),
  )
  let context = execution_for(sequence, 10000L).contexts[0]
  let pipeline = @lower.prepare_fragment_pipeline(sequence, 1, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  let request = @lower.prepare_fragment_request(
    pipeline,
    10L,
    1000L,
    row_limits=Some(context.limits),
  ).unwrap()
  let artifact = prepare_request_artifact(request, 10000, 1000, 100).unwrap()
  let text = @identity.stringify_value(
    artifact.artifact.value,
    10000,
    1000,
    100,
  )
  let node = prepare_ordered_node_artifact(context.params, registry_limits()).unwrap()
  assert_true(
    text.contains(
      @identity.stringify_value(node.source.value, 10000, 1000, 100),
    ),
  )
  assert_false(text.contains("row_kernel_contract_cid"))
  assert_false(text.contains("references"))
  assert_true(text.contains("\"row_kernel_limits\":{\"derive_1\":"))
  assert_true(text.contains(context.cid))
  assert_true(
    prepare_request_artifact(request, artifact.artifact.bytes, 1000, 100)
    is Ok(_),
  )
  assert_true(
    prepare_request_artifact(request, artifact.artifact.bytes - 1, 1000, 100)
    is Err(OutputLimit),
  )
  assert_true(
    @lower.prepare_fragment_request(pipeline, 10L, 1000L)
    is Err(@lower.RowLimitsMismatch),
  )
  assert_true(
    @lower.prepare_fragment_request(
      pipeline,
      10L,
      1000L,
      row_limits=Some({ ..context.limits, max_work: -1L, }),
    )
    is Err(@lower.InvalidRowLimits),
  )
  assert_true(
    @lower.prepare_fragment_request(
      pipeline,
      10L,
      1000L,
      row_limits=Some({ ..context.limits, max_input_rows: 11L, }),
    )
    is Err(@lower.InvalidRequestCeiling),
  )
  let map = prepared_sequence(row_owner(",{\"derive\":{\"x\":\"a\"}}"))
  let map_pipeline = @lower.prepare_fragment_pipeline(map, 1, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  assert_true(
    @lower.prepare_fragment_request(
      map_pipeline,
      10L,
      1000L,
      row_limits=Some(context.limits),
    )
    is Err(@lower.RowLimitsMismatch),
  )
}
