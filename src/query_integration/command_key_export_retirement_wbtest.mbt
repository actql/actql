///|
test "original Command correspondence transfers once after whole-input cleanup before derived view closes" {
  let (prepared, captured, inputs, operations, available, completed, template) = published_store_capture_with_completion(
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
  let (selector, changes) = @strategy.project_captured_effect_proposal_row(
    proposal, row, 0, 2, 100, 1024, 64, 8,
  ).unwrap()
  assert_eq(
    changes, "{\"state\":\"present\",\"value\":{\"id\":\"one\",\"value\":\"original\"}}",
  )
  @strategy.finish_captured_effect_proposal_plan(proposal, 1).unwrap()
  let preview = command_key_preview(
    prepared, captured, inputs, template, selector,
  )
  let verifier = @strategy.prepare_captured_effect_plan_verifier(
    preview,
    0,
    2,
    100,
    published_target=Some(target),
    input_key=Some(key),
  ).unwrap()
  @strategy.check_captured_effect_plan_row(
    verifier, row, 0, 2, 100, 1024, 64, 8,
  ).unwrap()
  let proof = @strategy.finish_captured_effect_plan_verifier(verifier).unwrap()
  assert_true(@strategy.captured_effect_plan_proof_matches(proof, preview, 0))
  command_key_close(captured, inputs, operations, available)
  assert_false(@strategy.captured_effect_plan_proof_matches(proof, preview, 0))
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
test "Host key continuation completes whole traversal and private cleanup before retaining correspondence" {
  let (_, captured, inputs, operations, available, completed, _) = published_store_capture_with_completion(
    input_key=true,
  )
  let (exported, bridge) = command_key_managed_export_with_bridge(
    inputs, operations, completed,
  )
  assert_true(
    @strategy.captured_effect_command_requires_input_key(inputs, 0, 100).unwrap(),
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
    @strategy.step_captured_effect_command_key_validation(key, 0)
    is Err(
      @strategy.CapturedEffectCommandKeyIssue::Control(@bounded.InvalidQuantum)
    ),
  )
  let mut done = false
  for _ in 0..<10000 {
    let (finished, used) = @strategy.step_captured_effect_command_key_validation(
      key, 1,
    ).unwrap()
    assert_true(used > 0)
    if finished {
      done = true
      break
    }
  }
  assert_true(done)
  @execution.close_managed_publication_bridge(bridge)
  assert_true(
    @strategy.step_captured_effect_command_key_validation(key, 1)
    is Ok((true, 0)),
  )
  available.val = false
  assert_true(
    @strategy.step_captured_effect_command_key_validation(key, 1)
    is Err(@strategy.CapturedEffectCommandKeyIssue::ForeignOrigin),
  )
  command_key_close(captured, inputs, operations, available)
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
