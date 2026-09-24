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
fn final_test_preview_wire(
  chain : CapturedRunTestChain,
  member_cid : String,
  preview_cid : String,
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
fn final_test_preview(chain : CapturedRunTestChain) -> EffectPreviewIdentity {
  let placeholder = ordering_test_cid("a")
  let (_, members) = match
    derive_effect_preview_identities(
      final_test_preview_wire(chain, placeholder, placeholder),
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
    final_test_preview_wire(chain, members[0], placeholder),
    65536,
    4096,
    32,
  ).unwrap()
  admit_effect_preview_identity(
    final_test_preview_wire(chain, members[0], preview_cid),
    publication_contract_identity(chain.run),
    run_evidence_value_identity(chain.authoring),
    65536,
    4096,
    32,
  ).unwrap()
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
  let context_body_wire = captured_test_wire(context_body).replace(
    old="\"effects\":{}",
    new="\"effects\":{\"WriteOne\":{}}",
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
fn final_test_receipts(
  preview : EffectPreviewIdentity,
) -> (String, Array[String], String) {
  let preview_cid = effect_preview_semantic_identity(preview)
  let member_cid = effect_preview_member_identity(preview, 0).unwrap()
  let member_receipt = seal_publication_contract(
    "effect_apply_receipt",
    "{\"version\":\"actql-effect-apply-receipt/0.1\"," +
    "\"effect_preview_cid\":\"" +
    preview_cid +
    "\",\"effect_member_preview_cid\":\"" +
    member_cid +
    "\",\"applied\":[],\"accepted\":[],\"unknown\":[]," +
    "\"failed\":[],\"unattempted\":[],\"status\":\"applied\"," +
    "\"outcome\":{\"state\":\"applied\",\"result\":{}}}",
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
  assert_true(
    publication_contract_identity(final_receipt) !=
    publication_contract_identity(chain.receipt),
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
