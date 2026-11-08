///|
/// Retain the SAME terminal Model's full preselected publication borrow before
/// its evidence issuer is constructed. The enclosing Plan already includes
/// the raw-outcome export and all three codec bodies. The shared issuer still
/// checks its actual row metadata. There is no new Root or Ledger.
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
    let complete = self._retained_observation_capacity
    guard count <= self._retained_limits.model.max_items &&
      @infer.original_observation_issuance_metadata_bytes(active, limits)
      is Some(metadata) &&
      metadata <= @execution.execution_capacity_retained_bytes(complete) else {
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
  // The command severs its semantic body alias first. Retire this original
  // projection's export/uses before the complete issuer and its same-parent
  // reservation. Cancellation is not Model/Store/physical cleanup evidence.
  self.local_observation = None
  if self.local_scan is Some(scan) {
    @execution.cancel_completed_relation_identity_scan(scan) |> ignore
    self.local_scan = None
  }
  if self.local_receipt is Some(receipt) {
    @execution.cancel_completed_relation_export_receipt(receipt)
    self.local_receipt = None
  }
  if self.local_use is Some(held) {
    @infer.release_output(held) |> ignore
    self.local_use = None
  }
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

///|
/// The complete issuer and its full preselected publication backing already
/// belong to this Work. Retain the original output use before any fallible
/// conversion; a second Model/input execution is never selected here.
pub fn NativeClientMockModelWork::prepare_local_observation(
  self : Self,
) -> Result[Unit, NativeClientMockModelIssue] {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.publication_capacity is Some(_) &&
    self.active is Some(active) &&
    self.observation is Some(issued) &&
    self.local_use is None &&
    self.local_scan is None &&
    self.local_receipt is None &&
    self.local_observation is None else {
    return Err(ForeignOriginal)
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  guard @infer.observation_issuance_value(issued) is Some(_) &&
    @infer.acquire_output(active) is Some(held) else {
    return Err(ForeignOriginal)
  }
  self.local_use = Some(held)
  guard @infer.borrow_original_live_model_relations(
      held,
      self.compiled,
      self.definition,
      self.graph,
    )
    is Some((_, outcomes)) else {
    return Err(ForeignOriginal)
  }
  let limits = self._retained_limits
  let scan = match
    @execution.start_completed_relation_identity_scan(
      outcomes,
      limits.output_rows,
      limits.output_values,
      limits.identity.wire,
      limits.identity.logical_wire,
      limits.identity.schema,
      limits.identity.work,
      limits.identity.workspace,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Model(@infer.IdentityExport(issue)))
  }
  self.local_scan = Some(scan)
  Ok(())
}

///|
/// Advance the original raw-outcome export only. The input CID/schema come
/// from the same CallScope's first completed export, without another scan.
pub fn NativeClientMockModelWork::advance_local_observation(
  self : Self,
) -> Result[Bool, NativeClientMockModelIssue] {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.local_use is Some(held) &&
    self.local_scan is Some(scan) &&
    self.observation is Some(issued) &&
    self.local_observation is None else {
    return Err(ForeignOriginal)
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  let (done, _) = match
    @execution.advance_completed_relation_identity_scan(scan, 31) {
    Ok(value) => value
    Err(issue) => return Err(Model(@infer.IdentityExport(issue)))
  }
  if !done {
    return Ok(false)
  }
  let receipt = match @execution.finish_completed_relation_identity_scan(scan) {
    Ok(value) => value
    Err(issue) => return Err(Model(@infer.IdentityExport(issue)))
  }
  self.local_receipt = Some(receipt)
  guard @infer.issue_original_local_model_observation_from_scope(
      held, issued, receipt, 16384, 1024, 20,
    )
    is Some(observation) else {
    return Err(ForeignOriginal)
  }
  self.local_observation = Some(observation)
  Ok(true)
}

///|
/// This body is a semantic dependency, not its original issuer or permission.
/// Keep the same Work/output/complete issuer until all actual aliases retire.
pub fn NativeClientMockModelWork::local_observation_original(
  self : Self,
) -> @publication.CapturedEffectDependencyBody? {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.local_observation is Some(observation) else {
    return None
  }
  @infer.original_local_model_observation_body(observation)
}
