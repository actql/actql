///|
pub(all) enum NativeLocalSavedEffectResolutionIssue {
  SavedResolutionUnavailable
  SavedResolutionOriginal(NativeLocalAdoptionIssue)
  SavedResolutionReviewer(NativeLocalEffectReviewerBindingIssue)
  SavedResolutionKey(NativeLocalSigningOriginalIssue)
  SavedResolutionProof(NativeLocalReviewerProofMaterialsIssue)
  SavedResolutionSigning(NativeLocalInitialResolutionSigningIssue)
  SavedResolutionAccount(NativeLocalSigningAccountIssue)
  SavedResolutionHost(NativeLocalInitialHostAttestationIssue)
  SavedResolutionEncoding
}

///|
// The SAME caller-owned field tuples/Array and returned decision controls
// overlap each real text emission. A preceding measurement peak is not an
// additive reservation, so both text phases name this one immutable inventory.
let saved_effect_decision_emission_controls : @execution.PreparationRepresentationUnits = {
  record_headers: 42L,
  reference_slots: 68L,
  scalar_words: 401L,
  owned_utf16_units: 256L,
  owned_wire_bytes: 192L,
}

///|
// The existing Checkpoint codec admits this unsigned body and independently
// derives its proof preimage. No text replacement, signature placeholder,
// incoming authority, current Boolean or caller-selected key is accepted.
fn emit_saved_effect_resolution(
  writer : @encode.Writer,
  artifact : @checkpoint.SealedCheckpoint,
  actor : String,
  decision : String,
  decided_at : String,
  approval_evidence_cid? : String? = None,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for
    (name, value) in [
      ("version", "actql-checkpoint-resolution/0.1"),
      ("actor", actor),
      ("checkpoint_id", artifact.checkpoint.checkpoint_id),
      ("checkpoint_cid", artifact.checkpoint_cid),
      ("decided_at", decided_at),
      ("decision", decision),
      ("required_artifact_cid", artifact.checkpoint.required_artifact_cid),
      ("review_projection_cid", artifact.checkpoint.review_projection_cid),
      ("resolution_id", artifact.checkpoint_cid),
      ("run_id", artifact.checkpoint.run_id().unwrap()),
      ("run_definition_cid", artifact.checkpoint.run_definition_cid().unwrap()),
    ] {
    @encode.key(writer, name)
    @encode.string_value(writer, value)
  }
  if approval_evidence_cid is Some(cid) {
    @encode.key(writer, "approval_evidence_cid")
    @encode.string_value(writer, cid)
  }
  @encode.end_object(writer)
}

///|
fn emit_saved_effect_approval(
  writer : @encode.Writer,
  artifact : @checkpoint.SealedCheckpoint,
  actor : String,
  authority : String,
  approved_at : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for
    (name, value) in [
      ("version", "actql-approval-attestation/0.1"),
      ("effect_preview_cid", artifact.checkpoint.required_artifact_cid),
      ("review_projection_cid", artifact.checkpoint.review_projection_cid),
      ("approver", actor),
      ("approved_at", approved_at),
      ("authority_scope_cid", authority),
    ] {
    @encode.key(writer, name)
    @encode.string_value(writer, value)
  }
  @encode.key(writer, "claims")
  @encode.begin_array(writer)
  // The existing Native checked Effect checkpoint admits exactly this claim;
  // no member-count rule or fabricated partial-application acceptance exists.
  @encode.string_value(writer, "effect_scope_approved")
  @encode.end_array(writer)
  @encode.end_object(writer)
}

///|
/// Invoke the existing Reviewer and independent Host signing owners under the
/// same original Journal Read. Every physical attempt is retained by that Host
/// before fallible current/claim work. Failure leaves those original duties;
/// successful Resolution admission alone never claims an Effect was applied.
fn NativeLocalSavedEffectReview::resolve_initial_original(
  self : NativeLocalSavedEffectReview,
  action : String,
  host_configuration_file : String,
  retain_resume : Bool,
) -> Result[
  (NativeClientRunRecord, NativeLocalEffectResumeOriginal?),
  NativeLocalSavedEffectResolutionIssue,
] {
  if retain_resume && action != "approve" {
    return Err(SavedResolutionUnavailable)
  }
  let decision = match action {
    "approve" => "approved"
    "reject" => "rejected"
    _ => return Err(SavedResolutionUnavailable)
  }
  guard self.approval_original is Some(original) &&
    self.capture.opening is JournalAcquired(host) &&
    self.saved_approval_original_live(original) &&
    original.checkpoint.artifact.checkpoint.run_id() is Some(_) &&
    original.checkpoint.artifact.checkpoint.run_definition_cid() is Some(_) else {
    return Err(SavedResolutionUnavailable)
  }
  let limits = native_checkpoint_limits()
  // Both unsigned emitters are closed flat records (at most twelve fields,
  // with one claim Array). Back this non-text measurement frame first; the
  // SAME emitter then supplies actual bytes/nodes/depth for its text writer.
  let measurement = @encode.text_writer_construction_inventory(0, 12, 2).unwrap()
  match
    self.capture.prepare_model_entry_construction(
      None,
      additional_controls=Some({
        // Reuse the existing Native review emitter's larger fixed frame:
        // twelve borrowed field tuples, Writer controls and two digest slots.
        // This emitter has eleven pairs and two shorter original operation IDs.
        // Two retained slots plus the acknowledged record option/map frame.
        record_headers: saved_effect_decision_emission_controls.record_headers +
        measurement.record_headers,
        reference_slots: saved_effect_decision_emission_controls.reference_slots +
        measurement.reference_slots,
        scalar_words: saved_effect_decision_emission_controls.scalar_words +
        measurement.scalar_words,
        owned_utf16_units: saved_effect_decision_emission_controls.owned_utf16_units +
        measurement.owned_utf16_units,
        owned_wire_bytes: saved_effect_decision_emission_controls.owned_wire_bytes,
      }),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(SavedResolutionOriginal(issue))
  }
  let decided_at = match
    @values.epoch_milliseconds_timestamp(@env.now().reinterpret_as_int64()) {
    Some(value) => value
    None => return Err(SavedResolutionUnavailable)
  }
  let initial = match host.restore_initial_signing_original() {
    Ok(value) => value
    Err(issue) => return Err(SavedResolutionOriginal(issue))
  }
  let (binding, installed) = match
    self.bind_initial_effect_reviewer(initial, host_configuration_file, () => {
      @env.now().to_double()
    }) {
    Ok(value) => value
    Err(issue) => return Err(SavedResolutionReviewer(issue))
  }
  let key = match
    host.acquire_initial_reviewer_signing_key(initial, installed) {
    Ok(value) => value
    Err(issue) => return Err(SavedResolutionKey(issue))
  }
  let approval = if action == "approve" {
    let unsigned = try {
      let measure = @encode.measuring_writer(
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
      emit_saved_effect_approval(
        measure,
        original.checkpoint.artifact,
        self.principal,
        original.authority,
        decided_at,
      )
      let (bytes, nodes, depth) = @encode.finish_measurement_usage(measure)
      match
        self.capture.prepare_model_entry_construction(
          Some(bytes),
          nodes~,
          depth~,
          additional_controls=Some(saved_effect_decision_emission_controls),
        ) {
        Ok(_) => ()
        Err(issue) => return Err(SavedResolutionOriginal(issue))
      }
      let writer = @encode.writer(
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
      emit_saved_effect_approval(
        writer,
        original.checkpoint.artifact,
        self.principal,
        original.authority,
        decided_at,
      )
      @encode.finish(writer)
    } catch {
      _ => return Err(SavedResolutionEncoding)
    }
    let materials = match
      key.prepare_approval_proof_materials(binding, unsigned, limits) {
      Ok(value) => value
      Err(issue) => return Err(SavedResolutionProof(issue))
    }
    let signing = match
      materials.prepare_initial_approval_signing(
        "approval/" + original.checkpoint.artifact.checkpoint_cid,
      ) {
      Ok(value) => value
      Err(issue) => return Err(SavedResolutionSigning(issue))
    }
    let evidence = match signing.sign_approval_evidence_once() {
      Ok(value) => value
      Err(issue) => return Err(SavedResolutionSigning(issue))
    }
    match signing.close_checked() {
      Ok(_) => ()
      Err(issue) => return Err(SavedResolutionOriginal(Crypto(issue)))
    }
    Some(evidence)
  } else {
    None
  }
  let unsigned = try {
    let measure = @encode.measuring_writer(
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_saved_effect_resolution(
      measure,
      original.checkpoint.artifact,
      self.principal,
      decision,
      decided_at,
      approval_evidence_cid=approval.map(value => value.1),
    )
    let (bytes, nodes, depth) = @encode.finish_measurement_usage(measure)
    match
      self.capture.prepare_model_entry_construction(
        Some(bytes),
        nodes~,
        depth~,
        additional_controls=Some(saved_effect_decision_emission_controls),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(SavedResolutionOriginal(issue))
    }
    let writer = @encode.writer(
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_saved_effect_resolution(
      writer,
      original.checkpoint.artifact,
      self.principal,
      decision,
      decided_at,
      approval_evidence_cid=approval.map(value => value.1),
    )
    @encode.finish(writer)
  } catch {
    _ => return Err(SavedResolutionEncoding)
  }
  let materials = match
    key.prepare_reviewer_proof_materials(binding, unsigned, limits) {
    Ok(value) => value
    Err(issue) => return Err(SavedResolutionProof(issue))
  }
  // These identifiers select only the exact existing original operation rows.
  // They are neither authority nor a second request/physical attempt budget.
  let reviewer_operation = "reviewer/" +
    original.checkpoint.artifact.checkpoint_cid
  let signing = match
    materials.prepare_initial_resolution_signing(reviewer_operation) {
    Ok(value) => value
    Err(issue) => return Err(SavedResolutionSigning(issue))
  }
  let candidate = match signing.sign_candidate_once() {
    Ok(value) => value
    Err(issue) => return Err(SavedResolutionSigning(issue))
  }
  let authenticated = match binding.authenticate_resolution(candidate, limits) {
    Ok(value) => value
    Err(issue) => return Err(SavedResolutionReviewer(issue))
  }
  // Read/Resolve authority cannot become Host Sign authority. This existing
  // owner restores its independent actual initialized subject and Account.
  let account = match host.restore_initial_host_signing_account(installed) {
    Ok(value) => value
    Err(issue) => return Err(SavedResolutionAccount(issue))
  }
  let host_operation = "host/" + original.checkpoint.artifact.checkpoint_cid
  let attestation = match
    authenticated.prepare_initial_host_attestation(
      account,
      materials,
      host_operation,
      approval_evidence_wire=approval.map(value => value.0),
    ) {
    Ok(value) => value
    Err(issue) => return Err(SavedResolutionHost(issue))
  }
  let signing = match attestation.prepare_signing() {
    Ok(value) => value
    Err(issue) => return Err(SavedResolutionHost(issue))
  }
  match signing.sign_once() {
    Ok(_) => ()
    Err(issue) => return Err(SavedResolutionHost(issue))
  }
  let record = match signing.admit_original_resolution() {
    Ok(value) => value
    Err(issue) => return Err(SavedResolutionHost(issue))
  }
  let continuation = if retain_resume {
    match signing.prepare_effect_resume_original() {
      Ok(value) => Some(value)
      Err(issue) => return Err(SavedResolutionHost(issue))
    }
  } else {
    None
  }
  // The actual wrapper retains the view before this fallible physical close.
  // A failed close exposes no fresh continuation and retains original custody.
  match host.close_original_signing_attempts() {
    Ok(_) => Ok((record, continuation))
    Err(issue) => Err(SavedResolutionOriginal(issue))
  }
}

///|
pub fn NativeLocalSavedEffectReview::resolve_initial_in_original_read(
  self : NativeLocalSavedEffectReview,
  action : String,
  host_configuration_file : String,
) -> Result[NativeClientRunRecord, NativeLocalSavedEffectResolutionIssue] {
  self
  .resolve_initial_original(action, host_configuration_file, false)
  .map(value => value.0)
}

///|
/// The same acknowledged Approved answer and original lease supplier. It does
/// not start a second Run or execute a mutation. The caller retains the returned
/// view before claim/constructor callbacks and retires it with that same Read.
pub fn NativeLocalSavedEffectReview::resolve_initial_resume_in_original_read(
  self : NativeLocalSavedEffectReview,
  host_configuration_file : String,
) -> Result[
  (NativeClientRunRecord, NativeLocalEffectResumeOriginal),
  NativeLocalSavedEffectResolutionIssue,
] {
  match
    self.resolve_initial_original("approve", host_configuration_file, true) {
    Ok((record, Some(original))) => Ok((record, original))
    Ok(_) => Err(SavedResolutionUnavailable)
    Err(issue) => Err(issue)
  }
}
