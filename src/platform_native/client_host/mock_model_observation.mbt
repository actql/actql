///|
/// Retain the SAME terminal Model's additional publication borrow before its
/// evidence issuer is constructed. The shared issuer quotes its actual row
/// metadata; the existing preserving JSON recipe covers the observation and
/// invocation codec bodies simultaneously. There is no new Root or Ledger.
pub fn NativeClientMockModelWork::prepare_observation(
  self : Self,
) -> Result[Unit, NativeClientMockModelIssue] {
  try {
    guard !self.closing &&
      !self.closed &&
      !self.advancing &&
      self.settlement is None &&
      self.active is Some(active) &&
      self.prepared is Some(prepared) &&
      self.publication_capacity is None &&
      self.observation is None &&
      @model.prepared_model_call_count(prepared) is Some(count) &&
      count <= 2147483645 else {
      return Err(ForeignOriginal)
    }
    // The SAME existing finite observation profile used by ordinary INFER.
    // It emits one original slot per step, including masked/failed outcomes.
    let limits : @infer.ObservationIssuanceLimits = {
      max_slots: count,
      max_wire_bytes: 16384,
      max_work: count + 2,
    }
    guard @infer.original_observation_issuance_metadata_bytes(active, limits)
      is Some(metadata) &&
      @execution.execution_capacity(metadata, metadata) is Some(base) &&
      @local.installed_json_effect_request_construction_capacity(
        base, 16384, 1024, 20,
      )
      is Some(observation) &&
      @local.installed_json_effect_request_construction_capacity(
        observation, 16384, 1024, 20,
      )
      is Some(complete) else {
      return Err(Encoding)
    }
    self.advancing = true
    defer {
      self.advancing = false
    }
    let capacity = mock_model_require(
      @infer.reserve_original_infer_publication_capacity(
        active,
        @execution.execution_capacity_retained_bytes(complete),
        @execution.execution_capacity_execution_bytes(complete),
      ).map_err(issue => NativeClientMockModelIssue::Model(issue)),
    )
    self.publication_capacity = Some(capacity)
    let issued = mock_model_require(
      @infer.start_original_observation_issuance(active, capacity, limits).map_err(issue => {
          NativeClientMockModelIssue::Model(issue)
        },
      ),
    )
    self.observation = Some(issued)
    Ok(())
  } catch {
    NativeMockModelStop(issue) => Err(issue)
  }
}

///|
/// Advance only the original flat evidence issuer, never the Model/provider.
pub fn NativeClientMockModelWork::advance_observation(
  self : Self,
) -> Result[Bool, NativeClientMockModelIssue] {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.observation is Some(issued) &&
    self.publication_capacity is Some(_) else {
    return Err(NotOpened)
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  @infer.advance_observation_issuance(issued, 1)
  .map(value => value.0)
  .map_err(issue => NativeClientMockModelIssue::Model(issue))
}

///|
/// Borrow the already issued original contracts. Their identity is evidence,
/// not a Preview, publication permission, durable save or physical cleanup ACK.
pub fn NativeClientMockModelWork::observation_original(
  self : Self,
) -> (@publication.RunEvidenceValue, @publication.PublicationContract)? {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.publication_capacity is Some(_) &&
    self.observation is Some(issued) else {
    return None
  }
  @infer.observation_issuance_value(issued)
}

///|
fn NativeClientMockModelWork::close_observation(
  self : Self,
) -> Result[Bool, NativeClientMockModelIssue] {
  if self.observation is Some(issued) {
    @infer.cancel_observation_issuance(issued) |> ignore
    // Process cancellation on this SAME bounded issuer; no Model work or
    // publication can restart. Keep it retained on a pending cleanup result.
    @infer.advance_observation_issuance(issued, 1) |> ignore
    match @infer.cleanup_observation_issuance(issued) {
      Err(issue) => return Err(Model(issue))
      Ok(false) => return Ok(false)
      Ok(true) => self.observation = None
    }
  }
  if self.publication_capacity is Some(capacity) {
    match @infer.release_original_infer_publication_capacity(capacity) {
      Err(issue) => return Err(Model(issue))
      Ok(false) => return Ok(false)
      Ok(true) => self.publication_capacity = None
    }
  }
  Ok(true)
}
