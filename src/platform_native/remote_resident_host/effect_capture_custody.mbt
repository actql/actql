///|
pub(all) enum ResidentEffectCaptureCustodyIssue {
  Unavailable
  Binding(@publication.RunEvidenceChainIssue)
  Store(@publication_store.NativePublicationStoreIssue)
  Capacity(@resources.LedgerIssue)
  ComputationCapacityMissing
}

///|
pub(all) struct ResidentEffectCaptureCustodyFailure {
  issue : ResidentEffectCaptureCustodyIssue
  custody : ResidentEffectCaptureCustody?
}

///|
/// The complete original computation chain already accepted by the existing
/// capture binding Owner. These are bounded contract references, not another
/// output borrow, execution handle or authority. Cleanup drops them only after
/// physical custody is confirmed retired. Its separate metadata reservation
/// remains live through failed cleanup or settlement.
priv struct OriginalResidentEffectComputationEvidence {
  run : @publication.PublicationContract
  invocation : @publication.PublicationContract
  definition : @publication.PublicationContract
  artifact : @publication.PublicationContract
  manifest : @publication.PublicationContract
  receipt : @publication.PublicationContract
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
  mut original : FundedResidentEffectComputation?
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
  computation_capacity? : ResidentEffectComputationCapacity? = None,
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
  // The operator must supply an independently justified representation bound.
  // A missing bound is a private installation gap, not a language restriction.
  guard computation_capacity is Some(capacity) else {
    return Err({ issue: ComputationCapacityMissing, custody: None, })
  }
  if !original_computation_capacity_valid(capacity) {
    return Err({ issue: Capacity(InvalidCharge), custody: None, })
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
        original: None,
      }
      self.effect_captures[holding] = owner
      owner
    }
  }
  match owner.original {
    Some(funded) =>
      if funded.capacity != capacity ||
        funded.physical_cleanup_confirmed ||
        funded.evidence is None ||
        !@resources.capacity_reservation_matches(
          owner.ledger,
          funded.reservation,
          capacity.contract_bytes + capacity.control_bytes,
          capacity.workspace_bytes,
        ) {
        return Err({ issue: Unavailable, custody: Some(owner), })
      }
    None => {
      let reservation = match
        reserve_original_computation_capacity(owner.ledger, capacity) {
        Ok(value) => value
        Err(issue) =>
          return Err({ issue: Capacity(issue), custody: Some(owner), })
      }
      // Publish the nominal reservation into the same owner before measuring
      // or extending any of the six original contract lifetimes.
      let funded : FundedResidentEffectComputation = {
        capacity,
        reservation,
        evidence: None,
        physical_cleanup_confirmed: false,
      }
      owner.original = Some(funded)
      let evidence : OriginalResidentEffectComputationEvidence = {
        run: materials.run_definition,
        invocation,
        definition: result.definition,
        artifact: result.artifact,
        manifest: result.manifest,
        receipt: result.receipt,
      }
      for
        contract in [
          evidence.run,
          evidence.invocation,
          evidence.definition,
          evidence.artifact,
          evidence.manifest,
          evidence.receipt,
        ] {
        match
          @publication.publication_contract_representation_extent(
            contract, max_nodes, max_depth, max_bytes,
          ) {
          Ok(_) => ()
          Err(_) =>
            return Err({
              issue: Binding(@publication.EvidenceEncoding),
              custody: Some(owner),
            })
        }
      }
      funded.evidence = Some(evidence)
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
  if self.released || self.original is None {
    return Err(Unavailable)
  }
  if self.original is Some(funded) &&
    (funded.physical_cleanup_confirmed || funded.evidence is None) {
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
  // A confirmed physical cleanup must never reopen the encrypted body merely
  // because its metadata settlement still needs retry.
  if self.original is Some(funded) && funded.physical_cleanup_confirmed {
    return Ok(())
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
  let physical_confirmed = match self.original {
    Some(funded) => funded.physical_cleanup_confirmed
    None => false
  }
  if !physical_confirmed {
    match self.custody.retry_cleanup() {
      Ok(_) => ()
      Err(issue) => return Err(Store(issue))
    }
    if self.original is Some(funded) {
      funded.physical_cleanup_confirmed = true
    }
  }
  if @resources.reservation_open(self.reservation) {
    match @resources.settle_reservation(self.ledger, self.reservation) {
      Ok(_) => ()
      Err(issue) => return Err(Capacity(issue))
    }
  }
  if self.original is Some(funded) {
    funded.evidence = None
    if @resources.capacity_reservation_open(funded.reservation) {
      match @resources.settle_capacity(self.ledger, funded.reservation) {
        Ok(_) => ()
        Err(issue) => return Err(Capacity(issue))
      }
    }
  }
  self.original = None
  self.released = true
  Ok(true)
}
