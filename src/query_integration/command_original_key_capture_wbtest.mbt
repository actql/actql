///|
fn command_key_managed_export(
  inputs : @strategy.CapturedEffectInputs,
  operations : @local_driver.LocalManagedDispatchOperations[Int],
  completed : @execution.ManagedCompletedOutput[Int],
) -> @strategy.CapturedEffectLocalResultExport {
  let bridge = @execution.prepare_managed_publication_bridge(
    completed,
    (operations.material)().unwrap(),
    100,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 20, max_work: 10000, },
    100,
    10000,
  ).unwrap()
  for row in local_managed_test_rows(operations) {
    @execution.append_managed_publication_bridge_wire(bridge, row, {
      max_bytes: 100,
      max_nodes: 20,
      max_depth: 4,
      max_text_bytes: 100,
    }).unwrap()
  }
  let output = @execution.finish_managed_publication_bridge(bridge).unwrap()
  let input = @strategy.captured_effect_input_at(inputs, 0).unwrap()
  let (preparation, _) = local_effect_export_receipt(
    output,
    @strategy.captured_effect_input_occurrence(input),
  )
  @strategy.bind_captured_effect_local_result_managed_export(
    inputs, 0, completed, bridge, preparation,
  ).unwrap()
}

///|
fn command_key_finish(
  value : @strategy.CapturedEffectCommandKeyValidation,
) -> Unit raise {
  let mut complete = false
  for _ in 0..<10000 {
    match
      @strategy.advance_captured_effect_command_key_validation(value, 1).unwrap() {
      @bounded.ContinueWith(_, ..) => ()
      @bounded.Completed(_, ..) => {
        complete = true
        break
      }
      _ => fail("whole original Command input did not complete")
    }
  }
  assert_true(complete)
  let mut clean = false
  for _ in 0..<10000 {
    if @strategy.cleanup_captured_effect_command_key_validation(value).unwrap() {
      clean = true
      break
    }
  }
  assert_true(clean)
}

///|
fn command_key_close(
  captured : @strategy.CapturedEffectRunDAG,
  inputs : @strategy.CapturedEffectInputs,
  operations : @local_driver.LocalManagedDispatchOperations[Int],
  available : Ref[Bool],
) -> Unit raise {
  @strategy.release_captured_effect_inputs(inputs) |> ignore
  available.val = false
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
  let run = @strategy.captured_effect_run_dag(captured)
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
}

///|
test "Command key proof requires original managed export completion cleanup and same captured Run" {
  let (_, captured, inputs, operations, available, completed) = published_store_capture_fixture(
    input_key=true,
  )
  let exported = command_key_managed_export(inputs, operations, completed)
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
  assert_true(
    @strategy.prepare_captured_effect_proposal_plan(
      inputs,
      0,
      2,
      100,
      published_target=Some(target),
      input_key=Some(key),
    )
    is Err(@strategy.CapturedEffectProposalIssue::NotReady),
  )
  command_key_finish(key)
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
  assert_eq(changes, "{\"id\":\"one\",\"value\":\"original\"}")
  @strategy.finish_captured_effect_proposal_plan(proposal, 1).unwrap()
  let (_, foreign, foreign_inputs, foreign_operations, foreign_available, _) = published_store_capture_fixture(
    input_key=true,
  )
  assert_true(
    @strategy.start_captured_effect_command_key_validation(
      @bounded.control(),
      foreign_inputs,
      0,
      0,
      exported,
      100,
      1000,
      10,
      100,
    )
    is Err(@strategy.CapturedEffectCommandKeyIssue::ForeignOrigin),
  )
  assert_true(
    @strategy.prepare_captured_effect_proposal_plan(
      foreign_inputs,
      0,
      2,
      100,
      input_key=Some(key),
    )
    is Err(@strategy.CapturedEffectProposalIssue::NotReady),
  )
  assert_true(
    @strategy.start_captured_effect_command_key_validation(
      @bounded.control(),
      inputs,
      1,
      0,
      exported,
      100,
      1000,
      10,
      100,
    )
    is Err(@strategy.CapturedEffectCommandKeyIssue::ForeignOrigin),
  )
  let retained = @strategy.prepare_captured_effect_proposal_plan(
    inputs,
    0,
    2,
    100,
    published_target=Some(target),
    input_key=Some(key),
  ).unwrap()
  command_key_close(captured, inputs, operations, available)
  assert_true(
    @strategy.project_captured_effect_proposal_row(
      retained, row, 0, 2, 100, 1024, 64, 8,
    )
    is Err(@strategy.CapturedEffectProposalIssue::NotReady),
  )
  command_key_close(
    foreign, foreign_inputs, foreign_operations, foreign_available,
  )
}

///|
test "Command key proof rejects the final duplicate from actual captured managed rows" {
  let (_, captured, inputs, operations, available, completed) = published_store_capture_fixture(
    input_key=true,
    rows="[{\"id\":\"one\",\"value\":\"a\"},{\"id\":\"two\",\"value\":\"b\"},{\"id\":\"one\",\"value\":\"c\"}]",
  )
  let exported = command_key_managed_export(inputs, operations, completed)
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
  let mut duplicate = false
  for _ in 0..<10000 {
    match
      @strategy.advance_captured_effect_command_key_validation(key, 1).unwrap() {
      @bounded.ContinueWith(_, ..) => ()
      @bounded.FailedWith(
        @execution.CompletedResultKeyIssue::Key(
          @execution.InputKeyIssue::DuplicateKey(0, 2)
        ),
        ..
      ) => {
        duplicate = true
        break
      }
      _ =>
        fail("duplicate Command input accepted or failed outside key assertion")
    }
  }
  assert_true(duplicate)
  while !@strategy.cleanup_captured_effect_command_key_validation(key).unwrap() {

  }
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

///|
test "Command key cleanup cancels partial captured work without releasing its original Result" {
  let (_, captured, inputs, operations, available, completed) = published_store_capture_fixture(
    input_key=true,
  )
  let exported = command_key_managed_export(inputs, operations, completed)
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
    @strategy.advance_captured_effect_command_key_validation(key, 1).unwrap()
    is @bounded.ContinueWith(_, ..),
  )
  while !@strategy.cleanup_captured_effect_command_key_validation(key).unwrap() {

  }
  assert_true(
    @strategy.captured_effect_local_result_export_retained(inputs, exported),
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
