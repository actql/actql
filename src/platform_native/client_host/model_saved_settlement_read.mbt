///|
// Only the current saved RunRead lends the original Store, epoch key and
// Journal transaction. The roles below are encrypted evidence metadata.
fn NativeLocalJournalCapture::restore_saved_model_failure_locked(
  self : NativeLocalJournalCapture,
  authority : NativeLocalPolicyAuthority,
  run : NativeClientRunRecord,
  store : @publication_store.Store,
  namespace_id : String,
  operation : NativeLocalStoreOperation,
  locator : (String, String),
  reads : NativeClientJournalReadAccess,
) -> Result[@publication.BoundModelHttpFailure, NativeClientRunJournalIssue] {
  let host = authority.host
  guard authority.purpose is ReadRunMaterials &&
    authority.capture is Some(capture) &&
    physical_equal(capture, self) &&
    physical_equal(operation.receiver.capture, self) &&
    operation.receiver.domain is StoreRunObservationDomain &&
    operation.sqlite_original() is Ok(bridge) &&
    store.matches_original_operation(bridge) &&
    self.original_resources is Some(resources) &&
    !namespace_id.is_empty() else {
    return Err(ForeignRun)
  }
  match require_saved_model_read_current(authority, run, store) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let (store_authority, device, inode) = match store.custody_location() {
    Ok(value) => value
    Err(issue) => return Err(PublicationObservation(issue))
  }
  let (bytes, nodes, depth) = native_mock_model_evidence_key_codec_limits
  guard journal_row_construction_working(bytes, nodes, depth)
    is Some((retained, working, block)) else {
    return Err(CapacityExceeded)
  }
  let (header, _, _, _, _) = @bootstrap.native_managed_value_layout()
  let key_extent = header + 33L
  match
    fund_native_saved_model_construction(
      reads,
      retained + key_extent,
      working + key_extent,
      Int64::max(block, key_extent),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let binding = match
    installed_publication_binding(namespace_id, store_authority, device, inode) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let original = match
    host.journal.read_saved_model_settlement_locked(
      run,
      binding,
      store_authority,
      SavedFailure(locator.0, locator.1),
      self.max_snapshot_bytes,
      reads,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let key = match native_mock_model_evidence_key(host, binding, reads) {
    Ok(value) => value
    Err(Epoch(issue)) => return Err(Epoch(issue))
    Err(Crypto(issue)) => {
      if self.read_operation_issue is None {
        self.read_operation_issue = Some(Crypto(issue))
      }
      return Err(CustodyLost)
    }
    Err(_) => return Err(Encoding)
  }
  let leaves : Array[@publication.RunEvidenceValue] = []
  for
    (role, kind, cid) in [
      (
        @publication_store.Accounting,
        "model_attempt_accounting",
        original.accounting_cid,
      ),
      (
        @publication_store.Outcome,
        "model_attempt_outcome",
        original.outcome_cid,
      ),
      (@publication_store.Capture, "model_slot_capture", original.capture_cid),
      (@publication_store.RawDescriptor, "model_raw_response", original.raw_cid),
    ] {
    match require_saved_model_read_current(authority, run, store) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let wire = match
      self.read_saved_model_store_leaf(
        resources,
        store,
        run.definition,
        original,
        role,
        cid,
        key,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match admit_native_saved_model_leaf(reads, wire, kind) {
      Ok(value) if @publication.run_evidence_value_identity(value) == cid =>
        leaves.push(value)
      Ok(_) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
  }
  let slot = match
    @publication.bind_model_slot_capture(original.call, leaves[2]) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  require_saved_model_read_current(authority, run, store).bind(_ => {
    @publication.bind_retained_model_http_failure(
      run.definition,
      original.scope_cid,
      store_authority,
      locator,
      slot,
      original.attempt,
      leaves[0],
      leaves[1],
      original.authority,
      leaves[3],
    ).map_err(_ => CustodyLost)
  })
}

///|
fn NativeLocalJournalCapture::read_saved_model_store_leaf(
  self : Self,
  resources : NativeLocalJournalOriginalResources,
  store : @publication_store.Store,
  definition : @publication.PublicationContract,
  original : NativeSavedModelSettlement,
  role : @publication_store.ModelSettlementReadRole,
  cid : String,
  key : Bytes,
) -> Result[String, NativeClientRunJournalIssue] {
  let (point, layout) = match
    store.model_settlement_restore_construction(
      definition,
      original.scope_cid,
      original.slot_cid,
      @publication.run_evidence_value_identity(original.attempt),
      role,
      cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(PublicationObservation(issue))
  }
  // The earlier Journal rows and admitted leaves coexist with each new
  // plaintext. Cipher/codec scratch returns before the next role.
  self
  .fund_saved_model_store_read(resources, layout, retained=true)
  .bind(_ => {
    point
    .read_original_wire(self.crypto, key)
    .map_err(issue => PublicationObservation(issue))
  })
}

///|
fn NativeLocalJournalCapture::fund_saved_model_store_read(
  self : Self,
  resources : NativeLocalJournalOriginalResources,
  layout : @publication_store.PrivateEvidenceCustodyConstruction,
  retained~ : Bool,
) -> Result[Unit, NativeClientRunJournalIssue] {
  match
    self.prepare_private_store_layouts_construction(
      1,
      _ => Some(layout),
      additional_retained=resources.metadata_retained,
    ) {
    Ok(quoted) => {
      if retained {
        resources.metadata_retained = quoted
      }
      Ok(())
    }
    Err(Original(issue)) => {
      if self.read_operation_issue is None {
        self.read_operation_issue = Some(issue)
      }
      Err(CapacityExceeded)
    }
    Err(_) => Err(CapacityExceeded)
  }
}

///|
fn require_saved_model_read_current(
  authority : NativeLocalPolicyAuthority,
  run : NativeClientRunRecord,
  store : @publication_store.Store,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !authority.current_for(authority.host.journal, run.request) {
    return Err(AuthorizationDenied)
  }
  store.retained_data_current().map_err(issue => PublicationObservation(issue))
}

///|
type NativeCompletedModelDependencySlot = (Int, String, String, String)

///|
/// One completed producer's authenticated durable references. Multiple
/// receiving ports may borrow this observation. It grants no dispatch.
struct NativeCompletedModelDependencyOriginal {
  producer : NativeClientMockModelWork
  held : @infer.OutputUse
  scope : @publication.BoundModelInvocationScope
  slots : Array[NativeCompletedModelDependencySlot]
  egress : @host.ClientWholeModelEgressOriginal
}

///|
fn native_completed_model_dependency_capacity(count : Int) -> (Int64, Int64)? {
  let count = count.to_int64()
  guard count > 0L &&
    @execution.preparation_array_representation(1L, count, true) is Some(array) &&
    @execution.preparation_representation_cost({
      ..array,
      record_headers: array.record_headers + 4L * count + 6L,
      reference_slots: array.reference_slots + 3L * count + 12L,
      scalar_words: array.scalar_words + count + 4L,
      owned_utf16_units: 71L * (3L * count + 1L),
    })
    is Some(bytes) else {
    return None
  }
  let (header, unit, terminator, array_header, pointer) = @bootstrap.native_managed_value_layout()
  guard @execution.checked_preparation_add_product(array_header, pointer, count)
    is Some(array_block) &&
    @execution.checked_preparation_add_product(header + terminator, unit, 71L)
    is Some(cid_block) else {
    return None
  }
  Some(
    (
      bytes,
      Int64::max(array_block, Int64::max(cid_block, header + 9L * pointer)),
    ),
  )
}

///|
/// Authenticate all entered successful slots on this one completed Work.
/// Borrow the same Journal transaction and stored Raw/bundle for every point.
/// The retained summary contains original references and no response bytes.
pub fn NativeClientMockModelWork::read_completed_model_dependency_in_original_read(
  self : Self,
  held : @infer.OutputUse,
  maximum_bundle_bytes : Int,
  artifact : @host.ClientWholeLocalResultArtifact,
  manifest : @host.ClientWholeLocalResultManifest,
) -> Result[NativeCompletedModelDependencyOriginal, NativeClientMockModelIssue] {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.settlement is None &&
    self.active is Some(active) &&
    physical_equal(held.owner, active) &&
    self.scope is Some(scope) &&
    self.admission is Some(dispatch) &&
    self.provider_role is PortableHttp(http) &&
    http.output_used &&
    http.registration is Some(registration) &&
    @host.client_model_raw_capture_matches(registration, dispatch, scope) &&
    self.capture.original_resources is Some(resources) &&
    @infer.stopped_attempt_count(active) is Some(count) &&
    count > 0 &&
    count <= self._retained_limits.model.max_items &&
    maximum_bundle_bytes > 0 else {
    return Err(ForeignOriginal)
  }
  match self.observe_model_step_in_original_read(physical=false) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.advancing = true
  defer self.release_observed_step()
  let model = match self.completed_dependency_current(held, registration) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let store = http.store
  let (store_authority, device, inode) = match store.custody_location() {
    Ok(value) => value
    Err(issue) => return Err(Store(issue))
  }
  let binding = match
    installed_publication_binding(
      self.namespace_id,
      store_authority,
      device,
      inode,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Original(Journal(issue)))
  }
  guard native_completed_model_dependency_capacity(count)
    is Some((retained, block)) else {
    return Err(Original(ConfigurationLimit))
  }
  match
    self.capture.fund_model_http_material_in_original_read(retained, block) {
    Ok(_) => ()
    Err(issue) => return Err(Transport(issue))
  }
  let limits = @model.model_call_settlement_export_limits(
    Int::min(maximum_bundle_bytes, 1048576),
    self._retained_limits.model.max_work,
  )
  let scope_cid = @publication.model_invocation_scope_cid(scope)
  let dependency = match self.model_entry_dependency(scope_cid) {
    Ok(value) => value
    Err(issue) => return Err(Original(Journal(issue)))
  }
  // Every verified value shares this producing Task's finite Work allowance.
  // The Store and Journal reads also retain their existing bounded arenas.
  let remaining = Ref(self._retained_limits.model.max_work)
  let slots : Array[NativeCompletedModelDependencySlot] = Array(capacity=count)
  self.capture
  .with_current_adoption_material_in_original_read((host, _, operations) => {
    let reads = operations.reads
    let (bytes, nodes, depth) = native_mock_model_evidence_key_codec_limits
    guard journal_row_construction_working(bytes, nodes, depth)
      is Some((retained, working, block)) else {
      return Err(Journal(CapacityExceeded))
    }
    let (header, _, _, _, _) = @bootstrap.native_managed_value_layout()
    let key_extent = header + 33L
    match
      fund_native_saved_model_construction(
        reads,
        retained + key_extent,
        working + key_extent,
        Int64::max(block, key_extent),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Journal(issue))
    }
    let key = match native_mock_model_evidence_key(host, binding, reads) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    host.journal
    .transaction_with_reads(
      () => {
        let run = match host.journal.retained(self.request, reads=Some(reads)) {
          Ok(Some(value)) => value
          Ok(None) => return Err(ForeignRun)
          Err(issue) => return Err(issue)
        }
        guard !run.cancellation_requested() &&
          self.matches_model_call_journal_run(run) else {
          return Err(ForeignRun)
        }
        for index in 0..<count {
          if remaining.val <= 0 {
            return Err(CapacityExceeded)
          }
          remaining.val -= 1
          guard @infer.stopped_attempt_slot(active, index) is Some(slot) &&
            @infer.attempt_evidence(active, slot) is Ok(evidence) &&
            @infer.invocation_evidence(active, slot) is Some(observation) else {
            return Err(CustodyLost)
          }
          let attempt = @model.model_attempt_identity(evidence)
          let attempt_cid = @publication.run_evidence_value_identity(attempt)
          let observation_cid = @publication.run_evidence_value_identity(
            observation,
          )
          let original = match
            host.journal.read_saved_model_settlement_locked(
              run,
              binding,
              store_authority,
              DependentSuccess(attempt_cid, {
                slot,
                scope_cid,
                observation_cid,
                dependency,
              }),
              self.capture.max_snapshot_bytes,
              reads,
            ) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          match
            self.verify_completed_dependency_store(
              resources, http, scope, model, evidence, observation, original, slot,
              limits, key, reads, remaining,
            ) {
            Ok(value) => slots.push(value)
            Err(issue) => return Err(issue)
          }
        }
        host.journal.recheck_model_run_cut(self.request, reads)
      },
      reads=Some(reads),
    )
    .map_err(issue => Journal(issue))
  })
  .map_err(issue => NativeClientMockModelIssue::Original(issue))
  .bind(_ => {
    // Time and Account can change during the Store call. The same Work stays
    // guarded while the original observer refreshes both before delivery.
    self
    .observe_model_step_in_original_read(physical=true, under_advance=true)
    .bind(_ => self.completed_dependency_current(held, registration))
    .bind(_ => {
      @infer.original_live_whole_model_egress(
        held,
        self.compiled,
        self.definition,
        self.graph,
        artifact,
        manifest,
      ).map_err(issue => NativeClientMockModelIssue::Egress(issue))
    })
    .bind(egress => {
      guard self.scope is Some(current) &&
        physical_equal(current, scope) &&
        http.registration is Some(current) &&
        physical_equal(current, registration) &&
        @infer.stopped_attempt_count(active) == Some(count) else {
        return Err(ForeignOriginal)
      }
      Ok({ producer: self, held, scope, slots, egress, })
    })
  })
}

///|
fn NativeClientMockModelWork::completed_dependency_current(
  self : Self,
  held : @infer.OutputUse,
  registration : @host.ClientModelRawCaptureRegistration,
) -> Result[@model.ModelExecution, NativeClientMockModelIssue] {
  match self.capture.check_current_in_original_read() {
    Ok(_) => ()
    Err(issue) => return Err(Original(issue))
  }
  match @host.check_client_model_raw_capture_current(registration) {
    Ok(_) => ()
    Err(issue) => return Err(Transport(RawPolicy(issue)))
  }
  guard self.active is Some(active) &&
    physical_equal(active, held.owner) &&
    @infer.call_scope(active) is Some(call) &&
    @infer.output(held) is Some(output) &&
    @execution.completed_output_available(output) &&
    @infer.borrow_original_live_host_output(
      held,
      self.compiled,
      self.definition,
      self.graph,
    )
    is Some((_, model)) &&
    @infer.call_scope(active) is Some(current) &&
    physical_equal(call, current) &&
    @host.client_whole_model_terminal_output_matches(call, output) else {
    return Err(ForeignOriginal)
  }
  Ok(model)
}

///|
fn NativeClientMockModelWork::verify_completed_dependency_store(
  self : Self,
  resources : NativeLocalJournalOriginalResources,
  http : NativeClientModelHttpWork,
  scope : @publication.BoundModelInvocationScope,
  model : @model.ModelExecution,
  evidence : @model.ModelAttemptEvidence,
  observation : @publication.RunEvidenceValue,
  original : NativeSavedModelSettlement,
  slot : Int,
  limits : @model.ModelCaptureExportLimits,
  key : Bytes,
  reads : NativeClientJournalReadAccess,
  remaining_work : Ref[Int],
) -> Result[NativeCompletedModelDependencySlot, NativeClientRunJournalIssue] {
  let attempt = @model.model_attempt_identity(evidence)
  let authority = @model.model_attempt_authority(evidence)
  let accounting = @model.model_attempt_accounting(evidence)
  let outcome = @model.model_attempt_outcome(evidence)
  guard original.success is Some(success) &&
    http.registration is Some(registration) &&
    @publication.model_invocation_scope_slot(scope, slot)
    is Some((slot_cid, _, _)) &&
    original.slot_cid == slot_cid &&
    @publication.run_evidence_value_identity(authority) ==
    @publication.run_evidence_value_identity(original.authority) &&
    @publication.run_evidence_value_identity(accounting) ==
    original.accounting_cid &&
    @publication.run_evidence_value_identity(outcome) == original.outcome_cid &&
    @publication.check_model_invocation_attempt(
      scope, slot, attempt, authority, 1L,
    )
    is Ok(_) else {
    return Err(CustodyLost)
  }
  let store = http.store
  let capture = self.capture
  let leaves = []
  for
    (role, kind, cid) in [
      (
        @publication_store.Accounting,
        "model_attempt_accounting",
        original.accounting_cid,
      ),
      (
        @publication_store.Outcome,
        "model_attempt_outcome",
        original.outcome_cid,
      ),
      (@publication_store.Capture, "model_slot_capture", original.capture_cid),
      (
        @publication_store.Invocation,
        "model_invocation_evidence",
        success.observation_cid,
      ),
      (@publication_store.RawDescriptor, "model_raw_response", original.raw_cid),
    ] {
    let wire = match
      capture.read_saved_model_store_leaf(
        resources,
        store,
        self.definition,
        original,
        role,
        cid,
        key,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let (nodes, depth) = match role {
      @publication_store.Invocation => (1024, 16)
      _ => (256, 8)
    }
    match admit_native_saved_model_leaf(reads, wire, kind, nodes~, depth~) {
      Ok(value) if @publication.run_evidence_value_identity(value) == cid =>
        leaves.push(value)
      Ok(_) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
  }
  guard @publication.bind_model_slot_capture(original.call, leaves[2])
    is Ok(captured) &&
    @publication.bind_model_slot_attempt_evidence(
      captured,
      original.attempt,
      leaves[0],
      leaves[1],
      original.authority,
      self.compiled.admission,
      self.definition,
    )
    is Ok(bound) &&
    success.observation_cid ==
    @publication.run_evidence_value_identity(observation) &&
    @publication.bind_model_raw_response(
      @host.client_model_raw_capture_policy(registration),
      leaves[4],
      scope,
      slot,
      original.attempt,
      original.authority,
    )
    is Ok(raw) &&
    @publication.verify_model_attempt_success_raw(bound, scope, leaves[3], raw)
    is Ok(_) else {
    return Err(CustodyLost)
  }
  let (point, layout) = match store.model_entered_raw_read_construction(raw) {
    Ok(value) => value
    Err(issue) => return Err(PublicationObservation(issue))
  }
  match capture.fund_saved_model_store_read(resources, layout, retained=false) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match point.verify_original(capture.crypto, key) {
    Ok(_) => ()
    Err(issue) => return Err(PublicationObservation(issue))
  }
  let wire = match
    capture.read_saved_model_store_leaf(
      resources,
      store,
      self.definition,
      original,
      @publication_store.CaptureBundle(limits.max_bytes),
      success.bundle_cid,
      key,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let bundle = match
    read_native_saved_model_capture_bundle(
      reads,
      wire,
      success.bundle_cid,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  defer @publication.release_model_capture_bundle_read(bundle) |> ignore
  guard @publication.model_capture_bundle_count(bundle) == 1 &&
    @publication.model_capture_bundle_record(bundle, 0) is Ok(record) &&
    @publication.run_evidence_value_identity(
      @publication.model_capture_record_evidence(record),
    ) ==
    success.observation_cid else {
    return Err(CustodyLost)
  }
  match
    @model.verify_completed_model_capture_value(
      model,
      slot,
      record,
      peak => {
        fund_native_saved_model_construction(reads, 0L, peak, peak) is Ok(_)
      },
      remaining_work=Some(remaining_work),
    ) {
    Ok(_) => ()
    Err(@model.Ledger(_) | @model.WorkLimit) => return Err(CapacityExceeded)
    Err(_) => return Err(CustodyLost)
  }
  Ok(
    (
      slot,
      @publication.run_evidence_value_identity(attempt),
      original.raw_cid,
      success.bundle_cid,
    ),
  )
}
