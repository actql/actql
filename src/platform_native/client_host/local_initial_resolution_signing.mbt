///|
pub(all) enum NativeLocalInitialResolutionSigningIssue {
  OriginalSigningUnavailable
  OriginalSigningOriginal(NativeLocalAdoptionIssue)
  OriginalSigningProof(NativeLocalReviewerProofMaterialsIssue)
  OriginalSigningJournal(NativeClientRunJournalIssue)
  OriginalSigningCredential(@credential_resource.NativeCredentialResourceIssue)
  OriginalSigningPhysical(@crypto.NativeSignatureIssue)
}

///|
/// One retained signing phase in the original Local Host, not an approval or
/// Host attestation Owner. The Host keeps this same physical receiver through
/// partial failure/close, before its database and Root can be acknowledged.
struct NativeLocalInitialResolutionSigning {
  materials : NativeLocalReviewerProofMaterials
  key : NativeLocalInitialReviewerSigningKey
  scope : @credential.LocalSigningCredentialScope
  earlier_valid_until : Int64?
  physical : @crypto.OriginalKeySigningAttempt
  mut entered : Bool
  mut closed : Bool
  mut original_use : (
    NativeLocalGrantOriginal,
    @credential.LocalSigningCredentialUse,
  )?
  mut signature : String?
}

///|
fn prepare_local_initial_resolution_physical(
  key : NativeLocalInitialReviewerSigningKey,
  scope : @credential.LocalSigningCredentialScope,
) -> Result[
  @crypto.OriginalKeySigningAttempt,
  NativeLocalInitialResolutionSigningIssue,
] {
  match InitialReviewerKey(key).require_signing_key_scope(scope) {
    Err(issue) => return Err(OriginalSigningProof(issue))
    Ok(_) => ()
  }
  let public_key = match key.original.public_key.raw32() {
    Err(_) => return Err(OriginalSigningUnavailable)
    Ok(value) => value
  }
  key.original.host.epoch.crypto
  .prepare_original_key_signing_attempt(
    key.original.projection,
    public_key,
    @utf8.encode(scope.preimage),
  )
  .map_err(issue => OriginalSigningPhysical(issue))
}

///|
/// Prepare only bounded immutable DATA and the existing physical Library
/// child. No secret read, new signature, claim or issuer-time sample occurs
/// here; independent current Read fences may observe their original clock.
/// Configured signers keep their distinct issuer service; they cannot fall
/// back to this initial Store policy or create another initial key.
pub fn NativeLocalReviewerProofMaterials::prepare_initial_resolution_signing(
  self : NativeLocalReviewerProofMaterials,
  attempt_id : String,
  earlier_valid_until? : Int64? = None,
) -> Result[
  NativeLocalInitialResolutionSigning,
  NativeLocalInitialResolutionSigningIssue,
] {
  guard self.proof is ResolutionOriginal(_) else {
    return Err(OriginalSigningUnavailable)
  }
  self.prepare_initial_original_signing(attempt_id, earlier_valid_until~)
}

///|
/// The SAME retained Host signer/credential owner, with a different typed
/// original Reviewer artifact. Existing Resolution entry points refuse it.
pub fn NativeLocalReviewerProofMaterials::prepare_initial_approval_signing(
  self : NativeLocalReviewerProofMaterials,
  attempt_id : String,
) -> Result[
  NativeLocalInitialResolutionSigning,
  NativeLocalInitialResolutionSigningIssue,
] {
  guard self.proof is ApprovalOriginal(_) else {
    return Err(OriginalSigningUnavailable)
  }
  self.prepare_initial_original_signing(attempt_id)
}

///|
fn NativeLocalReviewerProofMaterials::prepare_initial_original_signing(
  self : NativeLocalReviewerProofMaterials,
  attempt_id : String,
  earlier_valid_until? : Int64? = None,
) -> Result[
  NativeLocalInitialResolutionSigning,
  NativeLocalInitialResolutionSigningIssue,
] {
  let scope = match self.prepare_signing_scope(attempt_id) {
    Err(issue) => return Err(OriginalSigningProof(issue))
    Ok(value) => value
  }
  let current = match self.initial_signing_current(scope) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let host = self.reviewer.host
  if host.reviewer_signing_attempt is Some(previous) && !previous.closed {
    return Err(OriginalSigningUnavailable)
  }
  let physical = match
    prepare_local_initial_resolution_physical(current.key, scope) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let original : NativeLocalInitialResolutionSigning = {
    materials: self,
    key: current.key,
    scope,
    earlier_valid_until,
    physical,
    entered: false,
    closed: false,
    original_use: None,
    signature: None,
  }
  // Retain before any subsequent current callback. Failure cannot leave an
  // unowned Library child or make Host.close skip this same physical duty.
  host.reviewer_signing_attempt = Some(original)
  original.refresh_current(current).map(_ => original)
}

///|
fn local_initial_resolution_signature_standard(
  transport : String,
) -> Result[String, NativeLocalInitialResolutionSigningIssue] {
  // Signature's Native verifier transport is fixed unpadded base64url. The
  // existing Checkpoint proof codec deliberately requires canonical base64.
  if transport.length() != 86 {
    return Err(OriginalSigningUnavailable)
  }
  let standard = transport
    .replace_all(old="-", new="+")
    .replace_all(old="_", new="/") +
    "=="
  let bytes = @base64.decode(standard[:]) catch {
    _ => return Err(OriginalSigningUnavailable)
  }
  if bytes.length() != 64 || @base64.encode(bytes) != standard {
    return Err(OriginalSigningUnavailable)
  }
  Ok(standard)
}

///|
// Intrinsic receiver/lifetime check only. It invokes no caller, current,
// key, Journal or permission callback and cannot issue or renew a use.
fn NativeLocalInitialResolutionSigning::require_original_frame(
  self : NativeLocalInitialResolutionSigning,
) -> Result[Unit, NativeLocalInitialResolutionSigningIssue] {
  match self.physical.require_original_owner() {
    Err(issue) => return Err(OriginalSigningPhysical(issue))
    Ok(_) => ()
  }
  let host = self.key.original.host
  guard !self.closed &&
    !host.closed &&
    host.reviewer_signing_attempt is Some(actual) &&
    physical_equal(actual, self) else {
    return Err(OriginalSigningUnavailable)
  }
  Ok(())
}

///|
fn NativeLocalInitialResolutionSigning::require_current(
  self : NativeLocalInitialResolutionSigning,
) -> Result[
  NativeLocalInitialSigningCurrent,
  NativeLocalInitialResolutionSigningIssue,
] {
  match self.require_original_frame() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let current = match
    self.materials.initial_signing_current(
      self.scope,
      original_use=self.original_use,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // A current callback may have closed this SAME signer. A retained successful
  // subject view cannot make the retired physical receiver usable again.
  self.require_original_frame().map(_ => current)
}

///|
// The scope and original subject were admitted once in this same operation.
// Recheck actual mutable material after a TX/physical/caller boundary, then
// the same noncallback subject and signer lifetimes. Each following locked
// gate independently reads current authority, row, use, expiry and cancellation.
// This view is neither a cached Allow nor a replacement signing/cleanup owner.
fn NativeLocalInitialResolutionSigning::refresh_current(
  self : NativeLocalInitialResolutionSigning,
  current : NativeLocalInitialSigningCurrent,
) -> Result[
  NativeLocalInitialSigningCurrent,
  NativeLocalInitialResolutionSigningIssue,
] {
  match self.require_original_frame() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.materials.require_current() {
    Err(issue) => return Err(OriginalSigningProof(issue))
    Ok(_) => ()
  }
  match self.require_original_frame() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard current.subject.original_subject_after_current()
    is Ok((invocation, unit)) &&
    invocation == self.scope.run_invocation_cid &&
    unit == self.scope.unit_definition_cid else {
    return Err(OriginalSigningUnavailable)
  }
  // Only the same acknowledged claim assigns original_use. An unknown COMMIT
  // returns before reaching this continuation; no tentative use can sign.
  Ok({ ..current, original_use: self.original_use, })
}

///|
/// Confirm the original grant/use TX before actual signing. Repeated/history
/// calls never re-enter the signer, change attempt or choose another ordinal.
/// The returned wire is a signed Resolution candidate only: independent Host
/// attestation, evidence, commit and same-Run continuation remain mandatory.
pub fn NativeLocalInitialResolutionSigning::sign_candidate_once(
  self : NativeLocalInitialResolutionSigning,
) -> Result[String, NativeLocalInitialResolutionSigningIssue] {
  guard self.materials.proof is ResolutionOriginal(_) else {
    return Err(OriginalSigningUnavailable)
  }
  self.sign_original_once()
}

///|
/// Only the typed original Approval proof reaches this SAME one-shot signer.
/// Its returned evidence CID identifies the actual stored signed wire.
pub fn NativeLocalInitialResolutionSigning::sign_approval_evidence_once(
  self : NativeLocalInitialResolutionSigning,
) -> Result[(String, String), NativeLocalInitialResolutionSigningIssue] {
  guard self.materials.proof is ApprovalOriginal(_) else {
    return Err(OriginalSigningUnavailable)
  }
  let wire = match self.sign_original_once() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    local_adoption_digest(
      self.key.original.host.epoch.crypto,
      @utf8.encode(wire),
    ) {
    Ok(cid) => Ok((wire, cid))
    Err(issue) => Err(OriginalSigningOriginal(issue))
  }
}

///|
fn NativeLocalInitialResolutionSigning::sign_original_once(
  self : NativeLocalInitialResolutionSigning,
) -> Result[String, NativeLocalInitialResolutionSigningIssue] {
  // Foreign process/thread use cannot consume the original Host's phase.
  // Check even before mutable phase fields; this intrinsic observation has
  // no callbacks, key/current read or grant.
  match self.physical.require_original_owner() {
    Err(issue) => return Err(OriginalSigningPhysical(issue))
    Ok(_) => ()
  }
  if self.entered || self.closed {
    return Err(OriginalSigningUnavailable)
  }
  self.entered = true
  let current = match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let host = self.key.original.host
  let primary : Ref[NativeLocalInitialResolutionSigningIssue?] = Ref(None)
  let retained_signature : Ref[String?] = Ref(None)
  let stored = host.journal.transaction(() => {
    let result = match
      local_initial_signing_issue_storage_locked(
        self.key,
        self.materials.reviewer.request,
        self.scope,
        self.scope.attempt_id,
        self.earlier_valid_until,
        () => @env.now().reinterpret_as_int64(),
        () => current.require_locked(),
        resolution_proof=match self.materials.proof {
          ResolutionOriginal(proof) => Some(proof)
          ApprovalOriginal(_) => None
        },
      ) {
      Err(InitialStorageJournal(issue)) => return Err(issue)
      Err(InitialStorageCredential(issue)) => {
        primary.val = Some(OriginalSigningCredential(issue))
        return Err(CustodyLost)
      }
      Ok(value) => value
    }
    match result {
      InitialStorageClaim(original, signing_use) =>
        self.original_use = Some((original, signing_use))
      InitialStorageHistory(original, history) => {
        // A claimed/Unknown/Failed tag or absent/corrupt signature never signs
        // again. Even Succeeded must have this exact authenticated original.
        if history.observed_outcome() != @credential_resource.Succeeded {
          return Err(CustodyLost)
        }
        let signing_use = history.original_use()
        let signature = match
          local_initial_resolution_signature_locked(host, original, signing_use) {
          Err(issue) => return Err(issue)
          Ok(value) => value
        }
        self.original_use = Some((original, signing_use))
        retained_signature.val = Some(signature)
      }
    }
    current.require_locked()
  })
  match stored {
    Err(CustodyLost) if primary.val is Some(issue) => return Err(issue)
    Err(issue) => return Err(OriginalSigningJournal(issue))
    Ok(_) => ()
  }
  // No tentative claim/use from an unknown COMMIT can reach the signer. Full
  // subject/current callbacks run again after the actual confirmed TX.
  let current = match self.refresh_current(current) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // All fallible/current callbacks have finished. Check the actual claimed
  // Credential and its live expiry/revocation in a fresh original snapshot,
  // then enter the no-user-callback physical signer directly.
  if retained_signature.val is None {
    match self.key.original.check_callback_current() {
      Err(issue) => return Err(OriginalSigningOriginal(issue))
      Ok(_) => ()
    }
  }
  match host.journal.transaction(() => current.require_locked()) {
    Err(issue) => return Err(OriginalSigningJournal(issue))
    Ok(_) => ()
  }
  match retained_signature.val {
    Some(signature) => self.signature = Some(signature)
    None => {
      let transport = match self.physical.sign_once() {
        Err(issue) =>
          // Keep the spent original and its physical primary/close state.
          // Absence of a returned signature is not evidence of no signing.
          return Err(OriginalSigningPhysical(issue))
        Ok(value) => value
      }
      match self.key.original.check_callback_current() {
        Err(issue) => return Err(OriginalSigningOriginal(issue))
        Ok(_) => ()
      }
      let signature = match
        local_initial_resolution_signature_standard(transport) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      let current = match self.refresh_current(current) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      guard self.original_use is Some((original, signing_use)) else {
        return Err(OriginalSigningUnavailable)
      }
      match
        host.journal.transaction(() => {
          match current.require_locked() {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
          match
            store_local_initial_resolution_signature_locked(
              host,
              original,
              signing_use,
              signature,
              prepared=match self.materials.proof {
                ResolutionOriginal(proof) => Some(proof)
                ApprovalOriginal(_) => None
              },
              approval=match self.materials.proof {
                ApprovalOriginal(proof) => Some(proof)
                ResolutionOriginal(_) => None
              },
            ) {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
          current.require_locked()
        }) {
        Err(issue) => return Err(OriginalSigningJournal(issue))
        Ok(_) => self.signature = Some(signature)
      }
    }
  }
  let current = match self.refresh_current(current) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  self.original_wire_in_current(current)
}

///|
/// Current read of this same completed candidate, never another signature or
/// a cached Allow. Its durable signature/outcome originals are read together.
pub fn NativeLocalInitialResolutionSigning::original_candidate(
  self : NativeLocalInitialResolutionSigning,
) -> Result[String, NativeLocalInitialResolutionSigningIssue] {
  guard self.materials.proof is ResolutionOriginal(_) else {
    return Err(OriginalSigningUnavailable)
  }
  self.original_wire()
}

///|
fn NativeLocalInitialResolutionSigning::original_wire(
  self : NativeLocalInitialResolutionSigning,
) -> Result[String, NativeLocalInitialResolutionSigningIssue] {
  let current = match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  self.original_wire_in_current(current)
}

///|
fn NativeLocalInitialResolutionSigning::original_wire_in_current(
  self : NativeLocalInitialResolutionSigning,
  current : NativeLocalInitialSigningCurrent,
) -> Result[String, NativeLocalInitialResolutionSigningIssue] {
  guard self.signature is Some(signature) &&
    self.original_use is Some((original, signing_use)) &&
    original.grant is SigningGrant(grant) else {
    return Err(OriginalSigningUnavailable)
  }
  let host = self.key.original.host
  let retained : Ref[String?] = Ref(None)
  match
    host.journal.transaction(() => {
      match current.require_locked() {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      let history = match
        @credential_resource.prepare_native_local_original_signing_history_candidate(
          host.database,
          grant,
        ) {
        Err(_) => return Err(CustodyLost)
        Ok(value) if value.observed_outcome() == @credential_resource.Succeeded =>
          value
        Ok(_) => return Err(CustodyLost)
      }
      if @credential.local_signing_credential_use_cid(history.original_use()) !=
        @credential.local_signing_credential_use_cid(signing_use) {
        return Err(CustodyLost)
      }
      match
        local_initial_resolution_result_locked(host, original, signing_use) {
        Ok((value, Some(wire))) if value == signature =>
          retained.val = Some(wire)
        Ok(_) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      current.require_locked()
    }) {
    Err(issue) => return Err(OriginalSigningJournal(issue))
    Ok(_) => ()
  }
  let wire = match self.materials.proof.seal(self.scope.key_id, signature) {
    Err(_) => return Err(OriginalSigningUnavailable)
    Ok(value) => value
  }
  if retained.val != Some(wire) {
    return Err(OriginalSigningUnavailable)
  }
  let current = match self.refresh_current(current) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // The last full proof/current callback may revoke the original Credential.
  // Observe it afterwards too; never expose a signature from an earlier gate.
  match host.journal.transaction(() => current.require_locked()) {
    Err(issue) => Err(OriginalSigningJournal(issue))
    Ok(_) => self.require_original_frame().map(_ => wire)
  }
}

///|
/// Cleanup only. A consumed/unconfirmed key close remains on this same Host
/// receiver and blocks Host DB/Root closure; no claim/outcome is repaired.
pub fn NativeLocalInitialResolutionSigning::close_checked(
  self : NativeLocalInitialResolutionSigning,
) -> Result[Unit, @crypto.NativeSignatureIssue] {
  // The physical Owner also fences duplicate close by process/thread. A local
  // closed flag must never manufacture an ACK for a foreign caller.
  match self.physical.close_checked() {
    Err(issue) => Err(issue)
    Ok(_) => {
      self.closed = true
      self.signature = None
      Ok(())
    }
  }
}
