///|
pub(all) enum ResidentEffectCaptureCustodyIssue {
  Unavailable
  Binding(@publication.RunEvidenceChainIssue)
  Store(@publication_store.NativePublicationStoreIssue)
  Capacity(@resources.LedgerIssue)
}

///|
pub(all) struct ResidentEffectCaptureCustodyFailure {
  issue : ResidentEffectCaptureCustodyIssue
  custody : ResidentEffectCaptureCustody?
}

///|
/// Independent encrypted capture custody. It never replaces input, receiver,
/// borrow or Named Result ownership and grants no permission to apply/resume.
struct ResidentEffectCaptureCustody {
  mut custody : @publication_store.EffectCaptureCustody
  binding : @publication.EffectCaptureHoldingBinding
  crypto : @signature.Library
  key : Bytes
  ledger : @resources.Ledger
  reservation : @resources.Reservation
  mut released : Bool
}

///|
/// Validate the exact common capture chain, retain its execution Ledger charge
/// before persistence, and return the same responsibility on uncertain writes.
pub fn ResidentSourceCompute::persist_effect_capture(
  self : ResidentSourceCompute,
  store : @publication_store.Store,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  result : ResidentEffectResultCapture,
  invocation : @publication.PublicationContract,
  preview : @strategy.CapturedEffectPreviewInputs,
  captured : @publication.PublicationContract,
  store_authority : String,
  crypto : @signature.Library,
  key : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ResidentEffectCaptureCustody, ResidentEffectCaptureCustodyFailure] {
  if !self.resident_effect_inputs_current(inputs) {
    return Err({ issue: Unavailable, custody: None, })
  }
  let binding = match
    @publication.prepare_effect_capture_holding_binding(
      materials.run_definition,
      invocation,
      [result.definition],
      [result.artifact],
      result.manifest,
      result.receipt,
      captured,
      @strategy.captured_effect_preview_ledger_identity(preview),
      store_authority,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err({ issue: Binding(issue), custody: None, })
  }
  let physical = match
    store.prepare_effect_capture_custody(binding, crypto, key) {
    Ok(value) => value
    Err(issue) => return Err({ issue: Store(issue), custody: None, })
  }
  let holding = @publication.effect_capture_holding_identity(binding)
  let owner = match self.effect_captures.get(holding) {
    Some(value) => {
      if value.released || !value.custody.same_binding(physical) {
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
      let owner : ResidentEffectCaptureCustody = {
        custody: physical,
        binding,
        crypto,
        key: key[:].to_owned(),
        ledger,
        reservation,
        released: false,
      }
      self.effect_captures[holding] = owner
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
pub fn ResidentEffectCaptureCustody::confirm(
  self : ResidentEffectCaptureCustody,
) -> Result[@publication.PublicationContract, ResidentEffectCaptureCustodyIssue] {
  if self.released {
    return Err(Unavailable)
  }
  self.custody.confirm().map_err(issue => Store(issue))
}

///|
/// Reopen physical custody while keeping the original live Ledger charge.
/// This is Store reconstruction, not Host restart or approval/resume evidence.
pub fn ResidentEffectCaptureCustody::restore_store(
  self : ResidentEffectCaptureCustody,
  store : @publication_store.Store,
) -> Result[Unit, ResidentEffectCaptureCustodyIssue] {
  if self.released {
    return Err(Unavailable)
  }
  let custody = match
    store.restore_effect_capture_custody(self.binding, self.crypto, self.key) {
    Ok(value) => value
    Err(issue) => return Err(Store(issue))
  }
  self.custody = custody
  Ok(())
}

///|
pub fn ResidentEffectCaptureCustody::retry_cleanup(
  self : ResidentEffectCaptureCustody,
) -> Result[Bool, ResidentEffectCaptureCustodyIssue] {
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
