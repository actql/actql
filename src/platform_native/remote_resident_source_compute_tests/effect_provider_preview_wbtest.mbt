// Actual imported Native Artifact + physical Provider rows + common Preview
// and dispatch-key admission. Store authority and read-decision evidence remain
// local installation fixtures; waiting commit, approval and writes are separate.

///|
fn resident_provider_preview(
  consumer : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  local_result : Int,
  artifact : @host.ClientEffectLocalResultArtifact,
  invocation : @publication.PublicationContract,
  facts : ResidentProviderFacts,
) -> (
  @effect_provider.NativeResidentEffectPreview,
  @publication.CapturedEffectSourceArtifact,
) raise {
  let limits : @host.ClientCapturedEffectPreviewLimits = {
    max_work: 10000,
    max_wire_bytes: 65536,
    max_nodes: 10000,
    max_depth: 64,
    plan: {
      max_work: 10000,
      max_fields: 100,
      max_bytes: 65536,
      max_nodes: 10000,
      max_depth: 64,
    },
  }
  let prepare = (material, request, result, targets) => {
    @effect_provider.prepare_native_resident_effect_preview(
      consumer,
      material,
      inputs,
      request,
      1,
      "save",
      result,
      artifact,
      invocation,
      retained_compute_effect_retention(),
      retained_compute_cid("e"),
      retained_compute_cid("a"),
      provider_mapping(),
      facts.runtime_bundle_cid,
      facts.catalog,
      targets,
      limits,
      resident_compute_limits(),
      { max_bytes: 4096, max_nodes: 32, max_depth: 8, },
    )
  }
  assert_true(
    prepare(materials, facts.request, local_result, []) is Err(InvalidLimits),
  )
  let (_, foreign_request) = retained_compute_effect_materials()
  assert_true(
    prepare(materials, foreign_request, local_result, facts.rows)
    is Err(Request(IdentityMismatch)),
  )
  let foreign_run = @host.issue_client_effect_run_definition(
    materials.allowed,
    "retained-effect",
    "foreign-provider-preview",
    "2026-10-09T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    prepare(
      { ..materials, run_definition: foreign_run, },
      facts.request,
      local_result,
      facts.rows,
    )
    is Err(Source(ForeignRun)),
  )
  let prepared = match
    prepare(materials, facts.request, local_result, facts.rows) {
    Ok(value) => value
    Err(issue) => {
      let code = match issue {
        InvalidLimits => "limits"
        ForeignEvidence => "foreign-evidence"
        Encoding => "encoding"
        Request(value) => "request: " + @debug.to_string(value)
        Source(_) => "source"
        Identity(value) => "identity: " + @debug.to_string(value)
        Capability(value) => "capability: " + @debug.to_string(value)
        Mapping(value) => "mapping: " + @debug.to_string(value)
        Target(value) => "target: " + @debug.to_string(value)
        Footprint(value) => "footprint: " + @debug.to_string(value)
        Draft(value) => "draft: " + @debug.to_string(value)
        Preview(value) => "preview: " + @debug.to_string(value)
        Dispatch(value) => "dispatch: " + @debug.to_string(value)
        Keys(value) => "keys: " + @debug.to_string(value)
        Binding(_) => "binding"
        Plan(_) => "plan"
      }
      fail("retained Provider Preview: " + code)
    }
  }
  println("native-effect-provider: Preview bound and actual plan proved")
  let preview = @publication.admit_effect_preview_identity(
    prepared.wire,
    @publication.publication_contract_identity(materials.run_definition),
    @publication.run_evidence_value_identity(prepared.authoring),
    65536,
    10000,
    64,
  ).unwrap()
  assert_eq(@publication.effect_preview_member_count(preview), 1)
  assert_eq(@publication.effect_preview_row_count(preview, 0), Some(1))
  assert_eq(
    @publication.effect_preview_row_intended_changes_wire(preview, 0, 0),
    Some("{\"state\":\"present\",\"value\":{\"Count__c\":3}}"),
  )
  assert_true(
    prepared.wire.contains(
      "\"before\":{\"state\":\"present\",\"value\":{\"Count__c\":7}}",
    ),
  )
  assert_true(
    prepared.wire.contains(
      @catalog.target_preview_row_guard_cid(facts.rows[0].3),
    ),
  )
  assert_true(
    prepared.wire.contains(
      @catalog.write_capability_identity(prepared.capability),
    ),
  )
  assert_true(
    prepared.wire.contains(
      @host.client_request_authority_scope_cid(facts.request),
    ),
  )
  assert_true(
    @strategy.captured_effect_plan_proof_matches(
      prepared.proof.unwrap(),
      prepared.preview,
      0,
    ),
  )
  assert_true(
    @strategy.captured_effect_preview_inputs_available(prepared.preview),
  )
  assert_eq(prepared.keys.length(), 1)
  assert_true(
    @host.check_source_free_client_effect_preview_identities(
      materials.prepared,
      inputs,
      prepared.wire,
      @publication.publication_contract_identity(materials.run_definition),
      @publication.run_evidence_value_identity(prepared.authoring),
      [prepared.identity],
      65536,
      10000,
      64,
    )
    is Ok(_),
  )
  let result_contract = @publication.admit_publication_contract(
    "result_artifact",
    @host.client_effect_local_result_artifact_json(artifact),
    65536,
    10000,
    64,
  ).unwrap()
  let source = @publication.admit_captured_effect_source_from_result(
    preview,
    0,
    invocation,
    prepared.source,
    result_contract,
    retained_compute_cid("a"),
  ).unwrap()
  assert_true(
    @publication.captured_effect_source_matches_result_facts(
      source, result_contract, "r",
    ),
  )
  let repeated = prepare(materials, facts.request, local_result, facts.rows).unwrap()
  assert_eq(repeated.wire, prepared.wire)
  assert_true(
    @strategy.captured_effect_plan_proof_matches(
      repeated.proof.unwrap(),
      repeated.preview,
      0,
    ),
  )
  // Wrong physical input cannot be substituted even after semantic authoring.
  let mut root = -1
  for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
    if !@strategy.captured_effect_local_result_matches_member(inputs, index, 0) {
      root = index
    }
  }
  assert_true(root >= 0)
  assert_true(
    prepare(materials, facts.request, root, facts.rows)
    is Err(Plan(ForeignInput)),
  )
  assert_true(
    @strategy.captured_effect_preview_inputs_available(prepared.preview),
  )
  println(
    "native-effect-provider: original retained Result and physical target Preview plan verified",
  )
  (prepared, source)
}
