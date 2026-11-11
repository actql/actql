///|
/// Start with fixed controls, then grow the SAME terminal Model's reservation
/// for its actual flat-issuer inventory before that constructor. No output
/// policy-sized row export is reserved and no Root or Ledger is reissued.
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
      self.observation_issuer_capacity() is Some(issuer_capacity) else {
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
    self.publication_retained = @execution.execution_capacity_retained_bytes(
      complete,
    )
    self.publication_execution = @execution.execution_capacity_execution_bytes(
      complete,
    )
    mock_model_require(self.grow_observation_capacity(issuer_capacity))
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
/// Borrow the original completed Model observations at the Preview boundary.
/// The same issuer performs its current check once for this projection; no
/// capture is replayed, response rehashed or Model/Run issued. The caller's
/// retained capture operation backs the bounded array before entry.
pub fn NativeClientMockModelWork::completed_observation_originals(
  self : Self,
  max_entries : Int,
) -> (
  @publication.RunEvidenceValue,
  @publication.PublicationContract,
  Array[@publication.RunEvidenceValue],
  Array[@publication.RunEvidenceValue],
)? {
  guard max_entries >= 0 &&
    !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.active is Some(active) &&
    self.prepared is Some(prepared) &&
    self.observation is Some(issued) &&
    @model.prepared_model_call_count(prepared) is Some(count) &&
    count <= max_entries else {
    return None
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  guard @infer.observation_issuance_value(issued)
    is Some((observation, invocation)) else {
    return None
  }
  let originals = []
  for slot in 0..<count {
    guard @infer.observation_issuance_slot_outcome(issued, slot)
      is Some(outcome) else {
      return None
    }
    // A response-less failure remains in the original flat observation; it
    // has no successful invocation/response Artifact to add to Preview.
    if outcome == "ok" {
      guard @infer.invocation_evidence(active, slot) is Some(original) else {
        return None
      }
      originals.push(original)
    }
  }
  if self.closing ||
    self.closed ||
    !self.active.map(value => physical_equal(value, active)).unwrap_or(false) ||
    !self.observation
    .map(value => physical_equal(value, issued))
    .unwrap_or(false) {
    return None
  }
  guard @infer.observation_issuance_source_originals(issued) is Some(sources) else {
    return None
  }
  Some((observation, invocation, originals, sources))
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
      Ok(true) => {
        self.publication_capacity = None
        self.publication_retained = 0L
        self.publication_execution = 0L
      }
    }
  }
  Ok(true)
}

///|
/// The original issuer remains held. Add the actual metadata start inventory
/// before constructing it; keep the output use before any fallible conversion.
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
  guard self.observation_issuer_capacity() is Some(base) &&
    @execution.completed_relation_identity_scan_start_construction_capacity(
      outcomes,
      retain_body=true,
    )
    is Some(start) &&
    @execution.add_execution_capacity(base, start) is Some(required) else {
    return Err(Encoding)
  }
  match self.grow_observation_capacity(required) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
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
      incremental_metadata=true,
      retain_body=true,
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
  guard self.observation_issuer_capacity() is Some(base) &&
    @execution.completed_relation_identity_scan_next_construction_capacity(scan)
    is Some(next) &&
    @execution.add_execution_capacity(base, next) is Some(required) else {
    return Err(Encoding)
  }
  match self.grow_observation_capacity(required) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // The Core continuation yields BEFORE a later constructor exceeds these
  // already held bytes. Current/Source is checked once per bounded advance,
  // not again for every covered internal frame.
  let retained = self.publication_retained -
    @execution.execution_capacity_retained_bytes(base)
  let execution = self.publication_execution -
    @execution.execution_capacity_execution_bytes(base)
  guard @execution.execution_capacity(
      Int64::min(retained, execution),
      execution,
    )
    is Some(available) else {
    return Err(Encoding)
  }
  let (done, _) = match
    @execution.advance_completed_relation_identity_scan(
      scan,
      31,
      construction_capacity=Some(available),
    ) {
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
  // The projection already starts with this token's complete held peak,
  // including the body scan/join backing. Add only its actual new writers;
  // independently adding the body again would duplicate retained demand.
  guard self.local_observation_projection_capacity(receipt) is Some(projecting) &&
    @execution.completed_relation_identity_scan_body(scan, receipt) is Some(_) else {
    return Err(Encoding)
  }
  match self.grow_observation_capacity(projecting) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
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

///|
/// Borrow the original Model's semantic Invocation under its existing output
/// and complete issuer. The enclosing member-capture operation backs these
/// metadata constructors before this entry; no Model capacity is reissued.
pub fn NativeClientMockModelWork::local_effect_invocation(
  self : Self,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @host.ClientEffectLocalInvocation? {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.local_observation is Some(observation) else {
    return None
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  @infer.issue_original_local_model_effect_invocation(
    observation, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Original raw outcomes and schema emitted during the SAME local scan. The
/// caller retains these aliases until before Work returns its publication
/// backing. They are semantic DATA, not physical custody or another issuer.
pub fn NativeClientMockModelWork::local_observation_dependency_bodies(
  self : Self,
) -> Array[(String, String)]? {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.local_scan is Some(scan) &&
    self.local_receipt is Some(receipt) &&
    self.local_observation is Some(observation) else {
    return None
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  guard @infer.original_local_model_observation_input_bodies(observation)
    is Some(bodies) &&
    @execution.completed_relation_identity_scan_body(scan, receipt)
    is Some(body) else {
    return None
  }
  bodies.push(("relation_value", body))
  bodies.push(
    (
      "relation_schema",
      @execution.relation_schema_wire(
        @execution.completed_relation_export_schema_identity(receipt),
      ),
    ),
  )
  Some(bodies)
}

///|
/// Original input and outcome scans supply their own CIDs with the bodies.
/// No dependency admission may guess an identity from a body name or omit it
/// for a hashed relation. Existing pair-only readers remain unchanged.
pub fn NativeClientMockModelWork::local_observation_dependency_originals(
  self : Self,
) -> Array[(String, String, String)]? {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.local_scan is Some(scan) &&
    self.local_receipt is Some(receipt) &&
    self.local_observation is Some(observation) else {
    return None
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  guard @infer.original_local_model_observation_input_dependency_bodies(
      observation,
    )
    is Some(bodies) &&
    @execution.completed_relation_identity_scan_body(scan, receipt)
    is Some(body) else {
    return None
  }
  bodies.push(
    (
      "relation_value",
      @execution.logical_relation_cid(
        @execution.completed_relation_export_identity(receipt),
      ),
      body,
    ),
  )
  let schema = @execution.completed_relation_export_schema_identity(receipt)
  bodies.push(
    (
      "relation_schema",
      @execution.relation_schema_cid(schema),
      @execution.relation_schema_wire(schema),
    ),
  )
  // The Core current observation may call out. Finish with this SAME Work's
  // noncallback alias/retirement fence, never another permission observation.
  guard !self.closing &&
    !self.closed &&
    self.local_scan is Some(actual_scan) &&
    physical_equal(actual_scan, scan) &&
    self.local_receipt is Some(actual_receipt) &&
    physical_equal(actual_receipt, receipt) &&
    self.local_observation is Some(actual_observation) &&
    physical_equal(actual_observation, observation) else {
    return None
  }
  Some(bodies)
}

///|
/// Same accepted original Model/Source closure and one semantic Invocation.
/// The caller backs/retains these metadata aliases on its original capture
/// operation; this does not claim keyed attempt provenance or Store custody.
pub fn NativeClientMockModelWork::local_effect_direct_source_evidence(
  self : Self,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@host.ClientEffectLocalInvocation, Array[@host.ClientEffectAcquiredEvidence]),
  @host.ClientEffectAcquiredEvidenceIssue,
] {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.local_observation is Some(observation) else {
    return Err(Invocation(ForeignCapturedInput))
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  let result = @infer.issue_original_local_model_direct_source_evidence(
    observation, retention, max_bytes, max_nodes, max_depth,
  )
  if self.closing ||
    self.closed ||
    !(self.local_observation is Some(original) &&
    physical_equal(original, observation)) {
    return Err(Invocation(ForeignCapturedInput))
  }
  result
}

///|
/// Complete Model Unit provenance from this original Work. No second output
/// use, Model/Source execution or resource owner is created by this projection.
pub fn NativeClientMockModelWork::local_effect_model_acquired_evidence(
  self : Self,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  imports? : @host.ClientEffectImportedEvidence? = None,
) -> Result[
  @host.ClientEffectModelAcquiredEvidence,
  @host.ClientEffectAcquiredEvidenceIssue,
] {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.local_observation is Some(observation) else {
    return Err(Invocation(ForeignCapturedInput))
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  let result = @infer.issue_original_local_model_acquired_evidence(
    observation,
    retention,
    max_bytes,
    max_nodes,
    max_depth,
    imports~,
  )
  if self.closing ||
    self.closed ||
    !self.local_observation
    .map(value => physical_equal(value, observation))
    .unwrap_or(false) {
    return Err(Invocation(ForeignCapturedInput))
  }
  result
}

///|
pub fn NativeClientMockModelWork::local_effect_model_artifact(
  self : Self,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  acquired : @host.ClientEffectModelAcquiredEvidence,
  definition : @host.ClientEffectLocalResultDefinition,
  receipt : @execution.CompletedRelationExportReceipt,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @host.ClientEffectLocalResultArtifact,
  @host.ClientEffectLocalResultArtifactIssue,
] {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.local_observation is Some(observation) else {
    return Err(ForeignOwner)
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  let result = @infer.issue_original_local_model_effect_artifact(
    observation, materials, inputs, exported, acquired, definition, receipt, max_bytes,
    max_nodes, max_depth,
  )
  if self.closing ||
    self.closed ||
    !self.local_observation
    .map(value => physical_equal(value, observation))
    .unwrap_or(false) {
    return Err(ForeignOwner)
  }
  result
}
