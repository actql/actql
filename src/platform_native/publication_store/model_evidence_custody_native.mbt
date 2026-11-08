///|
// Per-call evidence uses the existing encrypted Store transaction, capacity,
// readback and tombstone owner. It does not issue a Model call, settlement ACK,
// ObservationSet, Result or current execution permission.
struct ModelEvidenceCustody {
  private_custody : PrivateEffectEvidenceCustody
  original : @publication.RunEvidenceValue
}

///|
/// The trusted Model caller supplies its original admitted evidence and the
/// same Run/Scope/Slot/attempt. Fund this constructor, encryption, readback and
/// failed-child overlap BEFORE calling; Store disk quota is independent.
pub fn Store::prepare_model_evidence_custody(
  self : Store,
  definition : @publication.PublicationContract,
  scope_cid : String,
  slot_cid : String,
  attempt_cid : String,
  original : @publication.RunEvidenceValue,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[ModelEvidenceCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.prepare_model_evidence_custody_in_scope(
      definition, scope_cid, slot_cid, attempt_cid, original, crypto, key,
    )
  })
}

///|
fn Store::prepare_model_evidence_custody_in_scope(
  self : Store,
  definition : @publication.PublicationContract,
  scope_cid : String,
  slot_cid : String,
  attempt_cid : String,
  original : @publication.RunEvidenceValue,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[ModelEvidenceCustody, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let role = @publication.run_evidence_value_name(original)
  if ![
      "model_call_attempt", "model_attempt_accounting", "model_attempt_outcome",
      "model_dispatch_authority", "model_slot_capture", "model_invocation_evidence",
      "model_capture_bundle", "model_attachment_admission",
    ].contains(role) {
    return Err(InvalidConfiguration)
  }
  let holding = match
    @publication.model_scoped_private_holding_cid(
      definition,
      self.authority_cid,
      scope_cid,
      slot_cid,
      attempt_cid,
      1,
      "settled",
      role,
    ) {
    Some(value) => value
    None => return Err(InvalidConfiguration)
  }
  let cid = @publication.run_evidence_value_identity(original)
  let terminal = "{\"cleanup_complete\":true,\"evidence_cid\":\"" +
    cid +
    "\",\"version\":\"actql-native-model-evidence-custody/0.1\"}"
  prepare_private_effect_custody(
    self,
    holding,
    role,
    cid,
    @publication.run_evidence_value_json(original),
    "model_evidence_custody",
    "model-evidence",
    terminal,
    crypto,
    key,
  ).map(private_custody => { private_custody, original, })
}

///|
/// Restore only this exact existing cell. Missing evidence is never inserted,
/// treated as unsent, or replaced by a newly encrypted response.
pub fn Store::restore_model_evidence_custody(
  self : Store,
  definition : @publication.PublicationContract,
  scope_cid : String,
  slot_cid : String,
  attempt_cid : String,
  original : @publication.RunEvidenceValue,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[ModelEvidenceCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    let custody = match
      self.prepare_model_evidence_custody_in_scope(
        definition, scope_cid, slot_cid, attempt_cid, original, crypto, key,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    custody.private_custody.read().map(_ => custody)
  })
}

///|
pub fn ModelEvidenceCustody::persist(
  self : ModelEvidenceCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(false, false, fn() {
    self.private_custody.persist()
  })
}

///|
/// Exact authenticated readback only. The original Model/Journal caller still
/// owes its own durable settlement and same-entry acknowledgement.
pub fn ModelEvidenceCustody::confirm(
  self : ModelEvidenceCustody,
) -> Result[@publication.RunEvidenceValue, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(false, false, fn() {
    match self.private_custody.read() {
      Ok((_, false)) => Ok(self.original)
      Ok((_, true)) => Err(RecoveryRequired)
      Err(issue) => Err(issue)
    }
  })
}

///|
/// Called only by the owning Run after its original evidence retention ends.
/// Cancellation or a public terminal status alone cannot select retirement.
pub fn ModelEvidenceCustody::retry_cleanup(
  self : ModelEvidenceCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(true, false, fn() {
    self.private_custody.retry_cleanup()
  })
}

///|
pub fn ModelEvidenceCustody::reserved_bytes(
  self : ModelEvidenceCustody,
) -> Int64 {
  self.private_custody.reserved_bytes()
}
