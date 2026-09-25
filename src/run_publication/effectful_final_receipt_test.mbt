///|
fn final_test_receipt_field(
  value : @json.CanonicalValue,
  name : String,
) -> String {
  match @json.object_field(value, name) {
    Some(@json.String(cid)) => cid
    _ => abort("Missing computation Receipt field")
  }
}

///|
fn final_test_source_artifact(
  chain : CapturedRunTestChain,
) -> PublicationContract {
  let source = chain.artifact
  let value = captured_test_value(publication_contract_json(source))
  let body = "{\"version\":\"actql-effect-source-artifact/0.1\"," +
    "\"source_result\":\"rows\",\"source_binding_cid\":\"" +
    ordering_test_cid("a") +
    "\",\"invocation_cid\":\"" +
    publication_contract_identity(chain.invocation) +
    "\",\"store_authority_cid\":\"" +
    ordering_test_cid("d") +
    "\",\"logical_result_cid\":\"" +
    final_test_receipt_field(value, "logical_result_cid") +
    "\",\"result_schema_cid\":\"" +
    final_test_receipt_field(value, "result_schema_cid") +
    "\",\"actual_row_count\":1,\"actual_completeness\":\"complete\"," +
    "\"effective_data_policy_cid\":\"" +
    final_test_receipt_field(value, "effective_data_policy_cid") +
    "\",\"effective_retention_policy_cid\":\"" +
    final_test_receipt_field(value, "effective_retention_policy_cid") +
    "\",\"provenance_evidence_cids\":[]}"
  seal_publication_contract("effect_source_artifact", body, 65536, 4096, 32).unwrap()
}

///|
fn final_test_source(
  chain : CapturedRunTestChain,
  preview : EffectPreviewIdentity,
) -> CapturedEffectSourceArtifact {
  admit_captured_effect_source_artifact(
    preview,
    0,
    chain.invocation,
    final_test_source_artifact(chain),
    ordering_test_cid("d"),
  ).unwrap()
}

///|
fn final_test_local_wire(body : String) -> String {
  let value = captured_test_value(body)
  let cid = @json.cid_value(value, 65536, 4096, 32) catch {
    _ => abort("Invalid local test identity")
  }
  captured_test_wire(
    @json.object_with_string_field(value, "self_cid", cid).unwrap(),
  )
}

///|
fn final_test_local_source(
  chain : CapturedRunTestChain,
  source : CapturedEffectSourceArtifact,
) -> CapturedLocalEffectSourceEvidence {
  let unit_cid = ordering_test_cid("1")
  let definition = final_test_local_wire(
    "{\"version\":\"actql-local-result-definition/0.1\"," +
    "\"unit_definition_cid\":\"" +
    unit_cid +
    "\",\"result_name\":\"rows\"}",
  )
  let definition_cid = final_test_receipt_field(
    captured_test_value(definition),
    "self_cid",
  )
  let invocation = final_test_local_wire(
    "{\"version\":\"actql-local-computation-semantics/0.1\"," +
    "\"unit_definition_cid\":\"" +
    unit_cid +
    "\",\"used_values_cid\":\"" +
    ordering_test_cid("2") +
    "\",\"local_contracts_cid\":\"" +
    ordering_test_cid("3") +
    "\",\"observation_cids\":[],\"policy_cid\":\"" +
    ordering_test_cid("e") +
    "\"}",
  )
  let invocation_cid = final_test_receipt_field(
    captured_test_value(invocation),
    "self_cid",
  )
  let result = captured_test_value(publication_contract_json(chain.artifact))
  let evidence = issue_local_result_occurrence_evidence(
    definition_cid,
    final_test_receipt_field(result, "logical_result_cid"),
    final_test_receipt_field(result, "result_schema_cid"),
    unit_cid,
    [],
    ordering_test_cid("b"),
    final_test_receipt_field(result, "effective_data_policy_cid"),
    "actql-common-host",
    ordering_test_cid("c"),
    65536,
    4096,
    32,
  ).unwrap()
  let retention = manifest_test_retention(
    final_test_receipt_field(result, "effective_data_policy_cid"),
  )
  let artifact = issue_complete_local_result_artifact(
    definition_cid, invocation_cid, evidence, retention, 1, 65536, 4096, 32,
  ).unwrap()
  let manifest = final_test_local_wire(
    "{\"version\":\"actql-local-result-manifest/0.1\"," +
    "\"unit_definition_cid\":\"" +
    unit_cid +
    "\",\"local_invocation_cid\":\"" +
    invocation_cid +
    "\",\"results\":{\"rows\":\"" +
    publication_contract_identity(artifact) +
    "\"}}",
  )
  admit_captured_local_effect_source(
    source,
    definition,
    invocation,
    manifest,
    artifact,
    result_ordering_derivation_contract(evidence),
    result_ordering_evidence_contract(evidence),
    retention,
    65536,
    4096,
    32,
  ).unwrap()
}

///|
fn final_test_preview_wire(
  chain : CapturedRunTestChain,
  member_cid : String,
  preview_cid : String,
  plan? : Bool = true,
  artifact_cid? : String? = None,
) -> String {
  let receipt = publication_contract_json(chain.receipt)
  let value = captured_test_value(receipt)
  let cid = ordering_test_cid("a")
  let raw = "{\"version\":\"actql-effect-preview/0.1\"," +
    "\"sensitivity\":\"private\",\"retention_class\":\"authority-evidence\"," +
    "\"encryption_required\":true,\"program_semantics_cid\":\"" +
    final_test_receipt_field(value, "program_semantics_cid") +
    "\",\"program_definition_cid\":\"" +
    final_test_receipt_field(value, "program_definition_cid") +
    "\",\"invocation_cid\":\"" +
    final_test_receipt_field(value, "invocation_cid") +
    "\",\"run_identity_cid\":\"" +
    publication_contract_identity(chain.run) +
    "\",\"compiled_plan_cid\":\"" +
    final_test_receipt_field(value, "compiled_plan_cid") +
    "\",\"check_environment_cid\":\"" +
    final_test_receipt_field(value, "check_environment_cid") +
    "\",\"authoring_context\":" +
    run_evidence_value_json(chain.authoring) +
    ",\"barrier_provenance_cids\":[],\"model_derived\":false," +
    "\"model_task_contract_cids\":[],\"model_invocation_evidence_cids\":[]," +
    "\"model_response_artifact_cids\":[],\"effects\":[{" +
    "\"effect_id\":\"WriteOne\",\"effect_kind\":\"update\"," +
    "\"target\":\"Object\",\"mapping\":\"mapping:fixture\"," +
    "\"resolved_mapping_contract_cid\":\"" +
    cid +
    "\",\"effect_identity_cid\":\"" +
    cid +
    (if plan { "\",\"effect_plan_logical_cid\":\"" + cid } else { "" }) +
    "\",\"source_result\":\"rows\",\"result_artifact_cid\":\"" +
    artifact_cid.unwrap_or(
      publication_contract_identity(final_test_source_artifact(chain)),
    ) +
    "\",\"preview_strength\":\"full_diff\",\"source_binding_cid\":\"" +
    cid +
    "\",\"capability_evidence_cid\":\"" +
    cid +
    "\",\"authority_scope_cid\":\"" +
    cid +
    "\",\"write_footprint\":{\"kind\":\"exact_targets\"," +
    "\"resource_identity_scheme_cid\":\"" +
    cid +
    "\",\"provider_namespace\":\"provider\"," +
    "\"provider_boundary_cid\":\"" +
    cid +
    "\",\"resource_kind\":\"Object\"," +
    "\"provider_object_identity_cids\":[\"" +
    ordering_test_cid("1") +
    "\"]},\"count\":0,\"max_items\":1," +
    "\"required_permissions\":[\"write\"],\"approval\":\"none\"," +
    "\"on_item_failure\":\"halt\",\"changes\":[],\"row_order\":[]," +
    "\"effect_member_preview_cid\":\"" +
    member_cid +
    "\",\"executed\":false}],\"executed\":false," +
    "\"effect_preview_cid\":\"" +
    preview_cid +
    "\"}"
  captured_test_wire(captured_test_value(raw))
}

///|
fn final_test_preview(
  chain : CapturedRunTestChain,
  plan? : Bool = true,
  artifact_cid? : String? = None,
) -> EffectPreviewIdentity {
  let placeholder = ordering_test_cid("a")
  let (_, members) = match
    derive_effect_preview_identities(
      final_test_preview_wire(
        chain,
        placeholder,
        placeholder,
        plan~,
        artifact_cid~,
      ),
      65536,
      4096,
      32,
    ) {
    Ok(value) => value
    Err(issue) =>
      match issue {
        PreviewShape(_) => abort("Preview derivation: shape")
        InvalidMember => abort("Preview derivation: member")
        RowInventoryMismatch(_) => abort("Preview derivation: inventory")
        RowIdentityMismatch(_, _) => abort("Preview derivation: row")
        MemberIdentityMismatch(_) =>
          abort("Preview derivation: member identity")
        PreviewIdentityMismatch => abort("Preview derivation: identity")
        RunBindingMismatch => abort("Preview derivation: run")
        AuthoringBindingMismatch => abort("Preview derivation: authoring")
        AuthoringIdentityMismatch =>
          abort("Preview derivation: authoring identity")
        Encoding => abort("Preview derivation: encoding")
      }
  }
  let (preview_cid, _) = derive_effect_preview_identities(
    final_test_preview_wire(
      chain,
      members[0],
      placeholder,
      plan~,
      artifact_cid~,
    ),
    65536,
    4096,
    32,
  ).unwrap()
  admit_effect_preview_identity(
    final_test_preview_wire(
      chain,
      members[0],
      preview_cid,
      plan~,
      artifact_cid~,
    ),
    publication_contract_identity(chain.run),
    run_evidence_value_identity(chain.authoring),
    65536,
    4096,
    32,
  ).unwrap()
}

///|
/// Synthetic reference-closure fixture only. The plan payload and logical CID
/// are not an admitted AoA plan; product capture must supply that proof.
fn final_test_captured_with_plan_inventory(
  chain : CapturedRunTestChain,
  plans_wire : String,
  plan_cids_wire : String,
) -> PublicationContract {
  let snapshot = admit_captured_result_snapshot(
    chain.definition,
    chain.artifact,
    "[{\"value\":7}]",
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  let effect_free = issue_effect_free_captured_run(
    chain.run,
    chain.invocation,
    [chain.definition],
    [chain.artifact],
    chain.manifest,
    chain.receipt,
    [snapshot],
    [],
    chain.authoring,
    chain.models,
    65536,
    4096,
    32,
  ).unwrap()
  let value = captured_test_value(publication_contract_json(effect_free))
  let context = @json.object_field(value, "effect_context").unwrap()
  let context_body = @json.object_without_field(context, "effect_context_cid").unwrap()
  let context_body_wire = captured_test_wire(context_body)
    .replace(
      old="\"effect_plan_logical_cids\":{}",
      new="\"effect_plan_logical_cids\":" + plan_cids_wire,
    )
    .replace(old="\"effect_plans\":{}", new="\"effect_plans\":" + plans_wire)
    .replace(old="\"effects\":{}", new="\"effects\":{\"WriteOne\":{}}")
    .replace(
      old="\"effect_source_artifacts\":{}",
      new="\"effect_source_artifacts\":{\"WriteOne\":" +
        publication_contract_json(final_test_source_artifact(chain)) +
        "}",
    )
    .replace(
      old="\"effect_source_holding_cids\":{}",
      new="\"effect_source_holding_cids\":{\"WriteOne\":\"" +
        effect_source_artifact_holding_cid(
          final_test_source_artifact(chain),
          "WriteOne",
          publication_contract_identity(chain.run),
          ordering_test_cid("d"),
        ).unwrap() +
        "\"}",
    )
    .replace(
      old="\"effect_source_local_inventory\":{}",
      new="\"effect_source_local_inventory\":{\"WriteOne\":" +
        captured_local_effect_source_json(
          final_test_local_source(
            chain,
            final_test_source(chain, final_test_preview(chain)),
          ),
          65536,
          4096,
          32,
        ).unwrap() +
        "}",
    )
  let context_value = captured_test_value(context_body_wire)
  let context_cid = @json.cid_value(context_value, 65536, 4096, 32) catch {
    _ => abort("Invalid Effect Context identity")
  }
  let effect_context = context_body_wire.replace(
    old="{\"authoring_context\":",
    new="{\"effect_context_cid\":\"" + context_cid + "\",\"authoring_context\":",
  )
  let body = @json.object_without_field(value, "captured_run_cid").unwrap()
  let final_body = captured_test_wire(body).replace(
    old=captured_test_wire(context),
    new=effect_context,
  )
  seal_publication_contract("captured_run", final_body, 65536, 4096, 32).unwrap()
}

///|
fn final_test_captured(chain : CapturedRunTestChain) -> PublicationContract {
  let snapshot = admit_captured_result_snapshot(
    chain.definition,
    chain.artifact,
    "[{\"value\":7}]",
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  let source = final_test_source(chain, final_test_preview(chain))
  issue_effectful_captured_run(
    chain.run,
    chain.invocation,
    [chain.definition],
    [chain.artifact],
    chain.manifest,
    chain.receipt,
    [snapshot],
    [source],
    [final_test_local_source(chain, source)],
    [],
    chain.authoring,
    chain.models,
    final_test_preview(chain),
    [("WriteOne", "{}")],
    65536,
    4096,
    32,
  ).unwrap()
}

///|
test "Effectful capture issuer owns its exact Preview plan inventory" {
  let chain = captured_run_test_chain()
  let snapshot = admit_captured_result_snapshot(
    chain.definition,
    chain.artifact,
    "[{\"value\":7}]",
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  let preview = final_test_preview(chain)
  let issue = fn(
    plans : Array[(String, String)],
    identity : EffectPreviewIdentity,
  ) {
    let source = final_test_source(chain, preview)
    issue_effectful_captured_run(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      [snapshot],
      [source],
      [final_test_local_source(chain, source)],
      [],
      chain.authoring,
      chain.models,
      identity,
      plans,
      65536,
      4096,
      32,
    )
  }
  assert_true(issue([("WriteOne", "{}")], preview) is Ok(_))
  assert_true(
    issue([], preview) is Err(CaptureIssuanceInventoryMismatch("effect_plans")),
  )
  assert_true(
    issue([("Foreign", "{}")], preview)
    is Err(CaptureIssuanceInventoryMismatch("effect_plans")),
  )
  assert_true(
    issue([("WriteOne", "{}"), ("WriteOne", "{}")], preview)
    is Err(CaptureIssuanceInventoryMismatch("effect_plans")),
  )
  assert_true(
    issue([("WriteOne", "{")], preview)
    is Err(CaptureIssuanceInvalidRows("effect_plans")),
  )
  let command = final_test_preview(chain, plan=false)
  assert_true(issue([], command) is Ok(_))
  assert_true(
    issue([("WriteOne", "{}")], command)
    is Err(CaptureIssuanceInventoryMismatch("effect_plans")),
  )
  let foreign_artifact = final_test_preview(
    chain,
    artifact_cid=Some(ordering_test_cid("f")),
  )
  assert_true(
    issue([("WriteOne", "{}")], foreign_artifact)
    is Err(CaptureIssuanceInventoryMismatch("effect_source_artifacts")),
  )
}

///|
fn final_test_reseal_captured_context(
  captured : PublicationContract,
  old : String,
  new : String,
) -> PublicationContract {
  let value = captured_test_value(publication_contract_json(captured))
  let context = @json.object_field(value, "effect_context").unwrap()
  let context_body = @json.object_without_field(context, "effect_context_cid").unwrap()
  let altered = captured_test_value(
    captured_test_wire(context_body).replace(old~, new~),
  )
  let cid = @json.cid_value(altered, 65536, 4096, 32) catch {
    _ => abort("Invalid altered Effect Context")
  }
  let complete = @json.object_with_string_field(
    altered, "effect_context_cid", cid,
  ).unwrap()
  let captured_body = @json.object_without_field(value, "captured_run_cid").unwrap()
  seal_publication_contract(
    "captured_run",
    captured_test_wire(captured_body).replace(
      old=captured_test_wire(context),
      new=captured_test_wire(complete),
    ),
    65536,
    4096,
    32,
  ).unwrap()
}

///|
test "Effectful capture re-admits the exact local source inventory" {
  let chain = captured_run_test_chain()
  let captured = final_test_captured(chain)
  let preview = final_test_preview(chain)
  let (set_wire, member_wires, set_cid) = final_test_receipts(preview)
  let check = fn(candidate : PublicationContract) {
    admit_effectful_final_run_evidence_chain(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      candidate,
      preview,
      set_wire,
      member_wires,
      final_test_receipt_wire(chain.receipt, preview, set_cid, candidate),
      65536,
      4096,
      32,
    )
  }
  assert_true(check(captured) is Ok(_))
  let foreign_name = final_test_reseal_captured_context(
    captured, "\"result_name\":\"rows\"", "\"result_name\":\"foreign\"",
  )
  assert_true(check(foreign_name) is Err(_))
  let foreign_member = final_test_reseal_captured_context(
    captured, "\"effect_source_local_inventory\":{\"WriteOne\":", "\"effect_source_local_inventory\":{\"Foreign\":",
  )
  assert_true(check(foreign_member) is Err(_))
}

///|
fn final_test_receipts(
  preview : EffectPreviewIdentity,
) -> (String, Array[String], String) {
  let preview_cid = effect_preview_semantic_identity(preview)
  let member_cid = effect_preview_member_identity(preview, 0).unwrap()
  let member_receipt = seal_publication_contract(
    "effect_apply_receipt",
    "{\"version\":\"actql-effect-apply-receipt/0.1\"," +
    "\"run_identity_cid\":\"" +
    effect_preview_run_identity(preview) +
    "\"," +
    "\"effect_preview_cid\":\"" +
    preview_cid +
    "\",\"effect_member_preview_cid\":\"" +
    member_cid +
    "\",\"rows\":[],\"status\":\"applied\"}",
    65536,
    4096,
    32,
  ).unwrap()
  let set = seal_publication_contract(
    "effect_set_apply_receipt",
    "{\"version\":\"actql-effect-set-apply-receipt/0.1\"," +
    "\"effect_preview_cid\":\"" +
    preview_cid +
    "\",\"apply_policy\":\"attempt_all\",\"effects\":[{" +
    "\"effect_id\":\"WriteOne\",\"effect_member_preview_cid\":\"" +
    member_cid +
    "\",\"state\":\"applied\",\"replayed\":false," +
    "\"member_receipt_cid\":\"" +
    publication_contract_identity(member_receipt) +
    "\"}],\"status\":\"applied\"}",
    65536,
    4096,
    32,
  ).unwrap()
  (
    publication_contract_json(set),
    [publication_contract_json(member_receipt)],
    publication_contract_identity(set),
  )
}

///|
fn final_test_receipt_wire(
  computation : PublicationContract,
  preview : EffectPreviewIdentity,
  set_cid : String,
  captured : PublicationContract,
) -> String {
  let body = @json.object_without_field(
    captured_test_value(publication_contract_json(computation)),
    "receipt_identity_cid",
  ).unwrap()
  let wire = captured_test_wire(body).replace(
    old="{\"aoa_ir_version\":",
    new="{\"effect_preview_cid\":\"" +
      effect_preview_semantic_identity(preview) +
      "\",\"effect_set_apply_receipt_cid\":\"" +
      set_cid +
      "\",\"captured_run_cid\":\"" +
      publication_contract_identity(captured) +
      "\",\"aoa_ir_version\":",
  )
  publication_contract_json(
    seal_publication_contract("run_receipt", wire, 65536, 4096, 32).unwrap(),
  )
}

///|
fn final_test_reseal_receipt(wire : String) -> PublicationContract {
  seal_publication_contract(
    "run_receipt",
    captured_test_wire(
      @json.object_without_field(
        captured_test_value(wire),
        "receipt_identity_cid",
      ).unwrap(),
    ),
    65536,
    4096,
    32,
  ).unwrap()
}

///|
test "final Effectful Receipt references one exact prior chain" {
  let chain = captured_run_test_chain()
  let preview = final_test_preview(chain)
  let captured = final_test_captured(chain)
  let (set_wire, member_wires, set_cid) = final_test_receipts(preview)
  let final_wire = final_test_receipt_wire(
    chain.receipt,
    preview,
    set_cid,
    captured,
  )
  let final_receipt = admit_effectful_final_receipt_references(
    chain.run,
    chain.receipt,
    captured,
    preview,
    set_wire,
    member_wires,
    final_wire,
    65536,
    4096,
    32,
  ).unwrap()
  let complete = admit_effectful_final_run_evidence_chain(
    chain.run,
    chain.invocation,
    [chain.definition],
    [chain.artifact],
    chain.manifest,
    chain.receipt,
    captured,
    preview,
    set_wire,
    member_wires,
    final_wire,
    65536,
    4096,
    32,
  ).unwrap()
  assert_eq(
    publication_contract_identity(complete),
    publication_contract_identity(final_receipt),
  )
  let issued = issue_effectful_final_run_receipt(
    chain.run,
    chain.receipt,
    captured,
    preview,
    set_wire,
    member_wires,
    65536,
    4096,
    32,
  ).unwrap()
  assert_eq(
    publication_contract_identity(issued),
    publication_contract_identity(final_receipt),
  )
  assert_true(
    issue_effectful_final_run_receipt(
      chain.run,
      issued,
      captured,
      preview,
      set_wire,
      member_wires,
      65536,
      4096,
      32,
    )
    is Err(InvalidComputation),
  )
  assert_true(
    publication_contract_identity(final_receipt) !=
    publication_contract_identity(chain.receipt),
  )
  assert_eq(
    effect_preview_member_plan_cid(preview, 0),
    Some(ordering_test_cid("a")),
  )
  let foreign_wire = final_wire.replace(
    old="\"captured_run_cid\":\"" +
      publication_contract_identity(captured) +
      "\"",
    new="\"captured_run_cid\":\"" + ordering_test_cid("f") + "\"",
  )
  let foreign = final_test_reseal_receipt(foreign_wire)
  assert_true(
    admit_effectful_final_receipt_references(
      chain.run,
      chain.receipt,
      captured,
      preview,
      set_wire,
      member_wires,
      publication_contract_json(foreign),
      65536,
      4096,
      32,
    )
    is Err(ForeignFinalReference("captured_run_cid")),
  )
}

///|
test "Effectful publication index binds the final Receipt, not computation" {
  let chain = captured_run_test_chain()
  let preview = final_test_preview(chain)
  let captured = final_test_captured(chain)
  let (set_wire, member_wires, set_cid) = final_test_receipts(preview)
  let final_wire = final_test_receipt_wire(
    chain.receipt,
    preview,
    set_cid,
    captured,
  )
  let final_receipt = admit_publication_contract(
    "run_receipt", final_wire, 65536, 4096, 32,
  ).unwrap()
  let request = issue_publication_request(
    chain.run,
    [chain.definition],
    "tenant-a",
    ordering_test_cid("1"),
    ordering_test_cid("2"),
    ordering_test_cid("3"),
    "2026-09-18T00:00:00.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let attempt = issue_publication_attempt(
    request,
    chain.run,
    "effect-attempt",
    ordering_test_cid("4"),
    None,
    "2026-09-18T00:00:01.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let binding = seal_publication_contract(
    "durable_result_binding",
    "{\"version\":\"actql-durable-result-binding/0.1\"," +
    "\"run_definition_cid\":\"" +
    publication_contract_identity(chain.run) +
    "\",\"result_definition_cid\":\"" +
    publication_contract_identity(chain.definition) +
    "\",\"invocation_cid\":\"" +
    publication_contract_identity(chain.invocation) +
    "\",\"logical_result_cid\":\"" +
    ordering_test_cid("5") +
    "\",\"result_schema_cid\":\"" +
    ordering_test_cid("6") +
    "\",\"ordering_evidence_cid\":\"" +
    ordering_test_cid("7") +
    "\",\"codec_contract_cid\":\"" +
    ordering_test_cid("8") +
    "\",\"result_fields\":[\"answer\"]," +
    "\"material_generation_cid\":\"" +
    ordering_test_cid("9") +
    "\",\"store_authority_cid\":\"" +
    ordering_test_cid("a") +
    "\",\"effective_retention_policy_cid\":\"" +
    ordering_test_cid("b") +
    "\",\"row_count\":0,\"byte_count\":0," +
    "\"physical_sha256\":\"" +
    "0".repeat(64) +
    "\"}",
    65536,
    4096,
    32,
  ).unwrap()
  let index = issue_public_index_entry(
    chain.run,
    chain.invocation,
    chain.manifest,
    final_receipt,
    captured,
    [binding],
    request,
    attempt,
    "2026-09-18T00:00:02.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    validate_effectful_publication_commit(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      captured,
      preview,
      set_wire,
      member_wires,
      final_wire,
      request,
      attempt,
      index,
      65536,
      4096,
      32,
    )
    is Ok(_),
  )
  let wrong_index = issue_public_index_entry(
    chain.run,
    chain.invocation,
    chain.manifest,
    chain.receipt,
    captured,
    [binding],
    request,
    attempt,
    "2026-09-18T00:00:02.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    validate_effectful_publication_commit(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      captured,
      preview,
      set_wire,
      member_wires,
      final_wire,
      request,
      attempt,
      wrong_index,
      65536,
      4096,
      32,
    )
    is Err(Index(CommitReferenceMismatch("index.run_receipt_cid"))),
  )
}

///|
test "final Effectful Receipt rejects foreign set and Preview references" {
  let chain = captured_run_test_chain()
  let preview = final_test_preview(chain)
  let captured = final_test_captured(chain)
  let (set_wire, member_wires, set_cid) = final_test_receipts(preview)
  let final_wire = final_test_receipt_wire(
    chain.receipt,
    preview,
    set_cid,
    captured,
  )
  for
    (field, expected) in [
      ("effect_preview_cid", effect_preview_semantic_identity(preview)),
      ("effect_set_apply_receipt_cid", set_cid),
    ] {
    let foreign = final_test_reseal_receipt(
      final_wire.replace(
        old="\"" + field + "\":\"" + expected + "\"",
        new="\"" + field + "\":\"" + ordering_test_cid("f") + "\"",
      ),
    )
    let issue = admit_effectful_final_receipt_references(
      chain.run,
      chain.receipt,
      captured,
      preview,
      set_wire,
      member_wires,
      publication_contract_json(foreign),
      65536,
      4096,
      32,
    )
    match issue {
      Err(ForeignFinalReference(actual)) => assert_eq(actual, field)
      _ => abort("Expected the exact foreign final reference")
    }
  }
}

///|
test "final Effectful Receipt cannot rewrite computation evidence" {
  let chain = captured_run_test_chain()
  let preview = final_test_preview(chain)
  let captured = final_test_captured(chain)
  let (set_wire, member_wires, set_cid) = final_test_receipts(preview)
  let final_wire = final_test_receipt_wire(
    chain.receipt,
    preview,
    set_cid,
    captured,
  )
  let original = final_test_receipt_field(
    captured_test_value(final_wire),
    "program_semantics_cid",
  )
  let altered = final_test_reseal_receipt(
    final_wire.replace(
      old="\"program_semantics_cid\":\"" + original + "\"",
      new="\"program_semantics_cid\":\"" + ordering_test_cid("f") + "\"",
    ),
  )
  assert_true(
    admit_effectful_final_receipt_references(
      chain.run,
      chain.receipt,
      captured,
      preview,
      set_wire,
      member_wires,
      publication_contract_json(altered),
      65536,
      4096,
      32,
    )
    is Err(ChangedComputationEvidence),
  )
}

///|
test "final Effectful Receipt rejects a foreign member outcome" {
  let chain = captured_run_test_chain()
  let preview = final_test_preview(chain)
  let captured = final_test_captured(chain)
  let (set_wire, member_wires, set_cid) = final_test_receipts(preview)
  let final_wire = final_test_receipt_wire(
    chain.receipt,
    preview,
    set_cid,
    captured,
  )
  let foreign_member = member_wires[0].replace(
    old="\"effect_preview_cid\":\"" +
      effect_preview_semantic_identity(preview) +
      "\"",
    new="\"effect_preview_cid\":\"" + ordering_test_cid("f") + "\"",
  )
  assert_true(
    admit_effectful_final_receipt_references(
      chain.run,
      chain.receipt,
      captured,
      preview,
      set_wire,
      [foreign_member],
      final_wire,
      65536,
      4096,
      32,
    )
    is Err(SetReceipt(_)),
  )
}

///|
test "final Effectful Receipt rejects an unverified captured context" {
  let chain = captured_run_test_chain()
  let preview = final_test_preview(chain)
  let captured = final_test_captured(chain)
  let original_context = @json.object_field(
    captured_test_value(publication_contract_json(captured)),
    "effect_context",
  ).unwrap()
  let context_cid = final_test_receipt_field(
    original_context, "effect_context_cid",
  )
  let captured_body = @json.object_without_field(
    captured_test_value(publication_contract_json(captured)),
    "captured_run_cid",
  ).unwrap()
  let foreign_captured = seal_publication_contract(
    "captured_run",
    captured_test_wire(captured_body).replace(
      old="\"effect_context_cid\":\"" + context_cid + "\"",
      new="\"effect_context_cid\":\"" + ordering_test_cid("f") + "\"",
    ),
    65536,
    4096,
    32,
  ).unwrap()
  let (set_wire, member_wires, set_cid) = final_test_receipts(preview)
  let final_wire = final_test_receipt_wire(
    chain.receipt,
    preview,
    set_cid,
    foreign_captured,
  )
  assert_true(
    admit_effectful_final_receipt_references(
      chain.run,
      chain.receipt,
      foreign_captured,
      preview,
      set_wire,
      member_wires,
      final_wire,
      65536,
      4096,
      32,
    )
    is Err(ForeignEffectContext),
  )
}

///|
test "final Effectful Receipt requires exact captured plan inventories" {
  let chain = captured_run_test_chain()
  let preview = final_test_preview(chain)
  let (set_wire, member_wires, set_cid) = final_test_receipts(preview)
  for
    (plans, cids) in [
      ("{}", "{\"WriteOne\":\"" + ordering_test_cid("a") + "\"}"),
      ("{\"WriteOne\":{}}", "{}"),
      (
        "{\"WriteOne\":{},\"Foreign\":{}}",
        "{\"WriteOne\":\"" + ordering_test_cid("a") + "\"}",
      ),
      ("{\"WriteOne\":{}}", "{\"WriteOne\":\"" + ordering_test_cid("f") + "\"}"),
    ] {
    let captured = final_test_captured_with_plan_inventory(chain, plans, cids)
    let final_wire = final_test_receipt_wire(
      chain.receipt,
      preview,
      set_cid,
      captured,
    )
    assert_true(
      admit_effectful_final_receipt_references(
        chain.run,
        chain.receipt,
        captured,
        preview,
        set_wire,
        member_wires,
        final_wire,
        65536,
        4096,
        32,
      )
      is Err(ForeignEffectInventory),
    )
  }
}

///|
test "final Effectful Receipt accepts no invented plan for a planless member" {
  let chain = captured_run_test_chain()
  let preview = final_test_preview(chain, plan=false)
  assert_eq(effect_preview_member_plan_cid(preview, 0), None)
  let captured = final_test_captured_with_plan_inventory(chain, "{}", "{}")
  let (set_wire, member_wires, set_cid) = final_test_receipts(preview)
  let final_wire = final_test_receipt_wire(
    chain.receipt,
    preview,
    set_cid,
    captured,
  )
  assert_true(
    admit_effectful_final_receipt_references(
      chain.run,
      chain.receipt,
      captured,
      preview,
      set_wire,
      member_wires,
      final_wire,
      65536,
      4096,
      32,
    )
    is Ok(_),
  )
  let invented = final_test_captured_with_plan_inventory(
    chain,
    "{\"WriteOne\":{}}",
    "{\"WriteOne\":\"" + ordering_test_cid("a") + "\"}",
  )
  let invented_final = final_test_receipt_wire(
    chain.receipt,
    preview,
    set_cid,
    invented,
  )
  assert_true(
    admit_effectful_final_receipt_references(
      chain.run,
      chain.receipt,
      invented,
      preview,
      set_wire,
      member_wires,
      invented_final,
      65536,
      4096,
      32,
    )
    is Err(ForeignEffectInventory),
  )
}

///|
test "Effectful computation chain checks exact captured Result values" {
  let chain = captured_run_test_chain()
  let preview = final_test_preview(chain)
  let captured = final_test_captured(chain)
  assert_true(
    validate_effectful_computation_evidence_chain(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      captured,
      preview,
      65536,
      4096,
      32,
    )
    is Ok(_),
  )
  let holding = effect_source_artifact_holding_cid(
    final_test_source_artifact(chain),
    "WriteOne",
    publication_contract_identity(chain.run),
    ordering_test_cid("d"),
  ).unwrap()
  let foreign_holding = final_test_reseal_captured_context(
    captured,
    holding,
    ordering_test_cid("f"),
  )
  assert_true(
    validate_effectful_computation_evidence_chain(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      foreign_holding,
      preview,
      65536,
      4096,
      32,
    )
    is Err(EvidenceInventoryMismatch("captured_effects")),
  )
  assert_true(
    validate_effect_free_run_evidence_chain(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      captured,
      65536,
      4096,
      32,
    )
    is Err(EvidenceNotEffectFree),
  )
  let altered = final_test_reseal_captured_context(
    captured, "\"value\":7", "\"value\":8",
  )
  assert_true(
    validate_effectful_computation_evidence_chain(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      altered,
      preview,
      65536,
      4096,
      32,
    )
    is Err(EvidenceReferenceMismatch("captured_result_values")),
  )
  let (set_wire, member_wires, set_cid) = final_test_receipts(preview)
  let final_wire = final_test_receipt_wire(
    chain.receipt,
    preview,
    set_cid,
    altered,
  )
  assert_true(
    admit_effectful_final_run_evidence_chain(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      altered,
      preview,
      set_wire,
      member_wires,
      final_wire,
      65536,
      4096,
      32,
    )
    is Err(Computation(EvidenceReferenceMismatch("captured_result_values"))),
  )
}

///|
test "Effectful computation chain rejects a foreign captured plan" {
  let chain = captured_run_test_chain()
  let preview = final_test_preview(chain)
  let captured = final_test_captured_with_plan_inventory(
    chain,
    "{\"WriteOne\":{}}",
    "{\"WriteOne\":\"" + ordering_test_cid("f") + "\"}",
  )
  assert_true(
    validate_effectful_computation_evidence_chain(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      captured,
      preview,
      65536,
      4096,
      32,
    )
    is Err(EvidenceInventoryMismatch("captured_effects")),
  )
}

///|
test "Effectful computation chain rejects a foreign source Artifact" {
  let chain = captured_run_test_chain()
  let preview = final_test_preview(
    chain,
    artifact_cid=Some(ordering_test_cid("f")),
  )
  let captured = final_test_captured(chain)
  assert_true(
    validate_effectful_computation_evidence_chain(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      captured,
      preview,
      65536,
      4096,
      32,
    )
    is Err(EvidenceInventoryMismatch("captured_effects")),
  )
}

///|
test "Effect-free commit chain rejects self-identified substituted rows" {
  let chain = captured_run_test_chain()
  let snapshot = admit_captured_result_snapshot(
    chain.definition,
    chain.artifact,
    "[{\"value\":7}]",
    ["value"],
    65536,
    4096,
    32,
  ).unwrap()
  let captured = issue_effect_free_captured_run(
    chain.run,
    chain.invocation,
    [chain.definition],
    [chain.artifact],
    chain.manifest,
    chain.receipt,
    [snapshot],
    [],
    chain.authoring,
    chain.models,
    65536,
    4096,
    32,
  ).unwrap()
  let altered = final_test_reseal_captured_context(
    captured, "\"value\":7", "\"value\":8",
  )
  assert_true(
    validate_effect_free_run_evidence_chain(
      chain.run,
      chain.invocation,
      [chain.definition],
      [chain.artifact],
      chain.manifest,
      chain.receipt,
      altered,
      65536,
      4096,
      32,
    )
    is Err(EvidenceReferenceMismatch("captured_result_values")),
  )
}
