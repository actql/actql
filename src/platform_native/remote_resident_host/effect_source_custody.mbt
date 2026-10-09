///|
pub(all) enum ResidentEffectSourceCustodyIssue {
  Unavailable
  Binding(@host.ClientEffectSourceArtifactIssue)
  Store(@publication_store.NativePublicationStoreIssue)
  Capacity(@resources.LedgerIssue)
  RevokedWithCleanup(@publication_store.NativePublicationStoreIssue)
}

///|
pub(all) struct ResidentEffectSourceCustodyFailure {
  issue : ResidentEffectSourceCustodyIssue
  custody : ResidentEffectSourceCustody?
}

///|
/// Retain cleanup responsibility for this Native input before any payload
/// allocation. Failed or uncertain persistence returns the same prepared
/// custody owner; callers must retain it for reconciliation or cleanup.
pub fn ResidentSourceCompute::retain_effect_source_custody(
  self : ResidentSourceCompute,
  store : @publication_store.Store,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  artifact : @host.ClientEffectLocalResultArtifact,
  source : @publication.CapturedEffectSourceArtifact,
  request : @payload.PublicationPayloadRequest,
) -> Result[ResidentEffectSourceCustody, ResidentEffectSourceCustodyFailure] {
  if !self.resident_effect_inputs_current(inputs) {
    return Err({ issue: Unavailable, custody: None, })
  }
  let (digest, bytes) = match
    @host.client_effect_source_payload_binding(
      materials, inputs, member_index, artifact, source, request,
    ) {
    Ok(value) => value
    Err(issue) => return Err({ issue: Binding(issue), custody: None, })
  }
  let custody = match
    store.prepare_effect_source_custody(
      materials.run_definition,
      source,
      request,
      digest,
      bytes.to_int64(),
    ) {
    Ok(value) => value
    Err(issue) => return Err({ issue: Store(issue), custody: None, })
  }
  let key = @payload.publication_payload_material_identity(request)
  let owner = match self.effect_payloads.get(key) {
    Some(value) => {
      if !physical_equal(value.store, store) ||
        value.source != @publication.captured_effect_source_holding_cid(source) ||
        value.digest != digest ||
        @payload.publication_payload_request_identity(value.request) !=
        @payload.publication_payload_request_identity(request) ||
        value.bytes != bytes.to_int64() ||
        value.released {
        return Err({ issue: Unavailable, custody: Some(value), })
      }
      value
    }
    None => {
      let ledger = @strategy.captured_dag_ledger(self.run)
      let reservation = match
        @resources.reserve_attempt(
          ledger,
          0L,
          @payload.publication_payload_request_max_bytes(request),
          0L,
        ) {
        Ok(value) => value
        Err(issue) => return Err({ issue: Capacity(issue), custody: None, })
      }
      let value : ResidentEffectSourceCustody = {
        store,
        custody,
        ledger,
        reservation,
        inputs,
        effect_run: self.effect_run.unwrap(),
        retained: self.effect_retained,
        source_closed: self.source_closed,
        run: materials.run_definition,
        artifact: source,
        request,
        digest,
        bytes: bytes.to_int64(),
        source: @publication.captured_effect_source_holding_cid(source),
        released: false,
      }
      self.effect_payloads.set(key, value)
      value
    }
  }
  match owner.custody.retain() {
    Ok(_) => ()
    Err(issue) => return Err({ issue: Store(issue), custody: Some(owner), })
  }
  if !self.resident_effect_inputs_current(inputs) {
    return Err({ issue: Unavailable, custody: Some(owner), })
  }
  Ok(owner)
}

///|
/// The execution Ledger reservation is independent from Store capacity, the
/// receiver borrow and Named Result retention. It remains live through failed
/// custody/payload/cleanup persistence. No execution permission is restored.
struct ResidentEffectSourceCustody {
  mut store : @publication_store.Store
  mut custody : @publication_store.EffectSourceCustody
  ledger : @resources.Ledger
  reservation : @resources.Reservation
  inputs : @strategy.CapturedEffectInputs
  effect_run : @strategy.CapturedEffectRunDAG
  retained : ResidentEffectRetainedCapture?
  source_closed : Ref[Bool]
  run : @publication.PublicationContract
  artifact : @publication.CapturedEffectSourceArtifact
  request : @payload.PublicationPayloadRequest
  source : String
  digest : String
  bytes : Int64
  mut released : Bool
}

///|
pub fn ResidentEffectSourceCustody::restore_store(
  self : ResidentEffectSourceCustody,
  store : @publication_store.Store,
) -> Result[Unit, ResidentEffectSourceCustodyIssue] {
  if self.released {
    return Err(Unavailable)
  }
  let custody = match
    store.restore_effect_source_custody(
      self.run,
      self.artifact,
      self.request,
      self.digest,
      self.bytes,
    ) {
    Ok(value) => value
    Err(@publication_store.Database(@sqlite.NotFound)) => {
      // This live prepared owner has never dropped its original Ledger charge.
      // Missing metadata cannot have admitted a payload writer; retain its exact
      // intent for cleanup/reconciliation rather than inventing execution state.
      let value = match
        store.prepare_effect_source_custody(
          self.run,
          self.artifact,
          self.request,
          self.digest,
          self.bytes,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Store(issue))
      }
      match value.retain() {
        Ok(_) => ()
        Err(issue) => return Err(Store(issue))
      }
      value
    }
    Err(issue) => return Err(Store(issue))
  }
  self.store = store
  self.custody = custody
  Ok(())
}

///|
pub fn ResidentEffectSourceCustody::begin_payload(
  self : ResidentEffectSourceCustody,
) -> Result[@publication_store.PayloadWriter, ResidentEffectSourceCustodyIssue] {
  if self.released {
    return Err(Unavailable)
  }
  if !self.current() {
    return Err(Unavailable)
  }
  let writer = match self.custody.begin_payload() {
    Ok(value) => value
    Err(issue) => return Err(Store(issue))
  }
  if !self.current() {
    return match writer.cancel() {
      Ok(_) => Err(Unavailable)
      Err(issue) => Err(RevokedWithCleanup(issue))
    }
  }
  Ok(writer)
}

///|
pub fn ResidentEffectSourceCustody::confirm_payload(
  self : ResidentEffectSourceCustody,
) -> Result[
  @publication_store.NativePublicationPayloadInfo,
  ResidentEffectSourceCustodyIssue,
] {
  if self.released {
    return Err(Unavailable)
  }
  if !self.current() {
    return Err(Unavailable)
  }
  self.custody.confirm_payload().map_err(issue => Store(issue))
}

///|
pub fn ResidentEffectSourceCustody::open_reader(
  self : ResidentEffectSourceCustody,
) -> Result[@publication_store.PayloadReader, ResidentEffectSourceCustodyIssue] {
  if self.released {
    return Err(Unavailable)
  }
  if !self.current() {
    return Err(Unavailable)
  }
  self.custody.open_reader().map_err(issue => Store(issue))
}

///|
pub fn ResidentEffectSourceCustody::retry_cleanup(
  self : ResidentEffectSourceCustody,
) -> Result[Bool, ResidentEffectSourceCustodyIssue] {
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

///|
fn ResidentEffectSourceCustody::current(
  self : ResidentEffectSourceCustody,
) -> Bool {
  resident_effect_input_custody_current(
    self.effect_run,
    self.retained,
    self.source_closed,
    self.inputs,
  )
}
