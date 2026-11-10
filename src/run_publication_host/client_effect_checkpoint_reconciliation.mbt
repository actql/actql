///|
pub(all) enum ClientEffectCheckpointReconciliationIssue {
  Binding(ClientEffectCheckpointBindingIssue)
  Checkpoint(@checkpoint.CheckpointIssue)
  Authoring(ClientAuthoringContextIssue)
  Preview(@publication.EffectPreviewIdentityIssue)
  ForeignPreview
  Invocation(@publication.PublicationContractIssue)
  RunBinding(@publication.EffectPreviewRunBindingIssue)
  RunState(@publication.RunStateIssue)
}

///|
/// Read the original Checkpoint's Preview through the existing subject,
/// compiled Run and authoring owners. This historical DATA supplies neither
/// current permission, an Effect outcome nor a persistence acknowledgement.
pub fn admit_client_effect_review_checkpoint_preview(
  original : @checkpoint.SealedCheckpoint,
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  stored_wire : String,
  preview_wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[
  @publication.EffectPreviewIdentity,
  ClientEffectCheckpointReconciliationIssue,
] {
  let authoring_cid = match
    client_effect_review_checkpoint_authoring(
      original, allowed, definition, stored_wire, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let preview = match
    @publication.admit_effect_preview_identity(
      preview_wire,
      @publication.publication_contract_identity(definition),
      authoring_cid,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preview(issue))
  }
  if @publication.effect_preview_semantic_identity(preview) !=
    original.checkpoint.required_artifact_cid {
    return Err(ForeignPreview)
  }
  Ok(preview)
}

///|
/// Same checkpoint admission, retaining its original canonical body for the
/// Native saved caller rather than reparsing it for each application row.
pub fn admit_client_effect_review_checkpoint_preview_with_original(
  original : @checkpoint.SealedCheckpoint,
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  stored_wire : String,
  preview_wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[
  (@publication.EffectPreviewIdentity, @canonical.CanonicalValue),
  ClientEffectCheckpointReconciliationIssue,
] {
  let authoring_cid = match
    client_effect_review_checkpoint_authoring(
      original, allowed, definition, stored_wire, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let preview = match
    @publication.admit_effect_preview_identity_with_original(
      preview_wire,
      @publication.publication_contract_identity(definition),
      authoring_cid,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preview(issue))
  }
  if @publication.effect_preview_semantic_identity(preview.0) !=
    original.checkpoint.required_artifact_cid {
    return Err(ForeignPreview)
  }
  Ok(preview)
}

///|
fn client_effect_review_checkpoint_authoring(
  original : @checkpoint.SealedCheckpoint,
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  stored_wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[String, ClientEffectCheckpointReconciliationIssue] {
  match @checkpoint.confirm_checkpoint_persisted(original, stored_wire) {
    Ok(_) => ()
    Err(issue) => return Err(Checkpoint(issue))
  }
  match
    validate_client_effect_review_checkpoint_subject(
      allowed, definition, original,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Binding(issue))
  }
  match
    bind_client_effect_compiled_run(
      allowed.compilation.owner,
      allowed,
      definition,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Binding(Run(issue)))
  }
  let authoring = match
    issue_prepared_client_authoring_context(
      client_effect_program_view(allowed.compilation.owner),
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Authoring(issue))
  }
  Ok(@publication.run_evidence_value_identity(authoring))
}

///|
/// Project complete admitted Unknown receipts for this original review only.
/// Journal custody/currentness and physical outcome evidence remain with the
/// caller. This is neither an Effect permit nor a stopping or cleanup ACK.
pub fn client_effect_review_checkpoint_reconciliation_state(
  original : @checkpoint.SealedCheckpoint,
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  stored_wire : String,
  preview_wire : String,
  invocation_wire : String,
  set_wire : String,
  member_receipt_wires : Array[String],
  updated_at : String,
  declared_results : Array[String],
  limits : @checkpoint.WireLimits,
) -> Result[String, ClientEffectCheckpointReconciliationIssue] {
  let preview = match
    admit_client_effect_review_checkpoint_preview(
      original, allowed, definition, stored_wire, preview_wire, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let invocation = match
    @publication.admit_publication_contract(
      "run_invocation",
      invocation_wire,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  match
    @publication.check_effect_preview_run_binding(
      allowed.admission,
      definition,
      invocation,
      preview,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(RunBinding(issue))
  }
  let run_id = match @publication.run_definition_run_id(definition) {
    Ok(value) => value
    Err(_) => return Err(Binding(ForeignSubject))
  }
  @publication.issue_effect_reconciliation_run_state_wire(
    preview,
    set_wire,
    member_receipt_wires,
    run_id,
    updated_at,
    declared_results,
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  ).map_err(issue => RunState(issue))
}
