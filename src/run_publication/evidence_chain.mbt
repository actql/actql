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
  if bindings.length() != definitions.length() || bindings.is_empty() {
    return Err(CommitInventoryMismatch)
  }
  let identities : Array[String] = []
  let definition_cids : Array[String] = []
  for binding in bindings {
    if binding.name != "durable_result_binding" {
      return Err(CommitWrongContract("durable_result_binding"))
    }
    if identities.contains(binding.identity) {
      return Err(CommitInventoryMismatch)
    }
    identities.push(binding.identity)
    guard contract_string(binding, "result_definition_cid")
      is Some(definition_cid) else {
      return Err(CommitReferenceMismatch("binding.result_definition_cid"))
    }
    if definition_cids.contains(definition_cid) {
      return Err(CommitInventoryMismatch)
    }
    definition_cids.push(definition_cid)
    if !definitions.any(definition => definition.identity == definition_cid) {
      return Err(CommitInventoryMismatch)
    }
    let matching_artifacts = artifacts.filter(artifact => {
      contract_string(artifact, "result_definition_cid") == Some(definition_cid)
    })
    if matching_artifacts.length() != 1 {
      return Err(CommitInventoryMismatch)
    }
    let artifact = matching_artifacts[0]
    guard contract_string(artifact, "ordering_evidence_cid")
      is Some(ordering_cid) &&
      orderings.any(ordering => ordering.identity == ordering_cid) else {
      return Err(CommitReferenceMismatch("binding.ordering_evidence_cid"))
    }
    guard contract_string(artifact, "effective_retention_policy_cid")
      is Some(retention_cid) &&
      retentions.any(retention => retention.identity == retention_cid) else {
      return Err(
        CommitReferenceMismatch("binding.effective_retention_policy_cid"),
      )
    }
    guard contract_string(artifact, "logical_result_cid")
      is Some(logical_result_cid) &&
      contract_string(artifact, "result_schema_cid") is Some(result_schema_cid) else {
      return Err(CommitReferenceMismatch("artifact.identity"))
    }
    for
      (field, expected) in [
        ("run_definition_cid", run_definition.identity),
        ("invocation_cid", invocation.identity),
        ("logical_result_cid", logical_result_cid),
        ("result_schema_cid", result_schema_cid),
        ("ordering_evidence_cid", ordering_cid),
        ("effective_retention_policy_cid", retention_cid),
      ] {
      if contract_string(binding, field) != Some(expected) {
        return Err(CommitReferenceMismatch("binding." + field))
      }
    }
    if contract_count(binding, "row_count") !=
      contract_count(artifact, "actual_row_count") {
      return Err(CommitReferenceMismatch("binding.row_count"))
    }
  }
  identities.sort_by(@canonical.compare_utf16)
  guard @json.object_field(index_entry.value, "durable_result_binding_cids")
    is Some(index_bindings) &&
    evidence_string_array(index_bindings) is Some(index_identities) else {
    return Err(CommitReferenceMismatch("index.durable_result_binding_cids"))
  }
  index_identities.sort_by(@canonical.compare_utf16)
  if index_identities != identities {
    return Err(CommitInventoryMismatch)
  }
  Ok(())
}

///|
/// Validate a publication commit together with every Result dependency that
/// the 12-field Artifact references. The older root-chain validator remains a
/// bounded structural primitive; product commit paths must use this complete
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
  match
    validate_result_evidence_set(
      definitions, artifacts, derivations, orderings, retentions,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(CommitResultEvidence(issue))
  }
  match
    validate_durable_result_bindings(
      run_definition, invocation, definitions, artifacts, orderings, retentions,
      bindings, index_entry,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  validate_effect_free_publication_commit(
    run_definition, invocation, definitions, artifacts, manifest, receipt, captured_run,
    request, attempt, index_entry, max_wire_bytes, max_nodes, max_depth,
  )
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
) -> Bool {
  guard @json.object_field(context, "effects") is Some(effects) &&
    evidence_inventory_names(effects) is Some(effect_names) &&
    !effect_names.is_empty() &&
    same_names(effect_names, preview.member_effect_ids) else {
    return false
  }
  let plan_names : Array[String] = []
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
  }
  true
}

///|
fn publication_inventory_matches(
  request : PublicationContract,
  definitions : Array[PublicationContract],
) -> Bool {
  guard @json.object_field(request.value, "inventory")
    is Some(@json.Array(frozen)) else {
    return false
  }
  let values = @json.array_values(frozen)
  if values.length() != definitions.length() {
    return false
  }
  for value in values {
    guard validate_named_cid_object(
        value, "result_name", "result_definition_cid",
      )
      is Some(item) else {
      return false
    }
    let matches = definitions.filter(fn(definition) {
      contract_string(definition, "result_name") == Some(item.name) &&
      definition.identity == item.cid
    })
    if matches.length() != 1 {
      return false
    }
  }
  true
}

///|
/// Validate the computation evidence shared by Effect-free and Effectful Runs.
/// The latter still requires a separately admitted apply outcome before a
/// final Receipt or publication commit can be accepted.
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
  if !evidence_identity_valid(
      effect_context, "effect_context_cid", max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(EvidenceEmbeddedIdentity("effect_context_cid"))
  }
  match preview {
    None =>
      if !evidence_empty_object(@json.object_field(effect_context, "effects")) ||
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
          effect_context, effect_preview,
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
  for artifact in artifacts {
    guard contract_string(artifact, "result_definition_cid")
      is Some(definition_cid) else {
      return Err(EvidenceInventoryMismatch("captured_results"))
    }
    let matching = definitions.filter(fn(definition) {
      definition.identity == definition_cid
    })
    guard matching.length() == 1 &&
      contract_string(matching[0], "result_name") is Some(name) &&
      @json.object_field(values, name) is Some(row_value) &&
      row_value is @json.Array(frozen_rows) &&
      @json.object_field(field_inventory, name) is Some(field_value) &&
      evidence_string_array(field_value) is Some(fields) else {
      return Err(EvidenceInventoryMismatch("captured_results"))
    }
    let rows = @json.array_values(frozen_rows)
    if !captured_fields_valid(rows, fields) ||
      contract_count(artifact, "actual_row_count") !=
      Some(rows.length().to_int64()) ||
      captured_relation_cid(row_value, max_wire_bytes, max_nodes, max_depth) !=
      contract_string(artifact, "logical_result_cid") {
      return Err(EvidenceReferenceMismatch("captured_result_values"))
    }
  }
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
  if request.name != "publication_request" {
    return Err(CommitWrongContract("publication_request"))
  }
  if attempt.name != "publication_attempt" {
    return Err(CommitWrongContract("publication_attempt"))
  }
  if index_entry.name != "public_index_entry" {
    return Err(CommitWrongContract("public_index_entry"))
  }
  if evidence_string(request.value, "run_definition_cid") !=
    Some(run_definition.identity) {
    return Err(CommitReferenceMismatch("request.run_definition_cid"))
  }
  if !publication_inventory_matches(request, definitions) {
    return Err(CommitInventoryMismatch)
  }
  if evidence_string(attempt.value, "publication_request_cid") !=
    Some(request.identity) ||
    evidence_string(attempt.value, "run_definition_cid") !=
    Some(run_definition.identity) {
    return Err(CommitReferenceMismatch("publication_attempt"))
  }
  for
    (field, expected) in [
      ("tenant_id", evidence_string(request.value, "tenant_id")),
      (
        "authority_scope_cid",
        evidence_string(request.value, "authority_scope_cid"),
      ),
      ("run_definition_cid", Some(run_definition.identity)),
      ("invocation_cid", Some(invocation.identity)),
      ("result_manifest_cid", Some(manifest.identity)),
      ("run_receipt_cid", Some(receipt.identity)),
      ("captured_run_cid", Some(captured_run.identity)),
      ("publication_request_cid", Some(request.identity)),
      ("publication_attempt_cid", Some(attempt.identity)),
    ] {
    if expected is None || evidence_string(index_entry.value, field) != expected {
      return Err(CommitReferenceMismatch("index." + field))
    }
  }
  Ok(())
}
