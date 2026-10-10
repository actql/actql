///|
pub(all) enum ResidentEffectReviewRetentionIssue {
  Unavailable
  InvalidConfiguration
  Capture(ResidentEffectCaptureCustodyIssue)
  Preview(ResidentEffectPreviewCustodyIssue)
  Preparation(ResidentEffectReviewCheckpointIssue)
  Checkpoint(ResidentEffectCheckpointCustodyIssue)
}

///|
/// A finite connection between the existing three evidence custody owners.
/// The caller retains the original input borrow and computation independently.
/// This connection grants no waiting commit, approval, execution or release
/// authority, and never acquires Source data or observes a Provider again.
struct ResidentEffectReviewRetention {
  consumer : ResidentSourceCompute
  materials : @host.ClientEffectRunMaterials
  inputs : @strategy.CapturedEffectInputs
  result : ResidentEffectResultCapture
  invocation : @publication.PublicationContract
  preview : @strategy.CapturedEffectPreviewInputs
  captured : @publication.PublicationContract
  wire : String
  authoring_cid : String
  request : @host.ClientRequestIdentity
  authority : String
  crypto : @signature.Library
  key : Bytes
  checkpoint_id : String
  created_at : String
  expires_at : String
  limits : @checkpoint.WireLimits
  mut capture_owner : ResidentEffectCaptureCustody?
  mut preview_owner : ResidentEffectPreviewCustody?
  mut review : ResidentEffectReviewCheckpoint?
  mut checkpoint_owner : ResidentEffectCheckpointCustody?
  mut capture_saved : Bool
  mut preview_saved : Bool
  mut retiring : Bool
  mut retired : Bool
}

///|
/// Retain the original typed facts before the first persistence attempt. A
/// failed persist leaves this handle responsible for every allocated custody;
/// callers must retry or clean it up before dropping their input borrow.
pub fn ResidentSourceCompute::prepare_effect_review_retention(
  self : ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  result : ResidentEffectResultCapture,
  invocation : @publication.PublicationContract,
  preview : @strategy.CapturedEffectPreviewInputs,
  captured : @publication.PublicationContract,
  wire : String,
  authoring_cid : String,
  authority : String,
  crypto : @signature.Library,
  key : Bytes,
  checkpoint_id : String,
  created_at : String,
  expires_at : String,
  limits : @checkpoint.WireLimits,
) -> Result[ResidentEffectReviewRetention, ResidentEffectReviewRetentionIssue] {
  let request = match self.request_for_effect_review(inputs) {
    Some(value) if materials.request == Some(value) => value
    _ => return Err(Unavailable)
  }
  if !self.resident_effect_inputs_current(inputs) {
    return Err(Unavailable)
  }
  if key.length() != 32 ||
    limits.max_wire_bytes < 1 ||
    limits.max_wire_bytes > 262144 ||
    limits.max_nodes < 1 ||
    limits.max_nodes > 10000 ||
    limits.max_depth < 1 ||
    limits.max_depth > 64 {
    return Err(InvalidConfiguration)
  }
  Ok({
    consumer: self,
    materials,
    inputs,
    result,
    invocation,
    preview,
    captured,
    wire,
    authoring_cid,
    request,
    authority,
    crypto,
    key: key[:].to_owned(),
    checkpoint_id,
    created_at,
    expires_at,
    limits,
    capture_owner: None,
    preview_owner: None,
    review: None,
    checkpoint_owner: None,
    capture_saved: false,
    preview_saved: false,
    retiring: false,
    retired: false,
  })
}

///|
/// Persist and authenticate computation, Preview and their exact Checkpoint in
/// that order. Uncertain commits retain the original owners and reservations.
/// Repeating this operation uses the cached typed facts, not another Provider
/// read, new request identity, fresh lifetime or replacement holding.
pub fn ResidentEffectReviewRetention::persist(
  self : ResidentEffectReviewRetention,
  store : @publication_store.Store,
) -> Result[
  @remote.RemoteEffectCheckpointReport,
  ResidentEffectReviewRetentionIssue,
] {
  if self.retiring || !self.consumer.resident_effect_inputs_current(self.inputs) {
    return Err(Unavailable)
  }
  if !self.capture_saved {
    match
      self.consumer.persist_effect_capture(
        store,
        self.materials,
        self.inputs,
        self.result,
        self.invocation,
        self.preview,
        self.captured,
        self.authority,
        self.crypto,
        self.key,
        self.limits.max_wire_bytes,
        self.limits.max_nodes,
        self.limits.max_depth,
      ) {
      Ok(owner) => {
        self.capture_owner = Some(owner)
        self.capture_saved = true
      }
      Err(failure) => {
        if failure.custody is Some(owner) {
          self.capture_owner = Some(owner)
        }
        return Err(Capture(failure.issue))
      }
    }
  }
  let capture = self.capture_owner.unwrap()
  match capture.confirm() {
    Ok(_) => ()
    Err(issue) => return Err(Capture(issue))
  }
  if !self.preview_saved {
    match
      self.consumer.persist_effect_preview(
        store,
        self.materials,
        self.inputs,
        self.result,
        self.invocation,
        self.preview,
        self.captured,
        self.wire,
        self.authoring_cid,
        self.authority,
        self.crypto,
        self.key,
        self.limits.max_wire_bytes,
        self.limits.max_nodes,
        self.limits.max_depth,
      ) {
      Ok(owner) => {
        self.preview_owner = Some(owner)
        self.preview_saved = true
      }
      Err(failure) => {
        if failure.custody is Some(owner) {
          self.preview_owner = Some(owner)
        }
        return Err(Preview(failure.issue))
      }
    }
  }
  let preview = self.preview_owner.unwrap()
  match preview.confirm() {
    Ok(_) => ()
    Err(issue) => return Err(Preview(issue))
  }
  let review = match self.review {
    Some(value) => value
    None =>
      match
        self.consumer.prepare_effect_review_checkpoint(
          self.materials,
          self.inputs,
          self.request,
          capture,
          preview,
          self.checkpoint_id,
          self.created_at,
          self.expires_at,
          self.limits,
        ) {
        Ok(value) => {
          self.review = Some(value)
          value
        }
        Err(issue) => return Err(Preparation(issue))
      }
  }
  match
    self.consumer.persist_effect_review_checkpoint(
      store,
      self.inputs,
      review,
      self.crypto,
      self.key,
    ) {
    Ok(owner) => self.checkpoint_owner = Some(owner)
    Err(failure) => {
      if failure.custody is Some(owner) {
        self.checkpoint_owner = Some(owner)
      }
      return Err(Checkpoint(failure.issue))
    }
  }
  self.report()
}

///|
/// Reattach all still-owned encrypted records after Store reopening. This
/// keeps the live Ledger charges; it is not Host restart or authorization.
pub fn ResidentEffectReviewRetention::restore_store(
  self : ResidentEffectReviewRetention,
  store : @publication_store.Store,
) -> Result[Unit, ResidentEffectReviewRetentionIssue] {
  if self.retired {
    return Err(Unavailable)
  }
  if self.capture_owner is Some(owner) && !owner.released {
    match owner.restore_store(store) {
      Ok(_) => ()
      Err(issue) => return Err(Capture(issue))
    }
  }
  if self.preview_owner is Some(owner) && !owner.released {
    match owner.restore_store(store) {
      Ok(_) => ()
      Err(issue) => return Err(Preview(issue))
    }
  }
  if self.checkpoint_owner is Some(owner) && !owner.released {
    match owner.restore_store(store) {
      Ok(_) => ()
      Err(issue) => return Err(Checkpoint(issue))
    }
  }
  Ok(())
}

///|
/// Only a confirmed original pair can be reported. This does not commit the
/// Cloud Run to waiting or imply that an approval was accepted.
pub fn ResidentEffectReviewRetention::report(
  self : ResidentEffectReviewRetention,
) -> Result[
  @remote.RemoteEffectCheckpointReport,
  ResidentEffectReviewRetentionIssue,
] {
  if self.retiring {
    return Err(Unavailable)
  }
  match self.checkpoint_owner {
    Some(owner) => owner.report(self.limits).map_err(issue => Checkpoint(issue))
    None => Err(Unavailable)
  }
}

///|
/// Hand the original Run Owner the common-issued persistence witness only
/// after authenticating all three existing custody Owners. Equal report bytes
/// do not substitute for those holdings or authorize a waiting transition.
pub fn ResidentEffectReviewRetention::confirm_original_checkpoint(
  self : ResidentEffectReviewRetention,
  consumer : ResidentSourceCompute,
  request : @host.ClientRequestIdentity,
  run_definition : @publication.PublicationContract,
) -> Result[@checkpoint.PersistedCheckpoint, ResidentEffectReviewRetentionIssue] {
  if self.retiring ||
    self.retired ||
    !physical_equal(self.consumer, consumer) ||
    self.request != request ||
    @publication.publication_contract_identity(self.materials.run_definition) !=
    @publication.publication_contract_identity(run_definition) ||
    !consumer.resident_effect_inputs_current(self.inputs) {
    return Err(Unavailable)
  }
  guard self.capture_saved &&
    self.preview_saved &&
    self.capture_owner is Some(capture) &&
    self.preview_owner is Some(preview) &&
    self.checkpoint_owner is Some(checkpoint) else {
    return Err(Unavailable)
  }
  match capture.confirm() {
    Ok(_) => ()
    Err(issue) => return Err(Capture(issue))
  }
  match preview.confirm() {
    Ok(_) => ()
    Err(issue) => return Err(Preview(issue))
  }
  let (persisted, _) = match checkpoint.confirm() {
    Ok(value) => value
    Err(issue) => return Err(Checkpoint(issue))
  }
  if self.retiring || !consumer.resident_effect_inputs_current(self.inputs) {
    return Err(Unavailable)
  }
  Ok(persisted)
}

///|
/// Called only after the caller discharges review/recovery obligations. Each
/// existing owner confirms retirement before returning its reservation. The
/// input borrow, producer, receiver and Named Result remain separately owned.
pub fn ResidentEffectReviewRetention::retry_cleanup(
  self : ResidentEffectReviewRetention,
) -> Result[Bool, ResidentEffectReviewRetentionIssue] {
  if self.retired {
    return Ok(false)
  }
  self.retiring = true
  if self.checkpoint_owner is Some(owner) {
    match owner.retry_cleanup() {
      Ok(_) => ()
      Err(issue) => return Err(Checkpoint(issue))
    }
  }
  if self.preview_owner is Some(owner) {
    match owner.retry_cleanup() {
      Ok(_) => ()
      Err(issue) => return Err(Preview(issue))
    }
  }
  if self.capture_owner is Some(owner) {
    match owner.retry_cleanup() {
      Ok(_) => ()
      Err(issue) => return Err(Capture(issue))
    }
  }
  self.retired = true
  Ok(true)
}
