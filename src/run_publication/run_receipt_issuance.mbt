///|
pub(all) enum RunReceiptIssuanceIssue {
  ReceiptIssuanceWrongContract(String)
  ReceiptIssuanceReferenceMismatch(String)
  ReceiptIssuanceInventoryMismatch(String)
  ReceiptIssuanceDuplicateBinding(String)
  ReceiptIssuanceInvalidBinding(String)
  ReceiptIssuanceEncoding
  ReceiptIssuanceContract(PublicationContractIssue)
  ReceiptIssuanceChain(RunPublicationChainIssue)
} derive(Eq, Debug)

///|
priv struct ReceiptBinding {
  name : String
  digest : String
}

///|
fn receipt_sorted_cids(
  values : Array[String],
  field : String,
) -> Result[Array[String], RunReceiptIssuanceIssue] {
  let output : Array[String] = []
  for value in values {
    if !valid_contract_cid(value) {
      return Err(ReceiptIssuanceReferenceMismatch(field))
    }
    if output.contains(value) {
      return Err(ReceiptIssuanceInventoryMismatch(field))
    }
    output.push(value)
  }
  output.sort_by(@canonical.compare_utf16)
  Ok(output)
}

///|
fn receipt_bindings(
  names : Array[String],
  digests : Array[String],
) -> Result[Array[ReceiptBinding], RunReceiptIssuanceIssue] {
  if names.length() != digests.length() {
    return Err(ReceiptIssuanceInventoryMismatch("bindings"))
  }
  let output : Array[ReceiptBinding] = []
  for index = 0; index < names.length(); index = index + 1 {
    let name = names[index]
    let digest = digests[index]
    if name.is_empty() || !valid_digest(digest) {
      return Err(ReceiptIssuanceInvalidBinding(name))
    }
    if output.any(binding => binding.name == name) {
      return Err(ReceiptIssuanceDuplicateBinding(name))
    }
    output.push({ name, digest, })
  }
  output.sort_by((left, right) => {
    @canonical.compare_utf16(left.name, right.name)
  })
  Ok(output)
}

///|
fn receipt_source_identities(
  sources : Array[RunEvidenceValue],
) -> Result[Array[String], RunReceiptIssuanceIssue] {
  let output : Array[String] = []
  for source in sources {
    if source.name != "source_evidence" {
      return Err(ReceiptIssuanceWrongContract("source_evidence"))
    }
    if output.contains(source.identity) {
      return Err(ReceiptIssuanceInventoryMismatch("source_evidence"))
    }
    output.push(source.identity)
  }
  Ok(output)
}

///|
fn receipt_model_identities(
  models : Array[RunEvidenceValue],
) -> Result[Array[String], RunReceiptIssuanceIssue] {
  let output : Array[String] = []
  for model in models {
    if model.name != "model_invocation_evidence" {
      return Err(ReceiptIssuanceWrongContract("model_invocation_evidence"))
    }
    if output.contains(model.identity) {
      return Err(ReceiptIssuanceInventoryMismatch("model_invocation_evidence"))
    }
    output.push(model.identity)
  }
  output.sort_by(@canonical.compare_utf16)
  Ok(output)
}

///|
fn receipt_derivation_identities(
  artifacts : Array[PublicationContract],
) -> Result[Array[String], RunReceiptIssuanceIssue] {
  let output : Array[String] = []
  for artifact in artifacts {
    guard @json.object_field(artifact.value, "provenance_evidence_cids")
      is Some(value) &&
      evidence_string_array(value) is Some(identities) else {
      return Err(ReceiptIssuanceInventoryMismatch("provenance_evidence_cids"))
    }
    for identity in identities {
      if !output.contains(identity) {
        output.push(identity)
      }
    }
  }
  output.sort_by(@canonical.compare_utf16)
  Ok(output)
}

///|
fn emit_receipt_string_array(
  writer : @encode.Writer,
  values : Array[String],
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(writer)
  for value in values {
    @encode.string_value(writer, value)
  }
  @encode.end_array(writer)
}

///|
/// Issue the one final Effect-free Run Receipt from admitted Run evidence and
/// the complete Result Manifest. The issuer derives embedded inventories and
/// evidence references instead of accepting a caller-authored Receipt body.
pub fn issue_effect_free_run_receipt(
  admission : RunPublicationAdmission,
  run_definition : PublicationContract,
  invocation : PublicationContract,
  observation : RunEvidenceValue,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  normalization_journal : RunEvidenceValue,
  compiler_version : String,
  aoa_ir_version : String,
  program_semantics_cid : String,
  aoa_logical_cid : String,
  binding_names : Array[String],
  binding_digests : Array[String],
  source_evidence : Array[RunEvidenceValue],
  model_evidence : Array[RunEvidenceValue],
  barrier_attempt_receipt_cids : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, RunReceiptIssuanceIssue] {
  if run_definition.name != "run_definition" ||
    invocation.name != "run_invocation" ||
    manifest.name != "result_manifest" {
    return Err(ReceiptIssuanceWrongContract("root"))
  }
  if observation.name != "observation_set" {
    return Err(ReceiptIssuanceWrongContract("observation_set"))
  }
  if normalization_journal.name != "normalization_journal" {
    return Err(ReceiptIssuanceWrongContract("normalization_journal"))
  }
  match
    validate_run_publication_chain(
      run_definition, invocation, definitions, artifacts, manifest, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(ReceiptIssuanceChain(issue))
  }
  if contract_string(run_definition, "compiled_plan_cid") !=
    Some(admission.compiled_plan_cid) ||
    contract_string(run_definition, "invocation_template_cid") !=
    Some(admission.template.identity) ||
    contract_string(run_definition, "authorization_context_cid") !=
    Some(admission.authorization_context_cid) {
    return Err(ReceiptIssuanceReferenceMismatch("run_definition"))
  }
  if contract_string(invocation, "invocation_template_cid") !=
    Some(admission.template.identity) ||
    contract_string(invocation, "observation_set_cid") !=
    Some(observation.identity) ||
    contract_string_from_value(observation.value, "invocation_template_cid") !=
    Some(admission.template.identity) {
    return Err(ReceiptIssuanceReferenceMismatch("invocation"))
  }
  guard contract_string_from_value(
      admission.template.value,
      "program_definition_cid",
    )
    is Some(program_definition_cid) &&
    contract_string_from_value(
      admission.template.value,
      "check_environment_cid",
    )
    is Some(check_environment_cid) &&
    contract_string_from_value(observation.value, "consistency")
    is Some(cross_source_consistency) &&
    @json.object_field(observation.value, "source_evidence_cids")
    is Some(observation_source_value) &&
    evidence_string_array(observation_source_value)
    is Some(observation_source_cids) &&
    @json.object_field(manifest.value, "results") is Some(result_artifacts) else {
    return Err(ReceiptIssuanceReferenceMismatch("embedded_evidence"))
  }
  for definition in definitions {
    if contract_string(definition, "program_definition_cid") !=
      Some(program_definition_cid) {
      return Err(ReceiptIssuanceReferenceMismatch("program_definition_cid"))
    }
  }
  let source_cids = match receipt_source_identities(source_evidence) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if source_cids != observation_source_cids {
    return Err(ReceiptIssuanceReferenceMismatch("source_evidence_cids"))
  }
  let model_cids = match receipt_model_identities(model_evidence) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let bindings = match receipt_bindings(binding_names, binding_digests) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let barriers = match
    receipt_sorted_cids(
      barrier_attempt_receipt_cids, "barrier_attempt_receipt_cids",
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let derivations = match receipt_derivation_identities(artifacts) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(ReceiptIssuanceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "aoa_ir_version")
    @encode.string_value(writer, aoa_ir_version)
    @encode.key(writer, "aoa_logical_cid")
    @encode.string_value(writer, aoa_logical_cid)
    @encode.key(writer, "artifact_derivation_evidence_cids")
    emit_receipt_string_array(writer, derivations)
    @encode.key(writer, "barrier_attempt_receipt_cids")
    emit_receipt_string_array(writer, barriers)
    @encode.key(writer, "bindings")
    @encode.begin_array(writer)
    for binding in bindings {
      @encode.begin_object(writer)
      @encode.key(writer, "name")
      @encode.string_value(writer, binding.name)
      @encode.key(writer, "sha256")
      @encode.string_value(writer, binding.digest)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "check_environment_cid")
    @encode.string_value(writer, check_environment_cid)
    @encode.key(writer, "compiled_plan_cid")
    @encode.string_value(writer, admission.compiled_plan_cid)
    @encode.key(writer, "compiler_version")
    @encode.string_value(writer, compiler_version)
    @encode.key(writer, "cross_source_consistency")
    @encode.string_value(writer, cross_source_consistency)
    @encode.key(writer, "external_observation_evidence")
    @encode.begin_array(writer)
    for identity in model_cids {
      @encode.begin_object(writer)
      @encode.key(writer, "evidence_cid")
      @encode.string_value(writer, identity)
      @encode.key(writer, "kind")
      @encode.string_value(writer, "model_invocation")
      @encode.end_object(writer)
    }
    for identity in source_cids {
      @encode.begin_object(writer)
      @encode.key(writer, "evidence_cid")
      @encode.string_value(writer, identity)
      @encode.key(writer, "kind")
      @encode.string_value(writer, "source_lookup")
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "invocation_cid")
    @encode.string_value(writer, invocation.identity)
    @encode.key(writer, "normalization_journal_cid")
    @encode.string_value(writer, normalization_journal.identity)
    @encode.key(writer, "observation_set")
    @json.emit_value(observation.value, writer)
    @encode.key(writer, "observation_set_cid")
    @encode.string_value(writer, observation.identity)
    @encode.key(writer, "prepared_invocation")
    @json.emit_value(admission.prepared.value, writer)
    @encode.key(writer, "program_definition_cid")
    @encode.string_value(writer, program_definition_cid)
    @encode.key(writer, "program_semantics_cid")
    @encode.string_value(writer, program_semantics_cid)
    @encode.key(writer, "result_artifacts")
    @json.emit_value(result_artifacts, writer)
    @encode.key(writer, "result_manifest")
    @json.emit_value(manifest.value, writer)
    @encode.key(writer, "result_manifest_cid")
    @encode.string_value(writer, manifest.identity)
    @encode.key(writer, "run_authorization")
    @json.emit_value(admission.authorization.value, writer)
    @encode.key(writer, "source_evidence")
    @encode.begin_array(writer)
    for source in source_evidence {
      @json.emit_value(source.value, writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "source_evidence_cids")
    emit_receipt_string_array(writer, source_cids)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-run-receipt/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(ReceiptIssuanceEncoding)
  }
  let body = @encode.finish(writer) catch {
    _ => return Err(ReceiptIssuanceEncoding)
  }
  match
    seal_publication_contract(
      "run_receipt", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(ReceiptIssuanceContract(issue))
  }
}
