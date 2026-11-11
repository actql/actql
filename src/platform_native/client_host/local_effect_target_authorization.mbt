///|
// Existing Account/decision Owners only. The caller has already admitted the
// original signed approval and owns its current claim; DATA supplied directly
// to this private helper is not evidence of either fact.
fn bind_saved_effect_target_authorization(
  configuration : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  preview_cid : String,
  context_cid : String,
  approval : @checkpoint.ResumedApproval,
  reviewer_id : String,
  required : Array[@checkpoint.CheckpointRequirement],
) -> Result[
  @authorization.DispatchAuthorization,
  @authorization.DispatchBindingIssue,
] {
  if tuple.operation != "effect" ||
    approval.reviewer_id != reviewer_id ||
    !@checkpoint.checkpoint_requirements_valid(@checkpoint.EffectSet, required) {
    return Err(@authorization.ForeignDecision)
  }
  let delegated_action = match
    @authorization.evaluate_account(configuration, tuple) {
    @authorization.Delegate(matched) => {
      let request = match
        @authorization.prepare_decision_request(
          matched,
          configuration_cid=configuration.configuration_cid(),
          boundary=@authorization.EffectCommit,
          subject_cid=preview_cid,
          context_cid~,
          answering_authorities=[reviewer_id],
          required_claims=required.map(@checkpoint.checkpoint_requirement_token),
        ) {
        Ok(value) => value
        Err(_) => return Err(@authorization.ForeignDecision)
      }
      match
        @authorization.admit_host_answer(
          request,
          @authorization.Permit(
            { subject: request.subject(), authority: approval.reviewer_id, },
            approval.claims,
          ),
        ) {
        Ok(value) => Some(value)
        Err(_) => return Err(@authorization.ForeignDecision)
      }
    }
    _ => None
  }
  @authorization.bind_dispatch_authorization(
    configuration,
    tuple,
    @authorization.EffectCommit,
    preview_cid,
    context_cid,
    delegated_action~,
  )
}

///|
/// Re-evaluate the actual target's Effect tuple and bind only this claim's
/// original authenticated approval to its sealed Set/member. This is not a
/// Provider capability: the caller still checks the SAME live row/claim fence
/// immediately before IO. A claim or an unresolved Delegate alone cannot pass.
pub fn NativeLocalEffectResumeOriginal::authorize_saved_file_effect_in_original_read(
  self : Self,
  capture : NativeLocalJournalCapture,
  member_index : Int,
  declaration : @rows.RowDeclaration,
  mapping : @rows.RowMapping,
  installation_binding_cid : String,
) -> Result[Unit, NativeLocalInitialHostAttestationIssue] {
  guard self.prepared &&
    !self.retired &&
    self.action is Some(Claimed(claim)) &&
    physical_equal(claim.journal, self.host.journal) &&
    claim.request == self.request &&
    self.subject is Some(SavedSigningSubject(read)) &&
    physical_equal(read.owner.capture, capture) &&
    read.owner.saved_approval_original_live(read.original) &&
    self.record.checkpoint is Some(checkpoint) &&
    checkpoint.artifact.checkpoint.kind == @checkpoint.EffectSet &&
    claim.checkpoint_cid == checkpoint.artifact.checkpoint_cid &&
    checkpoint.resolution_cid == Some(claim.resolution_cid) &&
    claim.approval.checkpoint_cid == claim.checkpoint_cid &&
    claim.approval.resolution_cid == claim.resolution_cid &&
    claim.approval.reviewer_id == self.registration.reviewer_id else {
    return Err(HostAttestationUnavailable)
  }
  let original = read.original
  let preview = original.preview
  let members = @publication.effect_preview_member_count(preview)
  if member_index < 0 || member_index >= members {
    return Err(HostAttestationUnavailable)
  }
  // Decision subject/request/answer/binding and their Result/Option/closure
  // frames; one authority and at most the two sealed Effect claims. Bounded
  // descriptor walks keep their temporary wrappers until this call returns.
  // Account, original Strings, Mapping and Preview are borrowed, not reparsed.
  match
    capture.prepare_model_entry_construction(
      None,
      additional_controls=Some({
        record_headers: 64L + 16L * members.to_int64(),
        reference_slots: 128L + 32L * members.to_int64(),
        scalar_words: 32L + 8L * members.to_int64(),
        // All intermediate canonical target concatenations overlap the final
        // comparison; neither borrowed identifier is encoded or reparsed.
        owned_utf16_units: 64L +
        6L * declaration.connector_id.length().to_int64() +
        2L * mapping.resource.length().to_int64(),
        owned_wire_bytes: 0L,
      }),
    ) {
    Err(issue) => return Err(HostAttestationOriginal(issue))
    Ok(_) => ()
  }
  guard !self.retired &&
    self.action is Some(Claimed(actual_claim)) &&
    physical_equal(actual_claim, claim) &&
    read.owner.saved_approval_original_live(original) &&
    @publication.effect_preview_semantic_identity(preview) ==
    checkpoint.artifact.checkpoint.required_artifact_cid &&
    @publication.effect_preview_member_source_binding_cid(preview, member_index) ==
    Some(installation_binding_cid) &&
    @publication.effect_preview_member_resolved_contract(preview, member_index)
    is Some(@publication.Mapping(reference, mapping_cid)) &&
    reference == mapping.mapping_ref &&
    mapping_cid == mapping.mapping_cid else {
    return Err(HostAttestationUnavailable)
  }
  let headers = @checked.effect_program_static_headers(
    @host.prepared_client_effect_computation_candidate(
      original.materials.prepared,
    ),
  )
  guard @syntax.effect_header_at(headers, member_index) is Some(header) &&
    @host.client_effect_member_descriptor(
      original.materials.prepared,
      @syntax.effect_header_stage(header),
      @syntax.effect_header_id(header),
      @host.client_standard_effect_computation_limits().effects.max_work,
    )
    is Ok(descriptor) &&
    descriptor.0 == member_index &&
    descriptor.2 == "update" &&
    descriptor.3 ==
    "connector://" + declaration.connector_id + "/" + mapping.resource &&
    descriptor.4 == mapping.mapping_ref &&
    descriptor.5 == mapping.mapping_cid else {
    return Err(HostAttestationUnavailable)
  }
  let decision_issue : Ref[@authorization.DispatchBindingIssue?] = Ref(None)
  let result = capture.with_current_adoption_material_in_original_read((
    host,
    material,
    _operations,
  ) => {
    guard !self.retired &&
      self.action is Some(Claimed(current_claim)) &&
      physical_equal(current_claim, claim) &&
      read.owner.saved_approval_original_live(original) &&
      physical_equal(host, self.host) &&
      @host.client_local_adopted_current_account(material, host.database)
      is Ok(configuration) &&
      configuration.configuration_cid() == self.authentication.policy_cid else {
      return Err(CustodyLost)
    }
    let tuple : @authorization.AccessTuple = {
      principal: self.principal,
      connection: declaration.connector_id,
      resource: mapping.resource,
      operation: "effect",
    }
    let bound = bind_saved_effect_target_authorization(
      configuration,
      tuple,
      checkpoint.artifact.checkpoint.required_artifact_cid,
      self.authentication.authority_context_cid,
      claim.approval,
      self.registration.reviewer_id,
      checkpoint.artifact.checkpoint.requirements,
    )
    if bound is Err(issue) {
      // Keep the first decision refusal before returning the SAME original
      // Read. Its separate return/cleanup issue remains on that owner.
      decision_issue.val = Some(issue)
    }
    Ok(bound.map(_ => ()))
  })
  if decision_issue.val is Some(issue) {
    return Err(HostAttestationAuthorization(issue))
  }
  match result {
    Ok(Ok(_)) =>
      if !self.retired &&
        self.action is Some(Claimed(current_claim)) &&
        physical_equal(current_claim, claim) &&
        read.owner.saved_approval_original_live(original) {
        Ok(())
      } else {
        Err(HostAttestationUnavailable)
      }
    Ok(Err(issue)) => Err(HostAttestationAuthorization(issue))
    Err(issue) => Err(HostAttestationOriginal(issue))
  }
}
