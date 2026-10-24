///|
/// Readonly correspondence lookup. A migration cannot use an old policy-only
/// append or create one implicitly. This is not a Run permission or renewal.
pub fn NativeLocalHostConnection::require_packaged_runtime_upgrade(
  self : NativeLocalHostConnection,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard self.packaged_runtime is Some(binding) else { return Ok(()) }
  let pair = match self.runtime_policy_pair(binding.scope) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if pair is None {
    return Ok(())
  }
  let saved = match self.retained_policy_upgrade() {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  let fields = match
    @host.client_local_original_record_fields(saved.body, [
      "adoption_cid", "authority_scope_cid", "legacy_admissions_wire", "operation_id",
      "profile_wire", "read_configuration_name", "read_original_cid", "read_selection_wire",
      "retention_configuration_cid", "retention_configuration_name", "run_configuration_cid",
      "run_configuration_name", "runtime_pair_wire", "store_configuration_cid", "store_configuration_name",
      "version",
    ]) {
    Ok(value) => value
    Err(_) => return Err(ChangedIntent)
  }
  let expected = @utf8.decode(
    @host.client_native_local_scalar_runtime_pair_body(pair.unwrap()),
  ) catch {
    _ => return Err(CustodyLost)
  }
  if fields[12] != expected || !local_runtime_binding_current(self, binding) {
    return Err(CustodyLost)
  }
  Ok(())
}

///|
/// A transaction-observed admission is a lookup instruction, not permission to
/// execute or to replace the original Run's assets.
pub(all) enum NativeLocalRuntimeSubmission {
  Accepted
  Pending(
    (@host.ClientLocalProductAssets, @local.ClientInstalledSequenceContracts)?
  )
}

///|
/// A genuinely unaccepted original intent may use current admitted assets.
/// Accepted requests must use lookup; no old preparation is recompiled here.
pub fn NativeLocalHostConnection::packaged_runtime_assets_for_submission(
  self : NativeLocalHostConnection,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  max_work : Int,
) -> Result[NativeLocalRuntimeSubmission, NativeClientRunJournalIssue] {
  guard self.packaged_runtime is Some(binding) else { return Ok(Pending(None)) }
  guard binding.pair is Some(pair) else {
    // Immutable installation DATA only; no Journal or Run acceptance is issued.
    return Ok(Pending(Some(binding.installed_assets)))
  }
  let current = () => {
    local_runtime_binding_current(self, binding) &&
    local_policy_upgrade_current(
      self,
      self.epoch.crypto,
      binding.principal,
      binding.connection,
      binding.scope,
      true,
    )
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  self.journal.transaction(() => {
    match self.require_packaged_runtime_upgrade() {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match
      self.journal.verify_submission_locked(
        self.epoch,
        reference,
        binding.scope,
        current(),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let original = match self.journal.retained_submission(reference) {
      Ok(Some(value)) => value
      _ => return Err(CustodyLost)
    }
    if @host.client_submitted_intent_cid(original.intent) !=
      preparation.intent_cid {
      return Err(ChangedIntent)
    }
    if original.run_admission is Some(_) {
      if !current() {
        return Err(AuthorizationDenied)
      }
      return Ok(Accepted)
    }
    guard preparation.preparation is Computation(prepared) else {
      return Err(UnsupportedPreparation)
    }
    let profile = match
      @host.inspect_client_native_local_scalar_values_profile(
        prepared, max_work,
      ) {
      Ok(value) => value
      Err(_) => return Err(UnsupportedPreparation)
    }
    if @host.validate_client_native_local_scalar_runtime_pair_preparation(
        pair, profile, prepared,
      )
      is Err(_) {
      return Err(UnsupportedPreparation)
    }
    if !current() {
      return Err(AuthorizationDenied)
    }
    Ok(Pending(Some(binding.installed_assets)))
  })
}
