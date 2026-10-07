///|
pub(all) enum RunEvidenceChainIssue {
  EvidenceRoot(RunPublicationChainIssue)
  EvidenceWrongContract(String)
  EvidenceMissingField(String)
  EvidenceReferenceMismatch(String)
  EvidenceEmbeddedIdentity(String)
  EvidenceInventoryMismatch(String)
  EvidenceNotEffectFree
  EvidenceEncoding
} derive(Eq, Debug)

///|
pub(all) enum PublicationCommitIssue {
  CommitEvidence(RunEvidenceChainIssue)
  CommitResultEvidence(ResultEvidenceSetIssue)
  CommitWrongContract(String)
  CommitReferenceMismatch(String)
  CommitInventoryMismatch
  CommitEncoding
} derive(Eq, Debug)

///|
fn evidence_object(
  value : @json.CanonicalValue,
  field : String,
) -> Result[@json.CanonicalValue, RunEvidenceChainIssue] {
  match @json.object_field(value, field) {
    Some(child) if object_fields(child) is Ok(_) => Ok(child)
    _ => Err(EvidenceMissingField(field))
  }
}

///|
fn validate_durable_result_bindings(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  orderings : Array[PublicationContract],
  retentions : Array[PublicationContract],
  bindings : Array[PublicationContract],
  index_entry : PublicationContract,
) -> Result[Unit, PublicationCommitIssue] {
  let check = start_durable_binding_preparation(
    {
      run_definition,
      invocation,
      definitions,
      artifacts,
      orderings,
      retentions,
      bindings,
      index_entry,
    },
    None,
  )
  while true {
    match check.advance(256) {
      Err(issue) => return Err(issue)
      Ok((true, _)) => {
        check.cancel()
        return Ok(())
      }
      Ok((false, _)) => ()
    }
  } nobreak {
    Err(CommitEncoding)
  }
}

///|
/// Validate a publication commit together with every Result dependency that
/// the 12-field Artifact references. Root-chain validation establishes only
/// structural bindings; product commit paths must use this complete
/// variant so evidence CIDs cannot be dangling placeholders.
pub fn validate_effect_free_publication_commit_with_result_evidence(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  derivations : Array[PublicationContract],
  orderings : Array[PublicationContract],
  retentions : Array[PublicationContract],
  bindings : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured_run : PublicationContract,
  request : PublicationContract,
  attempt : PublicationContract,
  index_entry : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, PublicationCommitIssue] {
  let workspace = if max_nodes > 268435455 {
    2147483647
  } else {
    Int::max(0, max_nodes) * 8
  }
  let preparation = start_effect_free_publication_commit_check(
    run_definition, invocation, definitions, artifacts, derivations, orderings, retentions,
    bindings, manifest, receipt, captured_run, request, attempt, index_entry, max_wire_bytes,
    max_nodes, max_depth, workspace,
  )
  while true {
    match preparation.advance(256) {
      Err(issue) => return Err(issue)
      Ok((true, _)) => return preparation.finish()
      Ok((false, _)) => ()
    }
  } nobreak {
    Err(CommitEncoding)
  }
}

///|
fn evidence_string(value : @json.CanonicalValue, field : String) -> String? {
  optional_string(@json.object_field(value, field))
}

///|
fn evidence_value_equal(
  left : @json.CanonicalValue,
  right : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  guard canonical_value_wire(left, max_wire_bytes, max_nodes, max_depth)
    is Some(left_wire) else {
    return false
  }
  guard canonical_value_wire(right, max_wire_bytes, max_nodes, max_depth)
    is Some(right_wire) else {
    return false
  }
  left_wire == right_wire
}

///|
fn evidence_contract_equal(
  value : @json.CanonicalValue,
  contract : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  canonical_value_wire(value, max_wire_bytes, max_nodes, max_depth) ==
  Some(contract.wire)
}

///|
fn evidence_identity_valid(
  value : @json.CanonicalValue,
  identity_field : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  guard optional_string(@json.object_field(value, identity_field))
    is Some(identity) else {
    return false
  }
  guard @json.object_without_field(value, identity_field) is Some(preimage) else {
    return false
  }
  let expected = @json.cid_value(preimage, max_wire_bytes, max_nodes, max_depth) catch {
    _ => return false
  }
  expected == identity
}

///|
fn evidence_string_array(value : @json.CanonicalValue) -> Array[String]? {
  guard value is @json.Array(frozen) else { return None }
  let output : Array[String] = []
  for item in @json.array_values(frozen) {
    guard string_value(item) is Some(text) else { return None }
    output.push(text)
  }
  Some(output)
}

///|
fn evidence_embedded_identity_array(
  value : @json.CanonicalValue,
  identity_field : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Array[String]? {
  guard value is @json.Array(frozen) else { return None }
  let output : Array[String] = []
  for item in @json.array_values(frozen) {
    if !evidence_identity_valid(
        item, identity_field, max_wire_bytes, max_nodes, max_depth,
      ) {
      return None
    }
    guard optional_string(@json.object_field(item, identity_field))
      is Some(identity) else {
      return None
    }
    output.push(identity)
  }
  Some(output)
}

///|
fn evidence_empty_object(value : @json.CanonicalValue?) -> Bool {
  match value {
    Some(child) =>
      object_fields(child).map(fields => fields.is_empty()).unwrap_or(false)
    None => false
  }
}

///|
fn evidence_inventory_names(value : @json.CanonicalValue) -> Array[String]? {
  guard object_fields(value) is Ok(fields) else { return None }
  let names : Array[String] = []
  for (name, _) in fields {
    if name.is_empty() {
      return None
    }
    names.push(name)
  }
  Some(names)
}

///|
fn same_names(left : Array[String], right : Array[String]) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for name in left {
    if !right.contains(name) {
      return false
    }
  }
  true
}

///|
fn effect_context_preview_inventory_matches(
  context : @json.CanonicalValue,
  preview : EffectPreviewIdentity,
  invocation_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  guard @json.object_field(context, "effects") is Some(effects) &&
    evidence_inventory_names(effects) is Some(effect_names) &&
    !effect_names.is_empty() &&
    same_names(effect_names, preview.member_effect_ids) else {
    return false
  }
  let plan_names : Array[String] = []
  guard @json.object_field(context, "effect_source_artifacts")
    is Some(source_artifacts) &&
    @json.object_field(context, "effect_source_holding_cids")
    is Some(source_holdings) &&
    @json.object_field(context, "effect_source_local_inventory")
    is Some(local_inventory) &&
    evidence_inventory_names(source_artifacts) is Some(source_names) &&
    evidence_inventory_names(source_holdings) is Some(holding_names) &&
    evidence_inventory_names(local_inventory) is Some(local_names) else {
    return false
  }
  let expected_source_names : Array[String] = []
  for index in 0..<preview.member_effect_ids.length() {
    if effect_preview_member_plan_cid(preview, index) is Some(_) {
      plan_names.push(preview.member_effect_ids[index])
    }
  }
  guard @json.object_field(context, "effect_plans") is Some(plans) &&
    evidence_inventory_names(plans) is Some(captured_plan_names) &&
    same_names(captured_plan_names, plan_names) &&
    @json.object_field(context, "effect_plan_logical_cids") is Some(plan_cids) &&
    evidence_inventory_names(plan_cids) is Some(captured_cid_names) &&
    same_names(captured_cid_names, plan_names) else {
    return false
  }
  for index in 0..<preview.member_effect_ids.length() {
    if effect_preview_member_plan_cid(preview, index) is Some(expected) &&
      evidence_string(plan_cids, preview.member_effect_ids[index]) !=
      Some(expected) {
      return false
    }
    if effect_preview_member_relation_source(preview, index) is Some(source) {
      let effect_id = preview.member_effect_ids[index]
      expected_source_names.push(effect_id)
      guard effect_preview_member_source_binding_cid(preview, index)
        is Some(source_binding_cid) &&
        @json.object_field(source_artifacts, effect_id) is Some(artifact) &&
        evidence_identity_valid(
          artifact, "result_artifact_cid", max_wire_bytes, max_nodes, max_depth,
        ) &&
        evidence_string(artifact, "version") ==
        Some("actql-effect-source-artifact/0.1") &&
        evidence_string(artifact, "result_artifact_cid") is Some(physical_cid) &&
        evidence_string(artifact, "source_binding_cid") ==
        Some(source_binding_cid) &&
        evidence_string(artifact, "invocation_cid") == Some(invocation_cid) &&
        evidence_string(source_holdings, effect_id) is Some(holding_cid) &&
        evidence_string(artifact, "store_authority_cid")
        is Some(store_authority_cid) &&
        effect_source_holding_identity(
          physical_cid,
          effect_id,
          preview.run_identity_cid,
          store_authority_cid,
        ) ==
        Some(holding_cid) else {
        return false
      }
      guard @json.object_field(local_inventory, effect_id) is Some(local_source) &&
        admitted_nested_local_contract(
          source_artifacts, effect_id, "effect_source_artifact", max_wire_bytes,
          max_nodes, max_depth,
        )
        is Some(physical) &&
        effect_source_artifact_relation_source(physical) == Some(source) &&
        captured_local_effect_source_matches_preview(
          preview, index, physical, local_source, max_wire_bytes, max_nodes, max_depth,
        ) else {
        return false
      }
    }
  }
  same_names(source_names, expected_source_names) &&
  same_names(holding_names, expected_source_names) &&
  same_names(local_names, expected_source_names)
}

///|
fn publication_inventory_matches(
  request : PublicationContract,
  definitions : Array[PublicationContract],
) -> Bool {
  let check = start_publication_inventory_preparation(
    request,
    definitions,
    None,
  )
  while true {
    match check.advance(256) {
      Err(_) => return false
      Ok((true, _)) => return check.finish().unwrap()
      Ok((false, _)) => ()
    }
  } nobreak {
    false
  }
}

///|
/// Validate the computation evidence shared by Effect-free and Effectful Runs.
/// The latter still requires a separately admitted apply outcome before a
/// final Receipt or publication commit can be accepted.
fn computation_evidence_prelude(
  inputs : ComputationEvidenceInputs,
) -> Result[ComputationEvidencePrelude, RunEvidenceChainIssue] {
  let {
    run_definition,
    invocation,
    definitions,
    artifacts,
    manifest,
    receipt,
    captured_run,
    preview,
    max_wire_bytes,
    max_nodes,
    max_depth,
  } = inputs
  match
    validate_run_publication_chain(
      run_definition, invocation, definitions, artifacts, manifest, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(EvidenceRoot(issue))
  }
  if receipt.name != "run_receipt" {
    return Err(EvidenceWrongContract("run_receipt"))
  }
  if captured_run.name != "captured_run" {
    return Err(EvidenceWrongContract("captured_run"))
  }
  let receipt_value = receipt.value
  if @json.object_field(receipt_value, "effect_preview_cid") is Some(_) ||
    @json.object_field(receipt_value, "effect_set_apply_receipt_cid") is Some(_) ||
    @json.object_field(receipt_value, "captured_run_cid") is Some(_) {
    return match preview {
      None => Err(EvidenceNotEffectFree)
      Some(_) => Err(EvidenceReferenceMismatch("computation_receipt"))
    }
  }
  if evidence_string(receipt_value, "invocation_cid") !=
    Some(invocation.identity) {
    return Err(EvidenceReferenceMismatch("invocation_cid"))
  }
  if evidence_string(receipt_value, "compiled_plan_cid") !=
    contract_string(run_definition, "compiled_plan_cid") {
    return Err(EvidenceReferenceMismatch("compiled_plan_cid"))
  }
  if preview is Some(effect_preview) {
    for
      (field, expected) in [
        ("program_semantics_cid", effect_preview.program_semantics_cid),
        ("program_definition_cid", effect_preview.program_definition_cid),
        ("invocation_cid", effect_preview.invocation_cid),
        ("compiled_plan_cid", effect_preview.compiled_plan_cid),
        ("check_environment_cid", effect_preview.check_environment_cid),
      ] {
      if evidence_string(receipt_value, field) != Some(expected) {
        return Err(EvidenceReferenceMismatch("preview." + field))
      }
    }
    if effect_preview.run_identity_cid != run_definition.identity {
      return Err(EvidenceReferenceMismatch("preview.run_identity_cid"))
    }
  }
  if evidence_string(receipt_value, "result_manifest_cid") !=
    Some(manifest.identity) {
    return Err(EvidenceReferenceMismatch("result_manifest_cid"))
  }
  let first_definition = definitions[0]
  let program = contract_string(first_definition, "program_definition_cid")
  if evidence_string(receipt_value, "program_definition_cid") != program {
    return Err(EvidenceReferenceMismatch("program_definition_cid"))
  }
  for definition in definitions {
    if contract_string(definition, "program_definition_cid") != program {
      return Err(EvidenceReferenceMismatch("program_definition_cid"))
    }
  }
  let prepared = match evidence_object(receipt_value, "prepared_invocation") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !evidence_identity_valid(
      prepared, "prepared_invocation_cid", max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(EvidenceEmbeddedIdentity("prepared_invocation_cid"))
  }
  if evidence_string(prepared, "invocation_template_cid") !=
    contract_string(invocation, "invocation_template_cid") ||
    evidence_string(prepared, "compiled_plan_cid") !=
    contract_string(run_definition, "compiled_plan_cid") {
    return Err(EvidenceReferenceMismatch("prepared_invocation"))
  }
  let authorization = match
    evidence_object(receipt_value, "run_authorization") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !evidence_identity_valid(
      authorization, "run_authorization_cid", max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(EvidenceEmbeddedIdentity("run_authorization_cid"))
  }
  if evidence_string(authorization, "prepared_invocation_cid") !=
    evidence_string(prepared, "prepared_invocation_cid") ||
    evidence_string(authorization, "execution_context_cid") !=
    evidence_string(prepared, "execution_context_cid") ||
    evidence_string(authorization, "host_policy_cid") !=
    evidence_string(prepared, "host_policy_cid") {
    return Err(EvidenceReferenceMismatch("run_authorization"))
  }
  if evidence_string(prepared, "policy_decision") != Some("allow") ||
    evidence_string(authorization, "decision") != Some("allowed") {
    return Err(EvidenceReferenceMismatch("run_authorization"))
  }
  let observation = match evidence_object(receipt_value, "observation_set") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !evidence_identity_valid(
      observation, "observation_set_cid", max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(EvidenceEmbeddedIdentity("observation_set_cid"))
  }
  if evidence_string(observation, "invocation_template_cid") !=
    contract_string(invocation, "invocation_template_cid") ||
    evidence_string(observation, "observation_set_cid") !=
    contract_string(invocation, "observation_set_cid") ||
    evidence_string(receipt_value, "observation_set_cid") !=
    contract_string(invocation, "observation_set_cid") {
    return Err(EvidenceReferenceMismatch("observation_set"))
  }
  let embedded_manifest = match
    evidence_object(receipt_value, "result_manifest") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !evidence_contract_equal(
      embedded_manifest, manifest, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(EvidenceReferenceMismatch("result_manifest"))
  }
  guard @json.object_field(receipt_value, "result_artifacts")
    is Some(receipt_artifacts) else {
    return Err(EvidenceMissingField("result_artifacts"))
  }
  guard @json.object_field(manifest.value, "results") is Some(manifest_results) else {
    return Err(EvidenceMissingField("results"))
  }
  if !evidence_value_equal(
      receipt_artifacts, manifest_results, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(EvidenceInventoryMismatch("result_artifacts"))
  }
  guard @json.object_field(receipt_value, "source_evidence")
    is Some(source_evidence) else {
    return Err(EvidenceMissingField("source_evidence"))
  }
  guard @json.object_field(receipt_value, "source_evidence_cids")
    is Some(source_evidence_cids) else {
    return Err(EvidenceMissingField("source_evidence_cids"))
  }
  let embedded_source_cids = evidence_embedded_identity_array(
    source_evidence, "source_evidence_cid", max_wire_bytes, max_nodes, max_depth,
  )
  let listed_source_cids = evidence_string_array(source_evidence_cids)
  if embedded_source_cids is None || embedded_source_cids != listed_source_cids {
    return Err(EvidenceReferenceMismatch("source_evidence_cids"))
  }
  guard @json.object_field(receipt_value, "external_observation_evidence")
    is Some(@json.Array(external_frozen)) else {
    return Err(EvidenceMissingField("external_observation_evidence"))
  }
  let external_source_cids : Array[String] = []
  let external_model_cids : Array[String] = []
  for item in @json.array_values(external_frozen) {
    guard evidence_string(item, "kind") is Some(kind) &&
      evidence_string(item, "evidence_cid") is Some(identity) else {
      return Err(EvidenceReferenceMismatch("external_observation_evidence"))
    }
    match kind {
      "source_lookup" => external_source_cids.push(identity)
      "model_invocation" => external_model_cids.push(identity)
      _ =>
        return Err(EvidenceReferenceMismatch("external_observation_evidence"))
    }
  }
  if Some(external_source_cids) != listed_source_cids {
    return Err(EvidenceReferenceMismatch("external_source_evidence"))
  }
  let captured_value = captured_run.value
  let captured_receipt = match evidence_object(captured_value, "receipt") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !evidence_contract_equal(
      captured_receipt, receipt, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(EvidenceReferenceMismatch("receipt"))
  }
  let effect_context = match evidence_object(captured_value, "effect_context") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ effect_context, program, external_model_cids, manifest_results, })
}

///|
fn computation_evidence_capture_inventory(
  inputs : ComputationEvidenceInputs,
  prelude : ComputationEvidencePrelude,
) -> Result[(@json.CanonicalValue, @json.CanonicalValue), RunEvidenceChainIssue] {
  let { invocation, preview, max_wire_bytes, max_nodes, max_depth, .. } = inputs
  let { effect_context, manifest_results, .. } = prelude
  if !captured_effect_context_dependencies_valid(
      effect_context, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(EvidenceInventoryMismatch("effect_dependency_inventory"))
  }
  match preview {
    None =>
      if !evidence_empty_object(@json.object_field(effect_context, "effects")) ||
        !evidence_empty_object(
          @json.object_field(effect_context, "effect_source_artifacts"),
        ) ||
        !evidence_empty_object(
          @json.object_field(effect_context, "effect_source_holding_cids"),
        ) ||
        !evidence_empty_object(
          @json.object_field(effect_context, "effect_source_local_inventory"),
        ) ||
        !evidence_empty_object(
          @json.object_field(effect_context, "effect_plans"),
        ) ||
        !evidence_empty_object(
          @json.object_field(effect_context, "effect_plan_logical_cids"),
        ) {
        return Err(EvidenceNotEffectFree)
      }
    Some(effect_preview) =>
      if !effect_context_preview_inventory_matches(
          effect_context,
          effect_preview,
          invocation.identity,
          max_wire_bytes,
          max_nodes,
          max_depth,
        ) {
        return Err(EvidenceInventoryMismatch("captured_effects"))
      }
  }
  guard @json.object_field(effect_context, "result_artifacts")
    is Some(captured_artifacts) else {
    return Err(EvidenceMissingField("result_artifacts"))
  }
  if !evidence_value_equal(
      captured_artifacts, manifest_results, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(EvidenceInventoryMismatch("captured_result_artifacts"))
  }
  let declared_names = evidence_inventory_names(manifest_results).unwrap()
  for field in ["result_values", "result_fields"] {
    guard @json.object_field(effect_context, field) is Some(inventory) else {
      return Err(EvidenceMissingField(field))
    }
    guard evidence_inventory_names(inventory) is Some(names) else {
      return Err(EvidenceInventoryMismatch(field))
    }
    if !same_names(declared_names, names) {
      return Err(EvidenceInventoryMismatch(field))
    }
  }
  guard @json.object_field(effect_context, "result_values") is Some(values) &&
    @json.object_field(effect_context, "result_fields") is Some(field_inventory) else {
    return Err(EvidenceMissingField("captured_results"))
  }
  Ok((values, field_inventory))
}

///|
fn computation_evidence_suffix(
  inputs : ComputationEvidenceInputs,
  prelude : ComputationEvidencePrelude,
) -> Result[Unit, RunEvidenceChainIssue] {
  let { preview, max_wire_bytes, max_nodes, max_depth, .. } = inputs
  let { effect_context, program, external_model_cids, .. } = prelude
  let authoring = match evidence_object(effect_context, "authoring_context") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !evidence_identity_valid(
      authoring, "authoring_context_cid", max_wire_bytes, max_nodes, max_depth,
    ) ||
    evidence_string(authoring, "program_definition_cid") != program {
    return Err(EvidenceEmbeddedIdentity("authoring_context_cid"))
  }
  if preview is Some(effect_preview) &&
    evidence_string(authoring, "authoring_context_cid") !=
    Some(effect_preview.authoring_context_cid) {
    return Err(EvidenceReferenceMismatch("preview.authoring_context_cid"))
  }
  guard @json.object_field(effect_context, "model_invocation_evidence")
    is Some(model_evidence) else {
    return Err(EvidenceMissingField("model_invocation_evidence"))
  }
  guard @json.object_field(effect_context, "model_invocation_evidence_cids")
    is Some(model_evidence_cids) else {
    return Err(EvidenceMissingField("model_invocation_evidence_cids"))
  }
  let embedded_model_cids = evidence_embedded_identity_array(
    model_evidence, "model_invocation_evidence_cid", max_wire_bytes, max_nodes, max_depth,
  )
  let listed_model_cids = evidence_string_array(model_evidence_cids)
  if embedded_model_cids is None || embedded_model_cids != listed_model_cids {
    return Err(EvidenceReferenceMismatch("model_invocation_evidence_cids"))
  }
  let captured_model_cids = embedded_model_cids.unwrap()
  captured_model_cids.sort_by(@canonical.compare_utf16)
  external_model_cids.sort_by(@canonical.compare_utf16)
  if captured_model_cids != external_model_cids {
    return Err(EvidenceReferenceMismatch("external_model_evidence"))
  }
  Ok(())
}

///|
fn validate_computation_run_evidence_chain(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured_run : PublicationContract,
  preview : EffectPreviewIdentity?,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, RunEvidenceChainIssue] {
  let workspace = if max_nodes > 268435455 { 2147483647 } else { max_nodes * 8 }
  let preparation = start_computation_evidence_check(
    {
      run_definition,
      invocation,
      definitions,
      artifacts,
      manifest,
      receipt,
      captured_run,
      preview,
      max_wire_bytes,
      max_nodes,
      max_depth,
    },
    workspace,
  )
  while true {
    match preparation.advance(256) {
      Err(issue) => return Err(issue)
      Ok((true, _)) => return preparation.finish()
      Ok((false, _)) => ()
    }
  } nobreak {
    Err(EvidenceEncoding)
  }
}

///|
/// Validate every retained computation dependency before Effect-free commit.
pub fn validate_effect_free_run_evidence_chain(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured_run : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, RunEvidenceChainIssue] {
  validate_computation_run_evidence_chain(
    run_definition,
    invocation,
    definitions,
    artifacts,
    manifest,
    receipt,
    captured_run,
    None,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Validate a captured Effectful computation, including its exact Preview
/// inventory. This does not prove physical Effect Plan payloads, current
/// authority, apply outcomes, or a durable publication commit.
pub fn validate_effectful_computation_evidence_chain(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  computation_receipt : PublicationContract,
  captured_run : PublicationContract,
  preview : EffectPreviewIdentity,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, RunEvidenceChainIssue] {
  validate_computation_run_evidence_chain(
    run_definition,
    invocation,
    definitions,
    artifacts,
    manifest,
    computation_receipt,
    captured_run,
    Some(preview),
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Validate the immutable publication intent and the exact index entry that a
/// Store adapter proposes to make visible. The adapter still owns durability,
/// fencing, and atomic index installation; it cannot redefine this binding.
pub fn validate_effect_free_publication_commit(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured_run : PublicationContract,
  request : PublicationContract,
  attempt : PublicationContract,
  index_entry : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, PublicationCommitIssue] {
  match
    validate_effect_free_run_evidence_chain(
      run_definition, invocation, definitions, artifacts, manifest, receipt, captured_run,
      max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(CommitEvidence(issue))
  }
  validate_publication_commit_references(
    run_definition, invocation, definitions, manifest, receipt, captured_run, request,
    attempt, index_entry,
  )
}

///|
/// The index binding is common to both Run kinds. The caller must first
/// validate the kind-specific evidence chain and all Result dependencies.
fn validate_publication_commit_references(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured_run : PublicationContract,
  request : PublicationContract,
  attempt : PublicationContract,
  index_entry : PublicationContract,
) -> Result[Unit, PublicationCommitIssue] {
  let check = start_publication_reference_preparation(
    {
      run_definition,
      invocation,
      definitions,
      manifest,
      receipt,
      captured_run,
      request,
      attempt,
      index_entry,
    },
    None,
  )
  while true {
    match check.advance(256) {
      Err(issue) => return Err(issue)
      Ok((true, _)) => {
        check.cancel()
        return Ok(())
      }
      Ok((false, _)) => ()
    }
  } nobreak {
    Err(CommitEncoding)
  }
}
