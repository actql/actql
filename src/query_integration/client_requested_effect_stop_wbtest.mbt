///|
// Actual checked/compiled/captured Values and Table-input owners. The public
// epoch token below is shape DATA only, not authenticated journal admission.
// These tests issue no persisted wait, approval, physical write or send grant.
fn check_requested_effect_stop_projection(
  document : String,
  prepared : @publication_host.PreparedClientEffectComputation,
  allowed : @publication_host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  preview : @strategy.CapturedEffectPreviewInputs,
) -> (
  @publication_host.ClientRequestedEffectStop,
  @checkpoint.CheckpointRequest,
  String,
) raise {
  let token = @publication_host.admit_client_submission_epoch_token(
    "{\"authenticator\":\"" +
    "c".repeat(64) +
    "\",\"authorityScopeCid\":\"sha256:" +
    "b".repeat(64) +
    "\",\"epochNonce\":\"" +
    "b".repeat(64) +
    "\",\"expiresAt\":2000,\"notBefore\":1000,\"version\":\"actql-submission-epoch/0.1\"}",
  ).unwrap()
  let reference = @publication_host.prepare_client_submission_reference_record(
    token, "requested-stop-original",
  ).unwrap()
  let request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    @publication_host.client_submission_epoch_token_authority_scope_cid(token),
    @publication_host.client_submission_reference_record_request_id(reference),
    @publication_host.source_free_caller_input_intent_cid(),
  ).unwrap()
  let plain = "{\"kind\":\"program\",\"input\":" +
    document +
    ",\"parameters\":null}"
  let unselected = @publication_host.prepare_client_submitted_intent(
    plain, 65536, 4096, 64,
  ).unwrap()
  assert_true(
    @publication_host.issue_client_requested_effect_stop(
      unselected, reference, request, allowed, definition, preview,
    )
    is Ok(None),
  )
  let intent = @publication_host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    document +
    ",\"parameters\":null,\"stopBefore\":\"commit\"}",
    65536,
    4096,
    64,
  ).unwrap()
  let original = @publication_host.issue_client_requested_effect_stop(
      intent, reference, request, allowed, definition, preview,
    )
    .unwrap()
    .unwrap()
  assert_eq(
    @publication_host.client_requested_effect_stop_intent_cid(original),
    @publication_host.client_submitted_intent_cid(intent),
  )
  assert_eq(
    @publication_host.client_requested_effect_stop_lifetime(original).unwrap(),
    @publication.run_definition_lifetime(definition).unwrap(),
  )
  let foreign_reference = @publication_host.prepare_client_submission_reference_record(
    token, "another-original",
  ).unwrap()
  assert_true(
    @publication_host.issue_client_requested_effect_stop(
      intent, foreign_reference, request, allowed, definition, preview,
    )
    is Err(@publication_host.ForeignRequest),
  )
  // An equal-body compiled Run is a different nominal admission. It may not
  // borrow the original capture even when its definition bytes happen to match.
  let (other, other_definition, _) = captured_subject_compile_allowed(prepared)
  assert_eq(
    @publication.publication_contract_json(other_definition),
    @publication.publication_contract_json(definition),
  )
  assert_true(
    @publication_host.issue_client_requested_effect_stop(
      intent, reference, request, other, other_definition, preview,
    )
    is Err(@publication_host.ForeignPreview),
  )
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 64,
  }
  let continuation = @publication_host.issue_client_requested_effect_stop_continuation(
    original,
    "{\"opaque_provider_data\":\"unchanged\"}",
    None,
    limits,
  ).unwrap()
  let actual_preview = @strategy.captured_effect_preview_owner(preview)
  let materials : @publication_host.ClientEffectRunMaterials = {
    normalization: None,
    prepared,
    compilation: allowed.compilation,
    allowed,
    run_definition: definition,
    request: Some(request),
  }
  let restored = @publication_host.restore_client_requested_effect_stop(
      intent,
      reference,
      request,
      materials,
      @effect_binding.effect_program_run_preview_invocation(actual_preview),
      @effect_binding.effect_program_run_preview_identity(actual_preview),
      {
        max_work: 10000,
        max_wire_bytes: 65536,
        max_nodes: 4096,
        max_depth: 64,
        plan: {
          max_work: 10000,
          max_fields: 100,
          max_bytes: 65536,
          max_nodes: 4096,
          max_depth: 64,
        },
      },
    )
    .unwrap()
    .unwrap()
  assert_eq(
    @publication_host.issue_client_requested_effect_stop_continuation(
      restored,
      "{\"opaque_provider_data\":\"unchanged\"}",
      None,
      limits,
    ).unwrap(),
    continuation,
  )
  assert_true(
    @publication_host.restore_client_requested_effect_stop(
      intent,
      foreign_reference,
      request,
      materials,
      @effect_binding.effect_program_run_preview_invocation(actual_preview),
      @effect_binding.effect_program_run_preview_identity(actual_preview),
      {
        max_work: 10000,
        max_wire_bytes: 65536,
        max_nodes: 4096,
        max_depth: 64,
        plan: {
          max_work: 10000,
          max_fields: 100,
          max_bytes: 65536,
          max_nodes: 4096,
          max_depth: 64,
        },
      },
    )
    is Err(@publication_host.ForeignRequest),
  )
  let previous = captured_subject_checkpoint(definition)
  let body : @checkpoint.CheckpointRequest = {
    ..previous.checkpoint,
    continuation_state_cid: native_publication_cid(continuation),
    required_artifact_cid: @strategy.captured_effect_preview_subject_cid(
      preview,
    ).unwrap(),
    reason_code: "user_requested_stop",
  }
  let artifact = @publication_host.seal_client_requested_effect_stop(
    original, body, continuation, limits,
  ).unwrap()
  assert_eq(artifact.checkpoint.subject, body.subject)
  assert_eq(artifact.checkpoint.requirements, [@checkpoint.EffectScopeApproved])
  assert_true(
    @publication_host.seal_client_requested_effect_stop(
      original,
      {
        ..body,
        required_artifact_cid: native_publication_cid("different-preview"),
      },
      continuation,
      limits,
    )
    is Err(@publication_host.ForeignPreview),
  )
  assert_true(
    @publication_host.seal_client_requested_effect_stop(
      original,
      { ..body, reason_code: "delegated_decision_deferred", },
      continuation,
      limits,
    )
    is Err(@publication_host.ForeignRun),
  )
  for
    foreign in [
      " " + continuation,
      continuation.replace(old="\"requested_stop\"", new="\"substitute\""),
      continuation.replace(
        old=@publication_host.client_submitted_intent_cid(intent),
        new=native_publication_cid("another-submitted-intent"),
      ),
    ] {
    assert_true(
      @publication_host.seal_client_requested_effect_stop(
        original,
        { ..body, continuation_state_cid: native_publication_cid(foreign), },
        foreign,
        limits,
      )
      is Err(@publication_host.ForeignContinuation),
    )
  }
  assert_true(
    @publication_host.seal_client_requested_effect_stop(
      original,
      {
        ..body,
        continuation_state_cid: native_publication_cid("different-continuation"),
      },
      continuation,
      limits,
    )
    is Err(@publication_host.ForeignContinuation),
  )
  (original, body, continuation)
}

///|
test "requested Effect stop binds the original Run Preview and refuses retired capture" {
  verify_captured_private_table_input(
    false,
    original_subject=true,
    requested_stop=true,
  )
}
