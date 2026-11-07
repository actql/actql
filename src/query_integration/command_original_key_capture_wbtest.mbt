///|
fn command_key_managed_export_with_bridge(
  inputs : @strategy.CapturedEffectInputs,
  operations : @local_driver.LocalManagedDispatchOperations[Int],
  completed : @execution.ManagedCompletedOutput[Int],
) -> (
  @strategy.CapturedEffectLocalResultExport,
  @execution.ManagedPublicationBridge[Int],
) {
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
  let exported = @strategy.bind_captured_effect_local_result_managed_export(
    inputs, 0, completed, bridge, preparation,
  ).unwrap()
  (exported, bridge)
}

///|
fn command_key_managed_export(
  inputs : @strategy.CapturedEffectInputs,
  operations : @local_driver.LocalManagedDispatchOperations[Int],
  completed : @execution.ManagedCompletedOutput[Int],
) -> @strategy.CapturedEffectLocalResultExport {
  command_key_managed_export_with_bridge(inputs, operations, completed).0
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
/// A shape-admitted private Preview isolates the same Run's payload verifier.
/// Placeholder authority/artifact fields do not establish apply authority or
/// installed acceptance; the original managed input is independently pinned.
fn command_key_preview(
  prepared : @publication_host.PreparedClientEffectComputation,
  captured : @strategy.CapturedEffectRunDAG,
  inputs : @strategy.CapturedEffectInputs,
  template : @publication.RunEvidenceValue,
  selector : String,
) -> @strategy.CapturedEffectPreviewInputs raise {
  let owner = @strategy.captured_effect_run_owner(captured)
  let definition = @publication_host.prepared_client_effect_computation_definition_cid(
    prepared,
  )
  let run = @publication.publication_contract_identity(
    @effect_binding.effect_program_run_definition(owner),
  )
  let (_, invocation, _) = private_table_artifact_context(template)
  let authoring = native_publication_cid(
    "{\"annotations\":[],\"program_definition_cid\":\"" +
    definition +
    "\",\"version\":\"actql-authoring-context/0.1\"}",
  )
  let raw =
    #|{"version":"actql-effect-preview/0.1","sensitivity":"private","retention_class":"authority-evidence","encryption_required":true,"program_semantics_cid":"@SEM@","program_definition_cid":"@DEF@","invocation_cid":"@INV@","run_identity_cid":"@RUN@","compiled_plan_cid":"@PLAN@","check_environment_cid":"@ENV@","authoring_context":{"version":"actql-authoring-context/0.1","program_definition_cid":"@DEF@","annotations":[],"authoring_context_cid":"@AUTHOR@"},"barrier_provenance_cids":[],"model_derived":false,"model_task_contract_cids":[],"model_invocation_evidence_cids":[],"model_response_artifact_cids":[],"effects":[{"effect_id":"save","effect_kind":"command","target":"Object","contract":"command:fixture.upload.v1","resolved_command_contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","source_result":"out","result_artifact_cid":"@P@","effect_identity_cid":"@P@","preview_strength":"full_diff","source_binding_cid":"@P@","capability_evidence_cid":"@P@","authority_scope_cid":"@P@","write_footprint":{"kind":"exact_targets","resource_identity_scheme_cid":"@P@","provider_namespace":"fixture","provider_boundary_cid":"@P@","resource_kind":"Object","provider_object_identity_cids":[]},"count":1,"max_items":1,"required_permissions":["scope:write"],"on_item_failure":"halt","changes":[{"after":{"state":"not_applicable"},"before":{"state":"not_applicable"},"intended_changes":{"state":"present","value":{"id":"one","value":"original"}},"row_idempotency_key":"@P@","row_preview_cid":"@P@","target_guard":{"state":"not_applicable"},"target_row_identity":@SELECTOR@}],"row_order":["@P@"],"effect_member_preview_cid":"@P@","executed":false}],"executed":false,"effect_preview_cid":"@P@"}
  let raw = raw
    .replace_all(
      old="@SEM@",
      new=@publication_host.prepared_client_effect_computation_semantics_cid(
        prepared,
      ),
    )
    .replace_all(old="@DEF@", new=definition)
    .replace_all(
      old="@INV@",
      new=@publication.publication_contract_identity(invocation),
    )
    .replace_all(old="@RUN@", new=run)
    .replace_all(
      old="@PLAN@",
      new=@publication.run_publication_compiled_plan_cid(
        @effect_binding.effect_program_run_admission(owner),
      ),
    )
    .replace_all(
      old="@ENV@",
      new=@publication_host.prepared_client_effect_computation_environment_cid(
        prepared,
      ),
    )
    .replace_all(old="@AUTHOR@", new=authoring)
    .replace_all(
      old="@P@",
      new=native_publication_cid("command-key-preview-placeholder"),
    )
    .replace_all(old="@SELECTOR@", new=selector)
  let canonical = match
    @publication.canonical_effect_preview_draft_wire(raw, 65536, 4096, 32) {
    Ok(value) => value
    Err(issue) => fail("Command key Preview shape: " + @debug.to_string(issue))
  }
  let (_, preview) = match
    @publication.author_effect_preview_semantic_wire(
      canonical, run, authoring, 65536, 4096, 32,
    ) {
    Ok(value) => value
    Err(issue) =>
      fail("Command key Preview identity: " + @debug.to_string(issue))
  }
  let bound = @effect_binding.bind_effect_program_run_preview(
    owner,
    invocation,
    0,
    preview,
    10000,
    {
      max_fields: 10,
      max_work: 10000,
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 32,
    },
  ).unwrap()
  @strategy.bind_captured_effect_preview_inputs(captured, inputs, bound, 10000).unwrap()
}

///|
test "Command Preview payload proof requires the same completed whole-input key validation" {
  let (prepared, captured, inputs, operations, available, completed, template) = published_store_capture_with_completion(
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
  let reference = published_store_capture_reference(Ref(true))
  guard reference.value is @admitted.Reference(original) else {
    fail("original Reference")
  }
  let target = @strategy.bind_captured_effect_command_target(
    inputs, 0, pair, reference, 100,
  ).unwrap()
  let preview = command_key_preview(
    prepared,
    captured,
    inputs,
    template,
    @admitted.reference_wire(original),
  )
  assert_true(
    @strategy.prepare_captured_effect_plan_verifier(
      preview,
      0,
      2,
      100,
      published_target=Some(target),
    )
    is Err(@strategy.CapturedEffectPlanVerifyIssue::NotReady),
  )
  assert_true(
    @strategy.prepare_captured_effect_plan_verifier(
      preview,
      0,
      2,
      100,
      published_target=Some(target),
      input_key=Some(key),
    )
    is Err(@strategy.CapturedEffectPlanVerifyIssue::NotReady),
  )
  command_key_finish(key)
  let verifier = @strategy.prepare_captured_effect_plan_verifier(
    preview,
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
  @strategy.check_captured_effect_plan_row(
    verifier, row, 0, 2, 100, 1024, 64, 8,
  ).unwrap()
  let proof = @strategy.finish_captured_effect_plan_verifier(verifier).unwrap()
  assert_true(@strategy.captured_effect_plan_proof_matches(proof, preview, 0))
  @strategy.check_captured_effect_plan_proofs(preview, [proof], 1, 100).unwrap()
  command_key_close(captured, inputs, operations, available)
  assert_false(@strategy.captured_effect_plan_proof_matches(proof, preview, 0))
}

///|
test "Command key proof requires original managed export completion cleanup and same captured Run" {
  let (_, captured, inputs, operations, available, completed, _) = published_store_capture_with_completion(
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
  assert_eq(
    changes, "{\"state\":\"present\",\"value\":{\"id\":\"one\",\"value\":\"original\"}}",
  )
  @strategy.finish_captured_effect_proposal_plan(proposal, 1).unwrap()
  let (_, foreign, foreign_inputs, foreign_operations, foreign_available, _, _) = published_store_capture_with_completion(
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
  let (_, captured, inputs, operations, available, completed, _) = published_store_capture_with_completion(
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
  let (_, captured, inputs, operations, available, completed, _) = published_store_capture_with_completion(
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
