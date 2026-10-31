///|
/// Reuse the original Checkpoint/Run owner for independent authoring binding.
#export_name("clientValuesHostAdmitEffectCheckpointPreview")
pub fn client_values_host_admit_effect_checkpoint_preview(
  original : @checkpoint.SealedCheckpoint,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  stored_wire : String,
  preview_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.EffectPreviewIdentity,
  @host.ClientEffectCheckpointReconciliationIssue,
] {
  @host.admit_client_effect_review_checkpoint_preview(
    original,
    allowed,
    definition,
    stored_wire,
    preview_wire,
    { max_wire_bytes, max_nodes, max_depth, },
  )
}

///|
/// Admit historical Preview DATA against an independently supplied original
/// Run/context tuple. This supplies no current approval or dispatch authority.
#export_name("clientValuesHostAdmitEffectPreviewIdentity")
pub fn client_values_host_admit_effect_preview_identity(
  preview_wire : String,
  expected_run_identity_cid : String,
  expected_authoring_context_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.EffectPreviewIdentity,
  @publication.EffectPreviewIdentityIssue,
] {
  @publication.admit_effect_preview_identity(
    preview_wire, expected_run_identity_cid, expected_authoring_context_cid, max_wire_bytes,
    max_nodes, max_depth,
  )
}

///|
/// Read the original immutable inventory bound without admitting it again.
#export_name("clientValuesHostEffectPreviewMemberCount")
pub fn client_values_host_effect_preview_member_count(
  preview : @publication.EffectPreviewIdentity,
) -> Int {
  @publication.effect_preview_member_count(preview)
}

///|
/// Return the admitted semantic identity, distinct from a Store byte digest.
#export_name("clientValuesHostEffectPreviewSemanticIdentity")
pub fn client_values_host_effect_preview_semantic_identity(
  preview : @publication.EffectPreviewIdentity,
) -> String {
  @publication.effect_preview_semantic_identity(preview)
}

///|
/// The existing owner derives the final Receipt from the actual computation,
/// captured Run and admitted original Effect receipts, never from task progress.
#export_name("clientValuesHostIssueEffectfulFinalRunReceipt")
pub fn client_values_host_issue_effectful_final_run_receipt(
  run_definition : @publication.PublicationContract,
  computation_receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
  preview : @publication.EffectPreviewIdentity,
  set_receipt_wire : String,
  member_receipt_wires : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  @publication.EffectfulFinalReceiptIssuanceIssue,
] {
  @publication.issue_effectful_final_run_receipt(
    run_definition, computation_receipt, captured_run, preview, set_receipt_wire,
    member_receipt_wires, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Validate the complete Effectful chain and Result evidence before the
/// existing Store CAS. Validation is neither the CAS nor its acknowledgement.
#export_name("clientValuesHostValidateEffectfulPublicationCommit")
pub fn client_values_host_validate_effectful_publication_commit(
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  derivations : Array[@publication.PublicationContract],
  orderings : Array[@publication.PublicationContract],
  retentions : Array[@publication.PublicationContract],
  bindings : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  computation_receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
  preview : @publication.EffectPreviewIdentity,
  set_receipt_wire : String,
  member_receipt_wires : Array[String],
  final_receipt : @publication.PublicationContract,
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  index_entry : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, @publication.EffectfulPublicationCommitIssue] {
  @publication.validate_effectful_publication_commit_with_result_evidence(
    run_definition,
    invocation,
    definitions,
    artifacts,
    derivations,
    orderings,
    retentions,
    bindings,
    manifest,
    computation_receipt,
    captured_run,
    preview,
    set_receipt_wire,
    member_receipt_wires,
    @publication.publication_contract_json(final_receipt),
    request,
    attempt,
    index_entry,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Retain the existing complete chain/outcome admission, not an adapter Bool
/// or a reissued final Receipt. Current authority and physical CAS stay separate.
#export_name("clientValuesHostAdmitEffectfulFinalRunEvidence")
pub fn client_values_host_admit_effectful_final_run_evidence(
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  derivations : Array[@publication.PublicationContract],
  orderings : Array[@publication.PublicationContract],
  retentions : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  computation_receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
  preview : @publication.EffectPreviewIdentity,
  set_receipt_wire : String,
  member_receipt_wires : Array[String],
  final_receipt : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.EffectfulFinalRunEvidence,
  @publication.EffectfulPublicationCommitIssue,
] {
  @publication.admit_retained_effectful_final_run_evidence(
    run_definition,
    invocation,
    definitions,
    artifacts,
    derivations,
    orderings,
    retentions,
    manifest,
    computation_receipt,
    captured_run,
    preview,
    set_receipt_wire,
    member_receipt_wires,
    @publication.publication_contract_json(final_receipt),
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
#export_name("clientValuesHostEffectfulFinalRunReceipt")
pub fn client_values_host_effectful_final_run_receipt(
  value : @publication.EffectfulFinalRunEvidence,
) -> @publication.PublicationContract {
  @publication.effectful_final_run_evidence_receipt(value)
}

///|
#export_name("clientValuesHostEffectfulFinalRunStatus")
pub fn client_values_host_effectful_final_run_status(
  value : @publication.EffectfulFinalRunEvidence,
) -> String {
  @publication.effect_set_apply_receipt_run_status(
    @publication.effectful_final_run_evidence_outcomes(value),
  )
}

///|
#export_name("clientValuesHostEffectfulFinalRunAllUnattempted")
pub fn client_values_host_effectful_final_run_all_unattempted(
  value : @publication.EffectfulFinalRunEvidence,
) -> Bool {
  @publication.effect_set_apply_receipt_all_unattempted(
    @publication.effectful_final_run_evidence_outcomes(value),
  )
}

///|
#export_name("clientValuesHostEffectfulFinalRunReconciliationState")
pub fn client_values_host_effectful_final_run_reconciliation_state(
  value : @publication.EffectfulFinalRunEvidence,
  updated_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @publication.RunStateIssue] {
  @publication.effectful_final_run_evidence_reconciliation_state(
    value, updated_at, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// The returned original index is checked immutable publication DATA, never
/// an observation that the Store committed it or released physical resources.
#export_name("clientValuesHostValidateRetainedEffectfulPublicationCommit")
pub fn client_values_host_validate_retained_effectful_publication_commit(
  value : @publication.EffectfulFinalRunEvidence,
  bindings : Array[@publication.PublicationContract],
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  index_entry : @publication.PublicationContract,
) -> Result[
  @publication.PublicationContract,
  @publication.EffectfulPublicationCommitIssue,
] {
  @publication.validate_retained_effectful_publication_commit(
    value, bindings, request, attempt, index_entry,
  ).map(_ => index_entry)
}

///|
pub(all) enum ClientValuesHostOriginalResultOccurrenceIssue {
  Ordering(@publication.ResultOrderingEvidenceIssue)
  Artifact(@publication.ResultArtifactEvidenceIssue)
}

///|
/// Admit the actual saved originals against independent observed facts. No
/// derivation/ordering/issuer/scope contract is issued or serialized here.
#export_name("clientValuesHostAdmitOriginalResultOccurrenceEvidence")
pub fn client_values_host_admit_original_result_occurrence_evidence(
  definition : @publication.PublicationContract,
  artifact : @publication.PublicationContract,
  derivation : @publication.PublicationContract,
  ordering : @publication.PublicationContract,
  retention : @publication.PublicationContract,
  logical_value_cid : String,
  result_schema_cid : String,
  effective_data_policy_cid : String,
) -> Result[
  @publication.ResultOrderingEvidence,
  ClientValuesHostOriginalResultOccurrenceIssue,
] {
  let original = match
    @publication.validate_result_occurrence_ordering_evidence(
      definition, derivation, ordering, logical_value_cid, result_schema_cid, effective_data_policy_cid,
    ) {
    Err(issue) => return Err(Ordering(issue))
    Ok(value) => value
  }
  @publication.validate_result_artifact_evidence(
    definition, artifact, original, retention,
  )
  .map_err(issue => Artifact(issue))
  .map(_ => original)
}

///|
#export_name("clientValuesHostIssueEffectSucceededRunStateWire")
pub fn client_values_host_issue_effect_succeeded_run_state_wire(
  prepared : @host.PreparedClientEffectComputation,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  evidence : @publication.EffectfulFinalRunEvidence,
  observed_at : String,
  names : Array[String],
  states : Array[String],
  reasons : Array[String],
  result_observed_at : Array[String],
) -> String? {
  if !@publication.effectful_final_run_evidence_matches_definition(
      evidence, definition,
    ) ||
    @publication.effect_set_apply_receipt_run_status(
      @publication.effectful_final_run_evidence_outcomes(evidence),
    ) !=
    "succeeded" {
    return None
  }
  match @host.bind_client_effect_compiled_run(prepared, allowed, definition) {
    Err(_) => return None
    Ok(_) => ()
  }
  client_host_succeeded_run_state_wire(
    definition,
    @host.client_effect_allowed_run_result_names(allowed),
    observed_at,
    names,
    states,
    reasons,
    result_observed_at,
  )
}
