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
pub(all) enum EffectfulFinalChainIssue {
  Computation(RunEvidenceChainIssue)
  FinalReferences(EffectfulFinalReferenceIssue)
} derive(Debug)

///|
pub(all) enum EffectfulPublicationCommitIssue {
  ResultEvidence(ResultEvidenceSetIssue)
  DurableBinding(PublicationCommitIssue)
  FinalChain(EffectfulFinalChainIssue)
  Index(PublicationCommitIssue)
} derive(Debug)

///|
/// Retained facts from the existing complete admission. This is immutable
/// publication DATA, not current apply authority, Store commit or physical ACK.
/// Arrays are snapshotted once; later publication checks borrow these originals
/// instead of admitting the computation and member receipt wires again.
pub struct EffectfulFinalRunEvidence {
  priv run_definition : PublicationContract
  priv invocation : PublicationContract
  priv definitions : Array[PublicationContract]
  priv artifacts : Array[PublicationContract]
  priv _observed_derivations : Array[PublicationContract]
  priv orderings : Array[PublicationContract]
  priv retentions : Array[PublicationContract]
  priv manifest : PublicationContract
  priv declared_results : Array[String]
  priv captured_run : PublicationContract
  priv final_receipt : PublicationContract
  priv outcomes : EffectSetApplyReceiptEvidence
}

///|
pub fn admit_retained_effectful_final_run_evidence(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  derivations : Array[PublicationContract],
  orderings : Array[PublicationContract],
  retentions : Array[PublicationContract],
  manifest : PublicationContract,
  computation_receipt : PublicationContract,
  captured_run : PublicationContract,
  preview : EffectPreviewIdentity,
  set_receipt_wire : String,
  member_receipt_wires : Array[String],
  final_receipt_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  computation? : RetainedEffectfulComputation? = None,
) -> Result[EffectfulFinalRunEvidence, EffectfulPublicationCommitIssue] {
  let definitions = definitions.copy()
  let artifacts = artifacts.copy()
  let derivations = derivations.copy()
  let orderings = orderings.copy()
  let retentions = retentions.copy()
  match
    validate_result_evidence_set(
      definitions, artifacts, derivations, orderings, retentions,
    ) {
    Err(issue) => return Err(ResultEvidence(issue))
    Ok(_) => ()
  }
  let (final_receipt, outcomes) = match computation {
    None =>
      match
        admit_effectful_final_run_evidence_with_outcomes(
          run_definition, invocation, definitions, artifacts, manifest, computation_receipt,
          captured_run, preview, set_receipt_wire, member_receipt_wires, final_receipt_wire,
          max_wire_bytes, max_nodes, max_depth,
        ) {
        Err(issue) => return Err(FinalChain(issue))
        Ok(value) => value
      }
    Some(original) => {
      guard retained_effectful_computation_matches(
        original, run_definition, invocation, definitions, artifacts, manifest, computation_receipt,
        captured_run, preview, max_wire_bytes, max_nodes, max_depth,
      ) else {
        return Err(FinalChain(FinalReferences(ForeignComputation)))
      }
      // SAME fully checked computation/rows; final outcomes still undergo
      // all original receipt/reference validators. No row reparse/reexecution.
      match
        admit_effectful_final_receipt_evidence(
          run_definition,
          computation_receipt,
          captured_run,
          original.inputs.preview.unwrap(),
          set_receipt_wire,
          member_receipt_wires,
          final_receipt_wire,
          max_wire_bytes,
          max_nodes,
          max_depth,
        ) {
        Err(issue) => return Err(FinalChain(FinalReferences(issue)))
        Ok(value) => value
      }
    }
  }
  let declared_results = match manifest_result_names(manifest) {
    Err(_) =>
      return Err(
        FinalChain(Computation(EvidenceInventoryMismatch("manifest results"))),
      )
    Ok(value) => value
  }
  Ok({
    run_definition,
    invocation,
    definitions,
    artifacts,
    _observed_derivations: derivations,
    orderings,
    retentions,
    manifest,
    declared_results,
    captured_run,
    final_receipt,
    outcomes,
  })
}

///|
pub fn effectful_final_run_evidence_receipt(
  value : EffectfulFinalRunEvidence,
) -> PublicationContract {
  value.final_receipt
}

///|
pub fn effectful_final_run_evidence_outcomes(
  value : EffectfulFinalRunEvidence,
) -> EffectSetApplyReceiptEvidence {
  value.outcomes
}

///|
/// Same immutable Run definition, independently of the caller's current
/// original admission/compilation binding or durable Store observation.
pub fn effectful_final_run_evidence_matches_definition(
  value : EffectfulFinalRunEvidence,
  definition : PublicationContract,
) -> Bool {
  definition.name == "run_definition" &&
  definition.identity == value.run_definition.identity
}

///|
/// The same original manifest supplies declared Results, while the retained
/// complete Set supplies exactly the actual unknown Effect partition.
pub fn effectful_final_run_evidence_reconciliation_state(
  value : EffectfulFinalRunEvidence,
  updated_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, RunStateIssue] {
  let run_id = match run_definition_run_id(value.run_definition) {
    Err(_) => return Err(InvalidRunId)
    Ok(value) => value
  }
  issue_admitted_effect_reconciliation_run_state_wire(
    value.outcomes,
    run_id,
    updated_at,
    value.declared_results,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Preserve the original Run and declared Results of this same complete
/// admitted final chain. Failure cannot publish Results or acknowledge stop.
pub fn effectful_final_run_evidence_failed_state(
  value : EffectfulFinalRunEvidence,
  updated_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, RunStateIssue] {
  let run_id = match run_definition_run_id(value.run_definition) {
    Err(_) => return Err(InvalidRunId)
    Ok(value) => value
  }
  issue_admitted_effect_failed_run_state_wire(
    value.outcomes,
    run_id,
    updated_at,
    value.declared_results,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Only new physical publication facts are checked here. Successful validation
/// neither commits the index nor changes the retained Effect outcome.
pub fn validate_retained_effectful_publication_commit(
  value : EffectfulFinalRunEvidence,
  bindings : Array[PublicationContract],
  request : PublicationContract,
  attempt : PublicationContract,
  index_entry : PublicationContract,
) -> Result[Unit, EffectfulPublicationCommitIssue] {
  match
    validate_durable_result_bindings(
      value.run_definition,
      value.invocation,
      value.definitions,
      value.artifacts,
      value.orderings,
      value.retentions,
      bindings,
      index_entry,
    ) {
    Err(issue) => return Err(DurableBinding(issue))
    Ok(_) => ()
  }
  validate_publication_commit_references(
    value.run_definition,
    value.invocation,
    value.definitions,
    value.manifest,
    value.final_receipt,
    value.captured_run,
    request,
    attempt,
    index_entry,
  ).map_err(issue => Index(issue))
}

///|
/// Validate the Effectful root chain and its exact publication index. Product
/// commit paths must use the complete Result-evidence variant below.
pub fn validate_effectful_publication_commit(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  computation_receipt : PublicationContract,
  captured_run : PublicationContract,
  preview : EffectPreviewIdentity,
  set_receipt_wire : String,
  member_receipt_wires : Array[String],
  final_receipt_wire : String,
  request : PublicationContract,
  attempt : PublicationContract,
  index_entry : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, EffectfulPublicationCommitIssue] {
  let final_receipt = match
    admit_effectful_final_run_evidence_chain(
      run_definition, invocation, definitions, artifacts, manifest, computation_receipt,
      captured_run, preview, set_receipt_wire, member_receipt_wires, final_receipt_wire,
      max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(FinalChain(issue))
  }
  validate_publication_commit_references(
    run_definition, invocation, definitions, manifest, final_receipt, captured_run,
    request, attempt, index_entry,
  ).map_err(issue => Index(issue))
}

///|
/// Validate the Effectful final chain, Result dependencies and exact index.
/// This does not replace apply admission, physical outcomes, or Store CAS.
pub fn validate_effectful_publication_commit_with_result_evidence(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  derivations : Array[PublicationContract],
  orderings : Array[PublicationContract],
  retentions : Array[PublicationContract],
  bindings : Array[PublicationContract],
  manifest : PublicationContract,
  computation_receipt : PublicationContract,
  captured_run : PublicationContract,
  preview : EffectPreviewIdentity,
  set_receipt_wire : String,
  member_receipt_wires : Array[String],
  final_receipt_wire : String,
  request : PublicationContract,
  attempt : PublicationContract,
  index_entry : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, EffectfulPublicationCommitIssue] {
  match
    validate_result_evidence_set(
      definitions, artifacts, derivations, orderings, retentions,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(ResultEvidence(issue))
  }
  match
    validate_durable_result_bindings(
      run_definition, invocation, definitions, artifacts, orderings, retentions,
      bindings, index_entry,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(DurableBinding(issue))
  }
  validate_effectful_publication_commit(
    run_definition, invocation, definitions, artifacts, manifest, computation_receipt,
    captured_run, preview, set_receipt_wire, member_receipt_wires, final_receipt_wire,
    request, attempt, index_entry, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Admit the complete immutable computation chain and final Effect references
/// together. Checked Program kind, current apply authority, physical Effect
/// Plan provenance, Result retention, and durable Store commit remain separate
/// admission obligations.
pub fn admit_effectful_final_run_evidence_chain(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  computation_receipt : PublicationContract,
  captured_run : PublicationContract,
  preview : EffectPreviewIdentity,
  set_receipt_wire : String,
  member_receipt_wires : Array[String],
  final_receipt_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectfulFinalChainIssue] {
  admit_effectful_final_run_evidence_with_outcomes(
    run_definition, invocation, definitions, artifacts, manifest, computation_receipt,
    captured_run, preview, set_receipt_wire, member_receipt_wires, final_receipt_wire,
    max_wire_bytes, max_nodes, max_depth,
  ).map(value => value.0)
}

///|
/// The same complete chain admission also retains its typed Set outcomes.
/// No second member-wire admission is required for disposition or partition.
pub fn admit_effectful_final_run_evidence_with_outcomes(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  computation_receipt : PublicationContract,
  captured_run : PublicationContract,
  preview : EffectPreviewIdentity,
  set_receipt_wire : String,
  member_receipt_wires : Array[String],
  final_receipt_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (PublicationContract, EffectSetApplyReceiptEvidence),
  EffectfulFinalChainIssue,
] {
  match
    validate_effectful_computation_evidence_chain(
      run_definition, invocation, definitions, artifacts, manifest, computation_receipt,
      captured_run, preview, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Computation(issue))
  }
  admit_effectful_final_receipt_evidence(
    run_definition, computation_receipt, captured_run, preview, set_receipt_wire,
    member_receipt_wires, final_receipt_wire, max_wire_bytes, max_nodes, max_depth,
  ).map_err(issue => FinalReferences(issue))
}

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
  admit_effectful_final_receipt_evidence(
    run_definition, computation_receipt, captured_run, preview, set_receipt_wire,
    member_receipt_wires, final_receipt_wire, max_wire_bytes, max_nodes, max_depth,
  ).map(value => value.0)
}

///|
fn admit_effectful_final_receipt_evidence(
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
) -> Result[
  (PublicationContract, EffectSetApplyReceiptEvidence),
  EffectfulFinalReferenceIssue,
] {
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
  if !effect_context_preview_inventory_matches(
      context,
      preview,
      preview.invocation_cid,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    return Err(ForeignEffectInventory)
  }
  let set_receipt = match
    admit_effect_set_apply_receipt_evidence(
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
      ("effect_set_apply_receipt_cid", set_receipt.receipt.identity),
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
  Ok((final_receipt, set_receipt))
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
