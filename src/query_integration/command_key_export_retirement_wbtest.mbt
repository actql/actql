///|
test "original Command correspondence transfers once after whole-input cleanup before derived view closes" {
  let (_, captured, inputs, operations, available, completed, _) = published_store_capture_with_completion(
    input_key=true,
  )
  let (exported, bridge) = command_key_managed_export_with_bridge(
    inputs, operations, completed,
  )
  let key = @strategy.start_captured_effect_command_key_validation(
    @bounded.control(),
    inputs,
    0,
    0,
    exported,
    100,
    1000,
    10,
    100,
  ).unwrap()
  assert_true(
    @strategy.retain_captured_effect_command_key_validation(key)
    is Err(@strategy.CapturedEffectCommandKeyIssue::ForeignOrigin),
  )
  command_key_finish(key)
  @strategy.retain_captured_effect_command_key_validation(key).unwrap()
  assert_true(
    @strategy.retain_captured_effect_command_key_validation(key)
    is Err(@strategy.CapturedEffectCommandKeyIssue::ForeignOrigin),
  )
  @execution.close_managed_publication_bridge(bridge)
  assert_true(
    @strategy.captured_effect_local_result_export_retained(inputs, exported),
  )
  let pair = @strategy.captured_effect_published_store_binding(inputs, 0, 100)
    .unwrap()
    .unwrap()
  let target = @strategy.bind_captured_effect_command_target(
    inputs,
    0,
    pair,
    published_store_capture_reference(Ref(true)),
    100,
  ).unwrap()
  let proposal = @strategy.prepare_captured_effect_proposal_plan(
    inputs,
    0,
    2,
    100,
    published_target=Some(target),
    input_key=Some(key),
  ).unwrap()
  let row = @identity.from_source(
    @source.parse_json(local_managed_test_rows(operations)[0], {
      max_input_bytes: 1024,
      max_nodes: 64,
      max_depth: 8,
    }).unwrap(),
    64,
    8,
    1024,
  )
  let (_, changes) = @strategy.project_captured_effect_proposal_row(
    proposal, row, 0, 2, 100, 1024, 64, 8,
  ).unwrap()
  assert_eq(
    changes, "{\"state\":\"present\",\"value\":{\"id\":\"one\",\"value\":\"original\"}}",
  )
  @strategy.finish_captured_effect_proposal_plan(proposal, 1).unwrap()
  command_key_close(captured, inputs, operations, available)
  assert_true(
    @strategy.prepare_captured_effect_proposal_plan(
      inputs,
      0,
      2,
      100,
      published_target=Some(target),
      input_key=Some(key),
    )
    is Err(@strategy.CapturedEffectProposalIssue::InvalidMember),
  )
}

///|
test "closed temporary export cannot initiate original Command correspondence transfer" {
  let (_, captured, inputs, operations, available, completed, _) = published_store_capture_with_completion(
    input_key=true,
  )
  let (exported, bridge) = command_key_managed_export_with_bridge(
    inputs, operations, completed,
  )
  let key = @strategy.start_captured_effect_command_key_validation(
    @bounded.control(),
    inputs,
    0,
    0,
    exported,
    100,
    1000,
    10,
    100,
  ).unwrap()
  command_key_finish(key)
  @execution.close_managed_publication_bridge(bridge)
  assert_true(
    @strategy.captured_effect_local_result_export_retained(inputs, exported),
  )
  assert_true(
    @strategy.retain_captured_effect_command_key_validation(key)
    is Err(@strategy.CapturedEffectCommandKeyIssue::ForeignOrigin),
  )
  assert_true(
    @strategy.prepare_captured_effect_proposal_plan(
      inputs,
      0,
      2,
      100,
      input_key=Some(key),
    )
    is Err(@strategy.CapturedEffectProposalIssue::NotReady),
  )
  command_key_close(captured, inputs, operations, available)
}
