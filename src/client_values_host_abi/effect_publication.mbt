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
