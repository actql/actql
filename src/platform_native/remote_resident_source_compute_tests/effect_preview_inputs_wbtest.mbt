// Actual Native input/Artifact identity binding to the existing Preview Owner.
// Target version, read decision, capability and Store authority are fixtures.
// Source content is issued from the actual Native local Artifact; the existing
// Store fixture checks private payload custody separately. Encrypted Captured
// Run persistence, target I/O, approval, waiting commit and writes are not claimed.

///|
fn retained_effect_preview_inputs(
  consumer : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  invocation : @publication.PublicationContract,
  artifact : @host.ClientEffectLocalResultArtifact,
  local_result : Int,
  stop_custodies : Array[(@resident.ResidentEffectSourceCustody, @store.Store)],
  local_manifest : @host.ClientEffectLocalManifest,
  imported : @host.ClientEffectImportedEvidence,
  acquired : @host.ClientEffectAcquiredEvidence,
  acquired_bodies : (String, String),
  dependencies : Array[@host.ClientEffectDependencyCapture],
  public_capture : @resident.ResidentEffectResultCapture,
  original_work? : (
    @client.NativeClientEffectSourceWork,
    @client.NativeClientRunJournal,
  )? = None,
  initial_reviewer? : (
    PairedInitialReviewerFixture,
    @client.NativeClientSubmissionReference,
  )? = None,
) -> Unit raise {
  let owner = materials.prepared
  let retention = retained_compute_effect_retention()
  let source_binding = retained_compute_cid("e")
  let store_authority = retained_compute_cid("a")
  let source = consumer
    .issue_effect_source_artifact(
      materials, inputs, 0, artifact, invocation, retention, source_binding, store_authority,
      65536, 4096, 64,
    )
    .unwrap()
  println("retained-effect-source: artifact-issued")
  assert_eq(
    @publication.effect_source_artifact_preview_binding(
      source,
      @publication.publication_contract_identity(invocation),
      "r",
      store_authority,
    ),
    Ok((@publication.publication_contract_identity(source), source_binding)),
  )
  let foreign_invocation = @publication.seal_publication_contract(
    "run_invocation",
    "{\"version\":\"actql-run-invocation/0.1\",\"invocation_template_cid\":\"" +
    retained_compute_cid("f") +
    "\",\"observation_set_cid\":\"" +
    retained_compute_cid("e") +
    "\"}",
    65536,
    4096,
    64,
  ).unwrap()
  assert_true(
    consumer.issue_effect_source_artifact(
      materials, inputs, 0, artifact, foreign_invocation, retention, source_binding,
      store_authority, 65536, 4096, 64,
    )
    is Err(ForeignInvocation),
  )
  let refreshed_retention = @publication.seal_publication_contract(
    "result_retention_policy",
    @publication.publication_contract_json(retention)
    .replace_all(
      old="\"effective_retention_policy_cid\":\"" +
        @publication.publication_contract_identity(retention) +
        "\",",
      new="",
    )
    .replace_all(old="2026-10-10T01:00:00.000Z", new="2026-10-10T01:01:00.000Z"),
    65536,
    4096,
    64,
  ).unwrap()
  assert_true(
    consumer.issue_effect_source_artifact(
      materials, inputs, 0, artifact, invocation, refreshed_retention, source_binding,
      store_authority, 65536, 4096, 64,
    )
    is Err(ForeignRetention),
  )
  assert_true(
    consumer.issue_effect_source_artifact(
      materials, inputs, 1, artifact, invocation, retention, source_binding, store_authority,
      65536, 4096, 64,
    )
    is Err(ForeignInput),
  )
  let identity = @host.issue_source_free_client_effect_local_identity(
    owner, inputs, 0, artifact, 10000, 65536, 4096, 64,
  ).unwrap()
  let definition = @host.prepared_client_effect_computation_definition_cid(
    owner,
  )
  let authoring = @publication.seal_run_evidence_value(
    "authoring_context",
    "{\"version\":\"actql-authoring-context/0.1\",\"program_definition_cid\":\"" +
    definition +
    "\",\"annotations\":[]}",
    65536,
    4096,
    64,
  ).unwrap()
  let descriptor = @host.client_effect_member_descriptor(
    owner, 1, "save", 10000,
  ).unwrap()
  let candidate = @host.prepared_client_effect_computation_candidate(owner)
  let effects = @checked.effect_program_static_effects(candidate)
  let terminal = @results.effect_plan_terminal_for_member(
      @results.effect_static_candidate_mapping_rules(effects),
      0,
      100,
      10000,
    )
    .unwrap()
    .unwrap()
  let plan = @results.effect_plan_pipeline_cid(terminal, 65536, 4096, 64)
  let run_cid = @publication.publication_contract_identity(
    materials.run_definition,
  )
  let authoring_cid = @publication.run_evidence_value_identity(authoring)
  let raw =
    #|{"version":"actql-effect-preview/0.1","sensitivity":"private","retention_class":"authority-evidence","encryption_required":true,"program_semantics_cid":"@SEMANTICS@","program_definition_cid":"@DEFINITION@","invocation_cid":"@INVOCATION@","run_identity_cid":"@RUN@","compiled_plan_cid":"@COMPILED@","check_environment_cid":"@ENVIRONMENT@","authoring_context":@AUTHORING@,"barrier_provenance_cids":[],"model_derived":false,"model_task_contract_cids":[],"model_invocation_evidence_cids":[],"model_response_artifact_cids":[],"effects":[{"effect_id":"save","effect_kind":"update","target":"connector://crm/account","mapping":"mapping:crm.account.v1","resolved_mapping_contract_cid":"@MAPPING@","effect_identity_cid":"@EFFECT@","source_result":"r","effect_plan_logical_cid":"@PLAN@","result_artifact_cid":"@ARTIFACT@","preview_strength":"full_diff","source_binding_cid":"@FIXTURE@","capability_evidence_cid":"@FIXTURE@","authority_scope_cid":"@AUTHORITY@","write_footprint":{"kind":"exact_targets","provider_namespace":"fixture","provider_boundary_cid":"@FIXTURE@","resource_kind":"Account","resource_identity_scheme_cid":"@FIXTURE@","provider_object_identity_cids":["@FIXTURE@"]},"count":1,"max_items":1,"required_permissions":["scope:update"],"approval":"required","on_item_failure":"halt","changes":[{"target_row_identity":3,"target_guard":{"state":"version","version_cid":"@FIXTURE@"},"before":{"state":"present","value":{"Name":0}},"after":{"state":"present","value":{"Name":3}},"intended_changes":{"state":"present","value":{"Name":3}},"row_preview_cid":"@FIXTURE@","row_idempotency_key":"@FIXTURE@"}],"row_order":[],"effect_member_preview_cid":"@FIXTURE@","executed":false}],"executed":false,"effect_preview_cid":"@FIXTURE@"}
  let raw = raw
    .replace_all(
      old="\"source_binding_cid\":\"@FIXTURE@\"",
      new="\"source_binding_cid\":\"" + source_binding + "\"",
    )
    .replace_all(old="@DEFINITION@", new=definition)
    .replace_all(
      old="@SEMANTICS@",
      new=@host.prepared_client_effect_computation_semantics_cid(owner),
    )
    .replace_all(
      old="@ENVIRONMENT@",
      new=@host.prepared_client_effect_computation_environment_cid(owner),
    )
    .replace_all(
      old="@COMPILED@",
      new=@publication.publication_contract_identity(
        @host.client_effect_compilation_compiled_plan(materials.compilation),
      ),
    )
    .replace_all(
      old="@INVOCATION@",
      new=@publication.publication_contract_identity(invocation),
    )
    .replace_all(old="@RUN@", new=run_cid)
    .replace_all(
      old="@AUTHORING@",
      new=@publication.run_evidence_value_json(authoring),
    )
    .replace_all(old="@MAPPING@", new=descriptor.5)
    .replace_all(old="@PLAN@", new=plan)
    .replace_all(
      old="@EFFECT@",
      new=@host.client_effect_local_identity_cid(identity),
    )
    .replace_all(
      old="@ARTIFACT@",
      new=@host.client_effect_local_result_artifact_cid(artifact),
    )
    .replace_all(
      old="@AUTHORITY@",
      new=@host.client_request_authority_scope_cid(materials.request.unwrap()),
    )
    .replace_all(old="@FIXTURE@", new=retained_compute_cid("d"))
  let draft = @publication.canonical_effect_preview_draft_wire(
    raw, 65536, 4096, 64,
  ).unwrap()
  let (wire, preview) = @publication.author_effect_preview_semantic_wire(
    draft, run_cid, authoring_cid, 65536, 4096, 64,
  ).unwrap()
  let (wire, preview) = if original_work is Some(_) {
    let scope = @host.client_request_logical_scope(materials.request.unwrap())
    // Semantic authoring leaves dispatch bindings unfinished. The original
    // request Owner, not a transported seed or row position, supplies scope.
    assert_true(
      @effect.recover_effect_preview_apply_keys(
        preview, scope, 1, 10000, 20000, 4096, 32, 8,
      )
      is Err(@effect.Mismatch(@effect.RowKeyMismatch(0, 0))),
    )
    let key = @effect.prepare_effect_dispatch_key(
      scope,
      @publication.effect_preview_semantic_identity(preview),
      @publication.effect_preview_row_correlation_wire(preview, 0, 0).unwrap(),
      4096,
      32,
      8,
    ).unwrap()
    let completed = @publication.complete_effect_preview_dispatch_keys(
      wire,
      [[@effect.effect_dispatch_key_cid(key)]],
      run_cid,
      authoring_cid,
      65536,
      4096,
      64,
    ).unwrap()
    let admitted = @effect.admit_effect_preview_apply_identity(
      completed,
      run_cid,
      authoring_cid,
      scope,
      [[key]],
      65536,
      4096,
      64,
    ).unwrap()
    assert_eq(
      @publication.effect_preview_semantic_identity(admitted),
      @publication.effect_preview_semantic_identity(preview),
    )
    (completed, admitted)
  } else {
    (wire, preview)
  }
  let result = @publication.admit_publication_contract(
    "result_artifact",
    @host.client_effect_local_result_artifact_json(artifact),
    65536,
    4096,
    64,
  ).unwrap()
  let admitted_source = @publication.admit_captured_effect_source_from_result(
    preview, 0, invocation, source, result, store_authority,
  ).unwrap()
  let (local_source, inventory) = retained_effect_capture_inventory(
    materials, inputs, admitted_source, local_manifest, artifact, imported, acquired,
    acquired_bodies, dependencies,
  )
  // Source custody has independent physical Store/cleanup acceptance.
  // Keep that fault exercise in its own Run; review retains the same actual
  // source/dependency facts through the complete computation capture Owner.
  if original_work is None {
    retained_effect_source_store(
      consumer, materials, inputs, artifact, admitted_source, local_result, stop_custodies,
    )
  }
  assert_true(
    @publication.captured_effect_source_matches_result_facts(
      admitted_source, result, "r",
    ),
  )
  assert_true(
    @publication.effect_source_artifact_holding_cid(
      source, "save", run_cid, store_authority,
    )
    is Some(_),
  )
  assert_true(
    @publication.admit_captured_effect_source_from_result(
      preview,
      0,
      invocation,
      source,
      result,
      retained_compute_cid("b"),
    )
    is Err(_),
  )
  let limits : @host.ClientCapturedEffectPreviewLimits = {
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
  }
  let bind = (material, stage, text, issued) => {
    consumer.bind_effect_preview_inputs(
      material, inputs, invocation, stage, text, authoring_cid, issued, limits,
    )
  }
  let captured = bind(materials, 1, wire, [identity]).unwrap()
  assert_true(@strategy.captured_effect_preview_inputs_available(captured))
  assert_eq(@publication.effect_preview_row_count(preview, 0), Some(1))
  assert_eq(
    @publication.effect_preview_row_intended_changes_wire(preview, 0, 0),
    Some("{\"state\":\"present\",\"value\":{\"Name\":3}}"),
  )
  assert_true(
    @strategy.captured_effect_preview_plan_terminal(captured, 0, 100, 10000)
    is Ok(Some(_)),
  )
  let proof = consumer
    .verify_effect_preview_plan(
      inputs,
      captured,
      0,
      local_result,
      resident_compute_limits(),
      100,
      10000,
      65536,
      4096,
      64,
    )
    .unwrap()
  assert_true(@strategy.captured_effect_plan_proof_matches(proof, captured, 0))
  retained_effect_complete_capture(
    consumer,
    materials,
    inputs,
    invocation,
    captured,
    proof,
    admitted_source,
    local_source,
    inventory,
    authoring,
    public_capture,
    review_retention=original_work is Some(_),
    private_preview=if original_work is Some(_) {
      Some((wire, authoring_cid))
    } else {
      None
    },
    original_work~,
    initial_reviewer~,
  )
  public_capture.output.cancel()
  assert_true(
    consumer.verify_effect_preview_plan(
      inputs,
      captured,
      0,
      0,
      resident_compute_limits(),
      100,
      10000,
      65536,
      4096,
      64,
    )
    is Err(ForeignInput),
  )
  let wrong_rows = wire.replace_all(old="\"Name\":3", new="\"Name\":4")
  let (wrong_rows, _) = @publication.author_effect_preview_semantic_wire(
    wrong_rows, run_cid, authoring_cid, 65536, 4096, 64,
  ).unwrap()
  let wrong_preview = bind(materials, 1, wrong_rows, [identity]).unwrap()
  assert_true(
    consumer.verify_effect_preview_plan(
      inputs,
      wrong_preview,
      0,
      local_result,
      resident_compute_limits(),
      100,
      10000,
      65536,
      4096,
      64,
    )
    is Err(Plan(PreviewMismatch)),
  )
  assert_true(@strategy.captured_effect_preview_inputs_available(captured))
  assert_true(bind(materials, 1, wire, []) is Err(Identity(_)))
  assert_true(bind(materials, 0, wire, [identity]) is Err(Run(_)))
  let another_run = @host.issue_client_effect_run_definition(
    materials.allowed,
    "retained-effect",
    "another-preview-run",
    "2026-10-09T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    bind({ ..materials, run_definition: another_run, }, 1, wire, [identity])
    is Err(ForeignInput),
  )
  assert_true(
    consumer.issue_effect_source_artifact(
      { ..materials, run_definition: another_run, },
      inputs,
      0,
      artifact,
      invocation,
      retention,
      source_binding,
      store_authority,
      65536,
      4096,
      64,
    )
    is Err(ForeignRun),
  )
  let changed = wire.replace(
    old="\"source_result\":\"r\"",
    new="\"source_result\":\"other\"",
  )
  let (changed, _) = @publication.author_effect_preview_semantic_wire(
    changed, run_cid, authoring_cid, 65536, 4096, 64,
  ).unwrap()
  assert_true(bind(materials, 1, changed, [identity]) is Err(Identity(_)))
}
