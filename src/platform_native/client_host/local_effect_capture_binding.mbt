///|
// A preflight over existing original custody, not a capture or read permit.
// The actual Work and capture Owners retain their current execution fences.
fn check_local_effect_capture_binding(
  host : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  journal : NativeClientRunJournal,
  materials : @host.ClientEffectRunMaterials,
  definition : @publication.PublicationContract,
  now : Double,
) -> Result[Unit, NativeClientSubmittedEffectMaterialsIssue] {
  let original = match
    host.lookup_submitted_effect_material_original(
      crypto, principal, connection, reference, request, now,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let binding = (fn() -> Result[Unit, NativeClientSubmittedEffectMaterialsIssue] {
    if !physical_equal(host.journal, journal) {
      return Err(ForeignPreparation)
    }
    if materials.request != Some(original.request) {
      return Err(ChangedIntent)
    }
    let run_cid = @publication.publication_contract_identity(
      original.definition,
    )
    if @publication.publication_contract_identity(definition) != run_cid ||
      @publication.publication_contract_identity(materials.run_definition) !=
      run_cid {
      return Err(ForeignRun)
    }
    if @host.client_effect_normalization_materials_cid(materials) !=
      Some(original.materials_cid) {
      return Err(ForeignPreparation)
    }
    Ok(())
  })()
  // A mismatch does not bypass the terminal current Account/custody check.
  // This lookup never changes control revision, claims work or repairs bytes.
  let current = match
    host.lookup_submitted_effect_material_original(
      crypto, principal, connection, reference, request, now,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if current.materials_cid != original.materials_cid ||
    current.materials_wire != original.materials_wire {
    return Err(Journal(CustodyLost))
  }
  binding
}

///|
/// Join the original accepted Submission packet to the same physical Work
/// before capture. Current Run read is independent of the Work's Source and
/// execution authority. No evidence disclosure, approval or credential is
/// issued, and a later boundary must still use the existing current fences.
pub fn NativeLocalHostConnection::check_submitted_effect_capture_work(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  work : NativeClientEffectSourceWork,
  now : Double,
) -> Result[Unit, NativeClientSubmittedEffectMaterialsIssue] {
  if @host.client_request_identity_relation(work.request, request) !=
    @host.SameRequest {
    // Authorize the original request before exposing a foreign binding.
    match
      self.lookup_submitted_effect_material_original(
        crypto, principal, connection, reference, request, now,
      ) {
      Ok(_) => return Err(ChangedIntent)
      Err(issue) => return Err(issue)
    }
  }
  check_local_effect_capture_binding(
    self,
    crypto,
    principal,
    connection,
    reference,
    request,
    work.journal,
    work.materials,
    work.definition,
    now,
  )
}
