///|
pub(all) enum ResidentEffectCheckpointCustodyIssue {
  Unavailable
  Capture(ResidentEffectCaptureCustodyIssue)
  Preview(ResidentEffectPreviewCustodyIssue)
  Store(@publication_store.NativePublicationStoreIssue)
  Capacity(@resources.LedgerIssue)
  Projection(@checkpoint.RunStateWireIssue)
}

///|
pub(all) struct ResidentEffectCheckpointCustodyFailure {
  issue : ResidentEffectCheckpointCustodyIssue
  custody : ResidentEffectCheckpointCustody?
}

///|
/// Exact original review evidence retains its own reservation. The Run owner
/// must separately commit waiting, authorize approval and discharge this
/// retention obligation before retirement. This is neither a Run ledger nor
/// an execution permit.
struct ResidentEffectCheckpointCustody {
  mut custody : @publication_store.EffectCheckpointCustody
  review : ResidentEffectReviewCheckpoint
  crypto : @signature.Library
  key : Bytes
  ledger : @resources.Ledger
  reservation : @resources.Reservation
  mut released : Bool
}

///|
fn ResidentEffectReviewCheckpoint::confirm_original_owners(
  self : ResidentEffectReviewCheckpoint,
) -> Result[Unit, ResidentEffectCheckpointCustodyIssue] {
  match self.capture_owner.confirm() {
    Ok(_) => ()
    Err(issue) => return Err(Capture(issue))
  }
  match self.preview_owner.confirm() {
    Ok((_, wire)) => if wire != self.review_wire { return Err(Unavailable) }
    Err(issue) => return Err(Preview(issue))
  }
  Ok(())
}

///|
pub fn ResidentSourceCompute::persist_effect_review_checkpoint(
  self : ResidentSourceCompute,
  store : @publication_store.Store,
  inputs : @strategy.CapturedEffectInputs,
  review : ResidentEffectReviewCheckpoint,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[
  ResidentEffectCheckpointCustody,
  ResidentEffectCheckpointCustodyFailure,
] {
  if !physical_equal(self, review.source_owner) ||
    !self.resident_effect_inputs_current(inputs) {
    return Err({ issue: Unavailable, custody: None, })
  }
  match review.confirm_original_owners() {
    Ok(_) => ()
    Err(issue) => return Err({ issue, custody: None, })
  }
  let physical = match
    store.prepare_effect_checkpoint_custody(
      review.checkpoint,
      review.continuation_wire,
      review.store_authority,
      crypto,
      key,
    ) {
    Ok(value) => value
    Err(issue) => return Err({ issue: Store(issue), custody: None, })
  }
  let holding = review.checkpoint.checkpoint_cid
  let owner = match self.effect_checkpoints.get(holding) {
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
      let owner : ResidentEffectCheckpointCustody = {
        custody: physical,
        review,
        crypto,
        key: key[:].to_owned(),
        ledger,
        reservation,
        released: false,
      }
      self.effect_checkpoints[holding] = owner
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
  match owner.review.confirm_original_owners() {
    Ok(_) => ()
    Err(issue) => return Err({ issue, custody: Some(owner), })
  }
  if !self.resident_effect_inputs_current(inputs) {
    return Err({ issue: Unavailable, custody: Some(owner), })
  }
  Ok(owner)
}

///|
pub fn ResidentEffectCheckpointCustody::confirm(
  self : ResidentEffectCheckpointCustody,
) -> Result[
  (@checkpoint.PersistedCheckpoint, String),
  ResidentEffectCheckpointCustodyIssue,
] {
  if self.released {
    return Err(Unavailable)
  }
  match self.review.confirm_original_owners() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.custody.confirm().map_err(issue => Store(issue))
}

///|
/// The common Owner can project waiting only after exact paired readback.
/// This projection still needs the original Run owner's revision-bound commit;
/// it is not public state, current authority or approval/resume permission.
pub fn ResidentEffectCheckpointCustody::waiting_projection(
  self : ResidentEffectCheckpointCustody,
  updated_at : String,
  declared_results : Array[String],
  limits : @checkpoint.WireLimits,
) -> Result[String, ResidentEffectCheckpointCustodyIssue] {
  let (persisted, _) = match self.confirm() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @checkpoint.issue_waiting_run_state(
    persisted, updated_at, declared_results, limits,
  ).map_err(issue => Projection(issue))
}

///|
/// Store reopening keeps the same live execution reservation. It is not Host
/// restart, generation reauthorization, holder restoration or waiting commit.
pub fn ResidentEffectCheckpointCustody::restore_store(
  self : ResidentEffectCheckpointCustody,
  store : @publication_store.Store,
) -> Result[Unit, ResidentEffectCheckpointCustodyIssue] {
  if self.released {
    return Err(Unavailable)
  }
  let physical = match
    store.restore_effect_checkpoint_custody(
      self.review.checkpoint,
      self.review.continuation_wire,
      self.review.store_authority,
      self.crypto,
      self.key,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Store(issue))
  }
  self.custody = physical
  Ok(())
}

///|
pub fn ResidentEffectCheckpointCustody::retry_cleanup(
  self : ResidentEffectCheckpointCustody,
) -> Result[Bool, ResidentEffectCheckpointCustodyIssue] {
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
