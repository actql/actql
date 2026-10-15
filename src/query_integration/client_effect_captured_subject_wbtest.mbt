///|
// Existing Compiler/admission/Values runtime only. The allow evidence uses
// explicit fixture Host metadata, not production authorization or a new Owner.
fn captured_subject_compile_allowed(
  prepared : @publication_host.PreparedClientEffectComputation,
) -> (
  @publication_host.ClientEffectAllowedRun,
  @publication.PublicationContract,
  @publication.RunEvidenceValue,
) {
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let compiled = @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = @publication_host.issue_client_effect_allowed_run(
    compiled,
    native_publication_cid("captured-subject-fixture-execution-context"),
    native_publication_cid("captured-subject-fixture-host-policy"),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_effect_run_definition(
    allowed, "scope", "local-effect-export", "2026-09-25T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  (
    allowed,
    definition,
    @publication_host.client_effect_compilation_template(compiled),
  )
}

///|
fn captured_subject_compiled_run(
  prepared : @publication_host.PreparedClientEffectComputation,
) -> (
  @publication_host.ClientEffectAllowedRun,
  @publication.PublicationContract,
  @publication.RunEvidenceValue,
  @strategy.CapturedEffectRunDAG,
) {
  let (allowed, definition, template) = captured_subject_compile_allowed(
    prepared,
  )
  let bound = @publication_host.bind_client_effect_compiled_run(
    prepared, allowed, definition,
  ).unwrap()
  let captured = @publication_host.open_prepared_source_free_client_effect_run(
    bound,
    {
      planning_work: 100000,
      attempts: 10,
      holdings: 10,
      transfer_bytes: 500000L,
      retained_bytes: 200000000L,
      execution_bytes: 268435456L,
    },
  ).unwrap()
  (allowed, definition, template, captured)
}

///|
fn captured_subject_checkpoint(
  definition : @publication.PublicationContract,
) -> @checkpoint.SealedCheckpoint {
  @checkpoint.seal_checkpoint(
    {
      checkpoint_id: "captured-subject-metadata-only",
      continuation_state_cid: native_publication_cid(
        "fixture-continuation-metadata",
      ),
      subject: @checkpoint.RunUnit(
        run_id="local-effect-export",
        unit_id="source",
        run_definition_cid=@publication.publication_contract_identity(
          definition,
        ),
      ),
      phase: @checkpoint.Commit,
      kind: @checkpoint.EffectSet,
      required_artifact_cid: native_publication_cid(
        "fixture-checkpoint-artifact-metadata",
      ),
      review_projection_cid: native_publication_cid(
        "fixture-checkpoint-review-metadata",
      ),
      requirements: [@checkpoint.EffectScopeApproved],
      reason_code: "effect_review",
      human_summary: "Original capture identity metadata fixture only",
      created_at: "2026-09-25T00:01:00.000Z",
      expires_at: "2026-09-25T00:02:00.000Z",
    },
    { max_wire_bytes: 65536, max_nodes: 4096, max_depth: 64, },
  ).unwrap()
}

///|
// The managed Values output/pins/Preview are real. The Checkpoint is sealed
// nominal metadata, not a persisted paired waiting transition or signing gate.
fn check_captured_subject_original(
  allowed : @publication_host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  prepared : @publication_host.PreparedClientEffectComputation,
  preview : @strategy.CapturedEffectPreviewInputs,
  invocation : @publication.PublicationContract,
) -> @publication_host.ClientCapturedEffectSubjectRead {
  let checkpoint = captured_subject_checkpoint(definition)
  let original_checked = @program_check.effect_program_static_checked_computation(
    @publication_host.prepared_client_effect_computation_candidate(prepared),
  )
  let expected_unit = @program_check.unit_definition_cid(original_checked, 0).unwrap()
  let expected_invocation = @publication.publication_contract_identity(
    invocation,
  )
  let read = @publication_host.read_client_captured_effect_subject(
    allowed, definition, preview, checkpoint,
  ).unwrap()
  assert_eq(
    read.original_subject_after_current().unwrap(),
    (expected_invocation, expected_unit),
  )
  // Even an equal-body Run Definition cannot replace this actual compiled
  // admission: another issuance has its own nominal admission/compilation.
  let (other_allowed, other_definition, _) = captured_subject_compile_allowed(
    prepared,
  )
  assert_eq(
    @publication.publication_contract_json(other_definition),
    @publication.publication_contract_json(definition),
  )
  assert_true(
    @publication_host.read_client_captured_effect_subject(
      other_allowed, other_definition, preview, checkpoint,
    )
    is Err(@publication_host.ForeignSubject),
  )
  for
    subject in [
      @checkpoint.RunUnit(
        run_id="foreign-run",
        unit_id="source",
        run_definition_cid=@publication.publication_contract_identity(
          definition,
        ),
      ),
      @checkpoint.RunUnit(
        run_id="local-effect-export",
        unit_id="foreign-unit",
        run_definition_cid=@publication.publication_contract_identity(
          definition,
        ),
      ),
      @checkpoint.RunUnit(
        run_id="local-effect-export",
        unit_id="source",
        run_definition_cid=native_publication_cid("foreign-run-definition"),
      ),
    ] {
    let foreign = @checkpoint.seal_checkpoint(
      { ..checkpoint.checkpoint, subject, },
      { max_wire_bytes: 65536, max_nodes: 4096, max_depth: 64, },
    ).unwrap()
    assert_true(
      @publication_host.read_client_captured_effect_subject(
        allowed, definition, preview, foreign,
      )
      is Err(@publication_host.ForeignSubject),
    )
  }
  read
}

///|
test "captured Effect subject reads original Invocation and explicit unit then rejects post-current pin retirement" {
  verify_captured_private_table_input(false, original_subject=true)
}

///|
test "empty captured Effect subject preserves the same original identity and terminal lifetime fence" {
  verify_captured_private_table_input(true, original_subject=true)
}
