///|
/// Restore only the original journal-selected packet through the existing
/// bounded material Owner. Its saved invocation/profile is rechecked against
/// the independently retained Run and request. This explicit restoration is
/// separate from first live binding: it cannot displace that physical Owner,
/// issue a replacement journal, claim work or send a Provider request.
/// Current Run read authority is required again after the bounded restore.
pub fn NativeLocalHostConnection::restore_submitted_effect_material_original(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  manifests : @host.ClientCompilationManifests,
  limits : @host.ClientValuesRunMaterialsLimits,
  effect_limits : @host.ClientEffectComputationLimits,
) -> Result[
  @host.ClientEffectRunMaterials,
  NativeClientSubmittedEffectMaterialsIssue,
] {
  let original = match
    self.lookup_submitted_effect_material_original(
      crypto, principal, connection, reference, request, now,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let materials = restore_original_effect_material_packet(
    original, expressions, operations, manifests, limits, effect_limits,
  )
  // Recheck current original Host/adoption/Account and immutable custody after
  // the pure restore, including before returning a material refusal. Control
  // revision changes alone do not replace packet
  // identity and do not turn a read into execution or a new admission.
  match
    self.require_original_effect_material_current(
      crypto, principal, connection, reference, request, now, original,
    ) {
    Ok(_) => ()
    Err(issue) => {
      if materials is Ok(value) {
        @host.clear_prepared_client_effect_custody_after_cleanup(value.prepared)
      }
      return Err(issue)
    }
  }
  materials.map_err(issue => Materials(issue))
}

///|
// SAME original material Owner, independent of a particular Native allocator
// scope. The caller must fund these pure checker/Graph/compiler constructors;
// original current Journal/custody is checked before and after by the Host.
fn restore_original_effect_material_packet(
  original : NativeClientRetainedEffectMaterials,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  manifests : @host.ClientCompilationManifests,
  limits : @host.ClientValuesRunMaterialsLimits,
  effect_limits : @host.ClientEffectComputationLimits,
  request_value_policies? : ((@checked.EffectComputationCandidate) -> Result[
    Array[@checked.HostRequestValuePolicyEvidence],
    @host.ClientEffectComputationIssue,
  ])? = None,
  before_compilation? : ((@host.ClientEffectCompilationConstructionInput) -> Result[
    Unit,
    @host.ClientEffectRunMaterialsIssue,
  ])? = None,
  retained_submission_input? : @host.ClientEffectRetainedSubmissionInput? = None,
) -> Result[@host.ClientEffectRunMaterials, @host.ClientEffectRunMaterialsIssue] {
  let materials = match
    @host.admit_client_effect_run_materials(
      original.materials_wire,
      @publication.publication_contract_identity(original.definition),
      expressions,
      operations,
      manifests,
      limits,
      effect_limits,
      expected_request=Some(original.request),
      retained_submission_input~,
      before_compilation~,
      request_value_policies~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if materials.request != Some(original.request) ||
    @publication.publication_contract_identity(materials.run_definition) !=
    @publication.publication_contract_identity(original.definition) {
    @host.clear_prepared_client_effect_custody_after_cleanup(materials.prepared)
    return Err(RunMismatch)
  }
  // Missing or legacy unbound normalization is not repaired by an issuer.
  match @host.restore_client_effect_run_normalization(materials) {
    Ok(_) => ()
    Err(issue) => {
      @host.clear_prepared_client_effect_custody_after_cleanup(
        materials.prepared,
      )
      return Err(Normalization(issue))
    }
  }
  if @host.client_effect_normalization_materials_cid(materials) !=
    Some(original.materials_cid) {
    @host.clear_prepared_client_effect_custody_after_cleanup(materials.prepared)
    return Err(Normalization(UnverifiedOriginalMaterials))
  }
  Ok(materials)
}

///|
// Only the actual approval restoration borrows the authenticated Submission
// in the existing lookup. The ordinary material reader returns the old packet.
fn NativeLocalHostConnection::read_submitted_effect_approval_material_original(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
) -> Result[
  (
    NativeClientRetainedEffectMaterials,
    @host.ClientEffectRetainedSubmissionInput?,
  ),
  NativeClientSubmittedEffectMaterialsIssue,
] {
  self.read_submitted_effect_material_original(
    crypto,
    principal,
    connection,
    reference,
    request,
    now,
    (observed, original, admission) => {
      let packet = match observed {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if @host.client_request_input_cid(packet.request) ==
        @host.source_free_caller_input_intent_cid() {
        return Ok((packet, None))
      }
      match
        @host.prepare_client_effect_retained_submission_input(
          original.reference.original,
          original.intent,
          packet.request,
          admission.run_definition_cid,
        ) {
        Ok(input) => Ok((packet, Some(input)))
        Err(_) => Err(CustodyLost)
      }
    },
  )
}

///|
// SAME independent current/custody relookup after pure construction, including
// failed construction. Neither an earlier read nor an equal CID refreshes it.
fn NativeLocalHostConnection::require_original_effect_material_current(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
  original : NativeClientRetainedEffectMaterials,
  retained_submission_input? : @host.ClientEffectRetainedSubmissionInput? = None,
) -> Result[Unit, NativeClientSubmittedEffectMaterialsIssue] {
  let current = match retained_submission_input {
    None =>
      match
        self.lookup_submitted_effect_material_original(
          crypto, principal, connection, reference, request, now,
        ) {
        Ok(packet) => packet
        Err(issue) => return Err(issue)
      }
    Some(_) =>
      match
        self.read_submitted_effect_approval_material_original(
          crypto, principal, connection, reference, request, now,
        ) {
        Ok((packet, input)) if input == retained_submission_input => packet
        Ok(_) => return Err(Journal(CustodyLost))
        Err(issue) => return Err(issue)
      }
  }
  if current.materials_wire != original.materials_wire ||
    current.materials_cid != original.materials_cid ||
    @host.client_request_identity_relation(current.request, original.request) !=
    @host.SameRequest ||
    @publication.publication_contract_identity(current.definition) !=
    @publication.publication_contract_identity(original.definition) {
    return Err(Journal(CustodyLost))
  }
  Ok(())
}
