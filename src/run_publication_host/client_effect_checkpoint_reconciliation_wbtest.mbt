///|
// Pure protocol DATA plus the real checked compiler/Run originals. No actual
// Journal, provider outcome, Account, physical stop or publication is issued.
struct CheckpointReconciliationFixture {
  allowed : ClientEffectAllowedRun
  definition : @publication.PublicationContract
  checkpoint : @checkpoint.SealedCheckpoint
  preview_wire : String
  invocation_wire : String
  set_wire : String
  members : Array[String]
}

///|
fn checkpoint_reconciliation_limits() -> @checkpoint.WireLimits {
  { max_wire_bytes: 1048576, max_nodes: 65536, max_depth: 64, }
}

///|
fn checkpoint_reconciliation_fixture(
  unknown? : Bool = true,
) -> CheckpointReconciliationFixture {
  let (allowed, definition, body) = checkpoint_binding_fixture()
  let owner = allowed.compilation.owner
  let (_, invocation) = issue_client_effect_source_free_invocation(
    allowed.compilation,
    "sha256:" + "4".repeat(64),
    100000,
    10000,
    100,
  ).unwrap()
  let authoring = issue_prepared_client_authoring_context(
    client_effect_program_view(owner),
    100000,
    10000,
    100,
  ).unwrap()
  let template =
    #|{"authoring_context":"AUTHORING","barrier_provenance_cids":[],"check_environment_cid":"ENVIRONMENT","compiled_plan_cid":"PLAN","effect_preview_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","effects":[{"approval":"none","authority_scope_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","capability_evidence_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","changes":[{"after":{"state":"present","value":{"Name":"After"}},"before":{"state":"present","value":{"Name":"Before"}},"intended_changes":{"state":"present","value":{"Name":"After"}},"row_idempotency_key":"sha256:4444444444444444444444444444444444444444444444444444444444444444","row_preview_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","target_guard":{"state":"version","version_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"target_row_identity":"row-1"}],"count":1,"effect_id":"save","effect_identity_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","effect_kind":"update","effect_member_preview_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","executed":false,"mapping":"mapping:fixture","max_items":1,"on_item_failure":"halt","preview_strength":"full_diff","required_permissions":["write"],"resolved_mapping_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","row_order":["sha256:3333333333333333333333333333333333333333333333333333333333333333"],"source_binding_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","target":"Object","write_footprint":{"kind":"exact_targets","provider_boundary_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","provider_namespace":"provider","provider_object_identity_cids":["sha256:1111111111111111111111111111111111111111111111111111111111111111"],"resource_identity_scheme_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","resource_kind":"Object"}}],"encryption_required":true,"executed":false,"invocation_cid":"INVOCATION","model_derived":false,"model_invocation_evidence_cids":[],"model_response_artifact_cids":[],"model_task_contract_cids":[],"program_definition_cid":"DEFINITION","program_semantics_cid":"SEMANTICS","retention_class":"authority-evidence","run_identity_cid":"RUN","sensitivity":"private","version":"actql-effect-preview/0.1"}
  let template = template
    .replace_all(
      old="SEMANTICS",
      new=prepared_client_effect_computation_semantics_cid(owner),
    )
    .replace_all(
      old="DEFINITION",
      new=prepared_client_effect_computation_definition_cid(owner),
    )
    .replace_all(
      old="ENVIRONMENT",
      new=prepared_client_effect_computation_environment_cid(owner),
    )
    .replace_all(
      old="RUN",
      new=@publication.publication_contract_identity(definition),
    )
    .replace_all(
      old="INVOCATION",
      new=@publication.publication_contract_identity(invocation),
    )
    .replace_all(
      old="PLAN",
      new=@publication.publication_contract_identity(
        client_effect_compilation_compiled_plan(allowed.compilation),
      ),
    )
    .replace_all(
      old="\"AUTHORING\"",
      new=@publication.run_evidence_value_json(authoring),
    )
  let (preview_wire, preview) = match
    @publication.author_effect_preview_semantic_wire(
      template,
      @publication.publication_contract_identity(definition),
      @publication.run_evidence_value_identity(authoring),
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => {
      println("Preview fixture: " + @debug.to_string(issue))
      abort("Preview fixture")
    }
  }
  let checkpoint = @checkpoint.seal_checkpoint(
    {
      ..body,
      required_artifact_cid: @publication.effect_preview_semantic_identity(
        preview,
      ),
    },
    checkpoint_reconciliation_limits(),
  ).unwrap()
  let state = if unknown { "unknown" } else { "applied" }
  let details = if unknown {
    "\"ledger_head_cid\":\"sha256:" + "e".repeat(64) + "\""
  } else {
    "\"outcome_receipt_cid\":\"sha256:" + "e".repeat(64) + "\""
  }
  let receipt_body = "{\"version\":\"actql-effect-apply-receipt/0.1\",\"run_identity_cid\":\"" +
    @publication.publication_contract_identity(definition) +
    "\",\"effect_preview_cid\":\"" +
    @publication.effect_preview_semantic_identity(preview) +
    "\",\"effect_member_preview_cid\":\"" +
    @publication.effect_preview_member_identity(preview, 0).unwrap() +
    "\",\"rows\":[{\"row_index\":0,\"row_preview_cid\":\"" +
    @publication.effect_preview_ordered_row_identity(preview, 0, 0).unwrap() +
    "\",\"state\":\"" +
    state +
    "\",\"dispatch_entry_cid\":\"sha256:" +
    "d".repeat(64) +
    "\",\"attempt_sequence\":1," +
    details +
    "}],\"status\":\"" +
    (if unknown { "unknown_outcome" } else { "applied" }) +
    "\"}"
  let publication_member = @publication.seal_publication_contract(
    "effect_apply_receipt", receipt_body, 100000, 10000, 100,
  ).unwrap()
  let set = @publication.issue_effect_set_apply_receipt_from_members(
    preview,
    [publication_member],
    [false],
    100000,
    10000,
    100,
  ).unwrap()
  {
    allowed,
    definition,
    checkpoint,
    preview_wire,
    invocation_wire: @publication.publication_contract_json(invocation),
    set_wire: @publication.publication_contract_json(set),
    members: [@publication.publication_contract_json(publication_member)],
  }
}

///|
fn checkpoint_reconciliation_project(
  f : CheckpointReconciliationFixture,
) -> Result[String, ClientEffectCheckpointReconciliationIssue] {
  client_effect_review_checkpoint_reconciliation_state(
    f.checkpoint,
    f.allowed,
    f.definition,
    f.checkpoint.wire,
    f.preview_wire,
    f.invocation_wire,
    f.set_wire,
    f.members,
    "2026-10-09T03:00:00.000Z",
    ["published"],
    checkpoint_reconciliation_limits(),
  )
}

///|
test "original Checkpoint Preview admits the same Run and original authoring data" {
  let f = checkpoint_reconciliation_fixture()
  let preview = admit_client_effect_review_checkpoint_preview(
    f.checkpoint,
    f.allowed,
    f.definition,
    f.checkpoint.wire,
    f.preview_wire,
    checkpoint_reconciliation_limits(),
  ).unwrap()
  assert_eq(
    @publication.effect_preview_semantic_identity(preview),
    f.checkpoint.checkpoint.required_artifact_cid,
  )
  assert_eq(@publication.effect_preview_member_count(preview), 1)
}

///|
test "original Checkpoint Preview refuses changed stored bytes and another Run" {
  let f = checkpoint_reconciliation_fixture()
  let limits = checkpoint_reconciliation_limits()
  assert_true(
    admit_client_effect_review_checkpoint_preview(
      f.checkpoint,
      f.allowed,
      f.definition,
      f.checkpoint.wire + " ",
      f.preview_wire,
      limits,
    )
    is Err(Checkpoint(_)),
  )
  let other = issue_client_effect_run_definition(
    f.allowed,
    "scope",
    "other-run",
    "2026-10-09T00:00:00.000Z",
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  assert_true(
    admit_client_effect_review_checkpoint_preview(
      f.checkpoint,
      f.allowed,
      other,
      f.checkpoint.wire,
      f.preview_wire,
      limits,
    )
    is Err(Binding(ForeignSubject)),
  )
}

///|
test "original Checkpoint reconciliation projects exact admitted Unknown receipts" {
  let f = checkpoint_reconciliation_fixture()
  let wire = checkpoint_reconciliation_project(f).unwrap()
  assert_eq(
    wire, "{\"next_action\":{\"effects\":[\"save\"],\"kind\":\"reconcile\"},\"result_availability\":{\"published\":{\"observed_at\":\"2026-10-09T03:00:00.000Z\",\"reason\":\"not_published\",\"state\":\"unavailable\"}},\"result_available\":false,\"run_id\":\"original-run\",\"status\":\"needs_reconciliation\",\"updated_at\":\"2026-10-09T03:00:00.000Z\",\"version\":\"actql-run-state/0.1\"}",
  )
}

///|
test "original Checkpoint reconciliation refuses changed original and incomplete receipts" {
  let f = checkpoint_reconciliation_fixture()
  let limits = checkpoint_reconciliation_limits()
  assert_true(
    client_effect_review_checkpoint_reconciliation_state(
      f.checkpoint,
      f.allowed,
      f.definition,
      f.checkpoint.wire + " ",
      "invalid",
      "invalid",
      "invalid",
      [],
      "invalid",
      [],
      limits,
    )
    is Err(Checkpoint(@checkpoint.PersistedWireMismatch)),
  )
  let wrong = @checkpoint.seal_checkpoint(
    {
      ..f.checkpoint.checkpoint,
      required_artifact_cid: "sha256:" + "f".repeat(64),
    },
    limits,
  ).unwrap()
  assert_true(
    checkpoint_reconciliation_project({ ..f, checkpoint: wrong, })
    is Err(ForeignPreview),
  )
  assert_true(
    checkpoint_reconciliation_project({ ..f, invocation_wire: "{}", })
    is Err(Invocation(_)),
  )
  assert_true(
    checkpoint_reconciliation_project({ ..f, members: [], })
    is Err(RunState(@publication.EffectSetMismatch)),
  )
  assert_true(
    checkpoint_reconciliation_project({
      ..f,
      members: [f.members[0], f.members[0]],
    })
    is Err(RunState(@publication.EffectSetMismatch)),
  )
  assert_true(
    checkpoint_reconciliation_project(
      checkpoint_reconciliation_fixture(unknown=false),
    )
    is Err(RunState(@publication.ActionStatusMismatch)),
  )
}

///|
test "original Checkpoint reconciliation retains full Preview Invocation and finite writer checks" {
  let f = checkpoint_reconciliation_fixture()
  let limits = checkpoint_reconciliation_limits()
  let owner = f.allowed.compilation.owner
  let original_authoring = issue_prepared_client_authoring_context(
    client_effect_program_view(owner),
    100000,
    10000,
    100,
  ).unwrap()
  let foreign_authoring = @publication.seal_run_evidence_value(
    "authoring_context",
    "{\"version\":\"actql-authoring-context/0.1\",\"program_definition_cid\":\"" +
    prepared_client_effect_computation_definition_cid(owner) +
    "\",\"annotations\":[{\"target\":{\"kind\":\"program\",\"source_path\":\"$\",\"name\":\"client-effect\"},\"meta\":{\"note\":\"foreign\"}}]}",
    100000,
    10000,
    100,
  ).unwrap()
  let foreign_preview = f.preview_wire.replace_all(
    old=@publication.run_evidence_value_json(original_authoring),
    new=@publication.run_evidence_value_json(foreign_authoring),
  )
  assert_true(foreign_preview != f.preview_wire)
  assert_true(
    checkpoint_reconciliation_project({ ..f, preview_wire: foreign_preview, })
    is Err(Preview(@publication.AuthoringBindingMismatch)),
  )
  let (_, other_invocation) = issue_client_effect_source_free_invocation(
    f.allowed.compilation,
    "sha256:" + "5".repeat(64),
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(
    checkpoint_reconciliation_project({
      ..f,
      invocation_wire: @publication.publication_contract_json(other_invocation),
    })
    is Err(RunBinding(@publication.PreviewRunForeignInvocation)),
  )
  let other_definition = issue_client_effect_run_definition(
    f.allowed,
    "scope",
    "other-run",
    "2026-10-09T00:00:00.000Z",
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  assert_true(
    checkpoint_reconciliation_project({ ..f, definition: other_definition, })
    is Err(Binding(ForeignSubject)),
  )
  let bytes = @utf8.encode(f.preview_wire).length()
  assert_true(
    client_effect_review_checkpoint_reconciliation_state(
      f.checkpoint,
      f.allowed,
      f.definition,
      f.checkpoint.wire,
      f.preview_wire,
      f.invocation_wire,
      f.set_wire,
      f.members,
      "2026-10-09T03:00:00.000Z",
      [],
      { ..limits, max_wire_bytes: bytes, },
    )
    is Ok(_),
  )
  assert_true(
    client_effect_review_checkpoint_reconciliation_state(
      f.checkpoint,
      f.allowed,
      f.definition,
      f.checkpoint.wire,
      f.preview_wire,
      f.invocation_wire,
      f.set_wire,
      f.members,
      "2026-10-09T03:00:00.000Z",
      [],
      { ..limits, max_wire_bytes: bytes - 1, },
    )
    is Err(Preview(_)),
  )
  assert_true(
    client_effect_review_checkpoint_reconciliation_state(
      f.checkpoint,
      f.allowed,
      f.definition,
      f.checkpoint.wire,
      f.preview_wire,
      f.invocation_wire,
      f.set_wire,
      f.members,
      "invalid-time",
      [],
      limits,
    )
    is Err(RunState(@publication.InvalidObservationTime("run"))),
  )
  assert_true(
    client_effect_review_checkpoint_reconciliation_state(
      f.checkpoint,
      f.allowed,
      f.definition,
      f.checkpoint.wire,
      f.preview_wire,
      f.invocation_wire,
      f.set_wire,
      f.members,
      "2026-10-09T03:00:00.000Z",
      ["same", "same"],
      limits,
    )
    is Err(RunState(@publication.DuplicateDeclaredResult("same"))),
  )
}
