///|
pub(all) enum ResidentEffectPreviewCustodyIssue {
  Unavailable
  Binding(@publication.RunEvidenceChainIssue)
  Store(@publication_store.NativePublicationStoreIssue)
  Capacity(@resources.LedgerIssue)
}

///|
pub(all) struct ResidentEffectPreviewCustodyFailure {
  issue : ResidentEffectPreviewCustodyIssue
  custody : ResidentEffectPreviewCustody?
}

///|
/// Original target evidence has its own reservation. Computation, Source,
/// receiver, borrow and public Result custody cannot discharge this obligation.
struct ResidentEffectPreviewCustody {
  mut custody : @publication_store.EffectPreviewCustody
  binding : @publication.EffectCaptureHoldingBinding
  identity : @publication.EffectPreviewIdentity
  wire : String
  authoring_cid : String
  crypto : @signature.Library
  key : Bytes
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  ledger : @resources.Ledger
  reservation : @resources.Reservation
  mut released : Bool
}

///|
/// Validate the original computation/Preview chain before allocating encrypted
/// target evidence. Saving evidence grants no waiting, approval or send rights.
pub fn ResidentSourceCompute::persist_effect_preview(
  self : ResidentSourceCompute,
  store : @publication_store.Store,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  result : ResidentEffectResultCapture,
  invocation : @publication.PublicationContract,
  preview : @strategy.CapturedEffectPreviewInputs,
  captured : @publication.PublicationContract,
  wire : String,
  authoring_cid : String,
  store_authority : String,
  crypto : @signature.Library,
  key : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ResidentEffectPreviewCustody, ResidentEffectPreviewCustodyFailure] {
  if !self.resident_effect_inputs_current(inputs) {
    return Err({ issue: Unavailable, custody: None, })
  }
  let identity = @strategy.captured_effect_preview_ledger_identity(preview)
  let binding = match
    @publication.prepare_effect_capture_holding_binding(
      materials.run_definition,
      invocation,
      [result.definition],
      [result.artifact],
      result.manifest,
      result.receipt,
      captured,
      identity,
      store_authority,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err({ issue: Binding(issue), custody: None, })
  }
  let physical = match
    store.prepare_effect_preview_custody(
      identity, wire, authoring_cid, store_authority, crypto, key, max_bytes, max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err({ issue: Store(issue), custody: None, })
  }
  let holding = @publication.effect_preview_private_holding_cid(
    identity, store_authority,
  ).unwrap()
  let owner = match self.effect_previews.get(holding) {
    Some(value) => {
      if value.released ||
        !value.custody.same_binding(physical) ||
        @publication.publication_contract_identity(
          @publication.effect_capture_holding_contract(value.binding),
        ) !=
        @publication.publication_contract_identity(captured) {
        return Err({ issue: Unavailable, custody: Some(value), })
      }
      value
    }
    None => {
      let ledger = @strategy.captured_dag_ledger(self.run)
      let reservation = match
        @resources.reserve_attempt(ledger, 0L, physical.reserved_bytes(), 0L) {
        Ok(value) => value
        Err(issue) => return Err({ issue: Capacity(issue), custody: None, })
      }
      let owner : ResidentEffectPreviewCustody = {
        custody: physical,
        binding,
        identity,
        wire,
        authoring_cid,
        crypto,
        key: key[:].to_owned(),
        max_bytes,
        max_nodes,
        max_depth,
        ledger,
        reservation,
        released: false,
      }
      self.effect_previews[holding] = owner
      owner
    }
  }
  if !self.resident_effect_inputs_current(inputs) {
    return Err({ issue: Unavailable, custody: Some(owner), })
  }
  match owner.custody.persist() {
    Ok(_) => ()
    Err(issue) => return Err({ issue: Store(issue), custody: Some(owner), })
  }
  if !self.resident_effect_inputs_current(inputs) {
    return Err({ issue: Unavailable, custody: Some(owner), })
  }
  Ok(owner)
}

///|
pub fn ResidentEffectPreviewCustody::confirm(
  self : ResidentEffectPreviewCustody,
) -> Result[
  (@publication.EffectPreviewIdentity, String),
  ResidentEffectPreviewCustodyIssue,
] {
  if self.released {
    return Err(Unavailable)
  }
  self.custody.confirm().map_err(issue => Store(issue))
}

///|
/// Reattach authenticated Store custody to the existing live Ledger charge.
/// This is not Host restart or permission to replay an external Effect.
pub fn ResidentEffectPreviewCustody::restore_store(
  self : ResidentEffectPreviewCustody,
  store : @publication_store.Store,
) -> Result[Unit, ResidentEffectPreviewCustodyIssue] {
  if self.released {
    return Err(Unavailable)
  }
  let custody = match
    store.restore_effect_preview_custody(
      self.identity,
      self.wire,
      self.authoring_cid,
      @publication.effect_capture_holding_authority(self.binding),
      self.crypto,
      self.key,
      self.max_bytes,
      self.max_nodes,
      self.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Store(issue))
  }
  self.custody = custody
  Ok(())
}

///|
/// Retire this evidence only when its caller has discharged its obligations.
/// Persisted terminal confirmation precedes returning the original reservation.
pub fn ResidentEffectPreviewCustody::retry_cleanup(
  self : ResidentEffectPreviewCustody,
) -> Result[Bool, ResidentEffectPreviewCustodyIssue] {
  if self.released {
    return Ok(false)
  }
  match self.custody.retry_cleanup() {
    Ok(_) => ()
    Err(issue) => return Err(Store(issue))
  }
  match @resources.settle_reservation(self.ledger, self.reservation) {
    Ok(_) => ()
    Err(issue) => return Err(Capacity(issue))
  }
  self.released = true
  Ok(true)
}
