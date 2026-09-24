///|
pub(all) enum EffectfulFinalReferenceIssue {
  WrongContract(String)
  ComputationAlreadyFinal
  ForeignComputation
  ForeignRun
  ForeignPreview(String)
  ForeignEffectContext
  ForeignEffectInventory
  SetReceipt(EffectSetApplyReceiptBindingIssue)
  FinalReceipt(PublicationContractIssue)
  ForeignFinalReference(String)
  ChangedComputationEvidence
} derive(Debug)

///|
pub(all) enum EffectfulFinalReceiptIssuanceIssue {
  InvalidComputation
  Encoding
  References(EffectfulFinalReferenceIssue)
} derive(Debug)

///|
/// Admit the immutable reference closure of one Effectful final Receipt.
/// This is not a checked Program-kind proof, apply permit, physical outcome
/// admission, or durable Run commit. The standard Host must establish those
/// separately before it may publish a final Effectful outcome.
pub fn admit_effectful_final_receipt_references(
  run_definition : PublicationContract,
  computation_receipt : PublicationContract,
  captured_run : PublicationContract,
  preview : EffectPreviewIdentity,
  set_receipt_wire : String,
  member_receipt_wires : Array[String],
  final_receipt_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectfulFinalReferenceIssue] {
  if run_definition.name != "run_definition" ||
    computation_receipt.name != "run_receipt" ||
    captured_run.name != "captured_run" {
    return Err(WrongContract("run_chain"))
  }
  let computation = computation_receipt.value
  for
    field in [
      "effect_preview_cid", "effect_set_apply_receipt_cid", "captured_run_cid",
    ] {
    if @json.object_field(computation, field) is Some(_) {
      return Err(ComputationAlreadyFinal)
    }
  }
  let captured_receipt = match evidence_object(captured_run.value, "receipt") {
    Ok(value) => value
    Err(_) => return Err(ForeignComputation)
  }
  if !evidence_contract_equal(
      captured_receipt, computation_receipt, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(ForeignComputation)
  }
  if preview.run_identity_cid != run_definition.identity ||
    evidence_string(computation, "compiled_plan_cid") !=
    contract_string(run_definition, "compiled_plan_cid") {
    return Err(ForeignRun)
  }
  for
    (field, expected) in [
      ("program_semantics_cid", preview.program_semantics_cid),
      ("program_definition_cid", preview.program_definition_cid),
      ("invocation_cid", preview.invocation_cid),
      ("compiled_plan_cid", preview.compiled_plan_cid),
      ("check_environment_cid", preview.check_environment_cid),
    ] {
    if evidence_string(computation, field) != Some(expected) {
      return Err(ForeignPreview(field))
    }
  }
  let context = match evidence_object(captured_run.value, "effect_context") {
    Ok(value) => value
    Err(_) => return Err(ForeignPreview("effect_context"))
  }
  if !evidence_identity_valid(
      context, "effect_context_cid", max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(ForeignEffectContext)
  }
  let authoring = match evidence_object(context, "authoring_context") {
    Ok(value) => value
    Err(_) => return Err(ForeignPreview("authoring_context"))
  }
  if !evidence_identity_valid(
      authoring, "authoring_context_cid", max_wire_bytes, max_nodes, max_depth,
    ) ||
    evidence_string(authoring, "authoring_context_cid") !=
    Some(preview.authoring_context_cid) {
    return Err(ForeignPreview("authoring_context_cid"))
  }
  let effects = match @json.object_field(context, "effects") {
    Some(value) =>
      match object_fields(value) {
        Ok(entries) => entries
        Err(_) => return Err(ForeignEffectInventory)
      }
    None => return Err(ForeignEffectInventory)
  }
  if effects.is_empty() ||
    effects.length() != preview.member_effect_ids.length() {
    return Err(ForeignEffectInventory)
  }
  let captured_ids = effects.map(fn(entry) { entry.0 })
  let preview_ids = preview.member_effect_ids.copy()
  captured_ids.sort_by(@canonical.compare_utf16)
  preview_ids.sort_by(@canonical.compare_utf16)
  if captured_ids != preview_ids {
    return Err(ForeignEffectInventory)
  }
  for field in ["effect_plans", "effect_plan_logical_cids"] {
    guard @json.object_field(context, field) is Some(inventory) &&
      evidence_inventory_names(inventory) is Some(names) else {
      return Err(ForeignEffectInventory)
    }
    if !same_names(names, captured_ids) {
      return Err(ForeignEffectInventory)
    }
  }
  let set_receipt = match
    admit_effect_set_apply_receipt_references(
      preview, set_receipt_wire, member_receipt_wires, max_wire_bytes, max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(SetReceipt(issue))
  }
  let final_receipt = match
    admit_publication_contract(
      "run_receipt", final_receipt_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(FinalReceipt(issue))
  }
  for
    (field, expected) in [
      ("effect_preview_cid", preview.semantic_cid),
      ("effect_set_apply_receipt_cid", set_receipt.identity),
      ("captured_run_cid", captured_run.identity),
    ] {
    if contract_string(final_receipt, field) != Some(expected) {
      return Err(ForeignFinalReference(field))
    }
  }
  let final_body = match
    @json.object_without_field(final_receipt.value, "receipt_identity_cid") {
    Some(value) => value
    None => return Err(ChangedComputationEvidence)
  }
  let final_body = match
    @json.object_without_field(final_body, "effect_preview_cid") {
    Some(value) => value
    None => return Err(ChangedComputationEvidence)
  }
  let final_body = match
    @json.object_without_field(final_body, "effect_set_apply_receipt_cid") {
    Some(value) => value
    None => return Err(ChangedComputationEvidence)
  }
  let final_body = match
    @json.object_without_field(final_body, "captured_run_cid") {
    Some(value) => value
    None => return Err(ChangedComputationEvidence)
  }
  let computation_body = match
    @json.object_without_field(computation, "receipt_identity_cid") {
    Some(value) => value
    None => return Err(ChangedComputationEvidence)
  }
  if !evidence_value_equal(
      final_body, computation_body, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(ChangedComputationEvidence)
  }
  Ok(final_receipt)
}

///|
/// Derive the final Receipt body from the admitted computation Receipt.
/// The three later references are inserted only after their closure has been
/// admitted. This does not grant apply authority or commit publication.
pub fn issue_effectful_final_run_receipt(
  run_definition : PublicationContract,
  computation_receipt : PublicationContract,
  captured_run : PublicationContract,
  preview : EffectPreviewIdentity,
  set_receipt_wire : String,
  member_receipt_wires : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectfulFinalReceiptIssuanceIssue] {
  if computation_receipt.name != "run_receipt" {
    return Err(InvalidComputation)
  }
  let set = match
    admit_effect_set_apply_receipt_references(
      preview, set_receipt_wire, member_receipt_wires, max_wire_bytes, max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(References(SetReceipt(issue)))
  }
  let body = match
    @json.object_without_field(
      computation_receipt.value,
      "receipt_identity_cid",
    ) {
    Some(value) => value
    None => return Err(InvalidComputation)
  }
  let body = match
    @json.object_with_string_field(
      body,
      "effect_preview_cid",
      preview.semantic_cid,
    ) {
    Some(value) => value
    None => return Err(InvalidComputation)
  }
  let body = match
    @json.object_with_string_field(
      body,
      "effect_set_apply_receipt_cid",
      set.identity,
    ) {
    Some(value) => value
    None => return Err(InvalidComputation)
  }
  let body = match
    @json.object_with_string_field(
      body,
      "captured_run_cid",
      captured_run.identity,
    ) {
    Some(value) => value
    None => return Err(InvalidComputation)
  }
  let wire = @json.stringify_value(body, max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let issued = match
    seal_publication_contract(
      "run_receipt", wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(References(FinalReceipt(issue)))
  }
  match
    admit_effectful_final_receipt_references(
      run_definition,
      computation_receipt,
      captured_run,
      preview,
      set_receipt_wire,
      member_receipt_wires,
      issued.wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(References(issue))
  }
}
