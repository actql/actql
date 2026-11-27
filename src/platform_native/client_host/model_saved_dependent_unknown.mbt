///|
// A read-only continuation of the selected saved Run observation. The
// stopped receiver has no settlement or Raw. Its sealed Entry nominates
// only the already completed producers on this exact Run and Store.
fn NativeLocalJournalCapture::restore_saved_dependent_model_unknown_locked(
  self : Self,
  authority : NativeLocalPolicyAuthority,
  run : NativeClientRunRecord,
  store : @publication_store.Store,
  namespace_id : String,
  operation : NativeLocalStoreOperation,
  locator : (String, String),
  reads : NativeClientJournalReadAccess,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let host = authority.host
  guard authority.purpose is ReadRunMaterials &&
    authority.capture is Some(capture) &&
    physical_equal(capture, self) &&
    physical_equal(operation.receiver.capture, self) &&
    operation.receiver.domain is StoreRunObservationDomain &&
    operation.sqlite_original() is Ok(bridge) &&
    store.matches_original_operation(bridge) &&
    self.original_resources is Some(resources) &&
    !namespace_id.is_empty() &&
    run.dispatch_reserved &&
    run.physical_start_claimed &&
    run.checkpoint is None &&
    run.effect_material_originals is None &&
    run.publication_policy_originals is Some(_) &&
    run.run_observation_originals is Some(_) &&
    self.max_snapshot_bytes > 0L &&
    self.max_snapshot_bytes < 2147483519L else {
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
  if run.publication_binding != Some(binding) {
    return Err(ForeignRun)
  }
  let dependency = match
    host.journal
    .read_dependent_model_entry_locked(
      locator.0,
      locator.1,
      self.max_snapshot_bytes,
      reads,
    )
    .bind(body => {
      admit_native_saved_dependent_model_entry(reads, run, body, locator.0)
    }) {
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
  for producer in dependency.producers {
    for slot in producer.slots {
      match require_saved_model_read_current(authority, run, store) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      let original = match
        host.journal.read_saved_model_settlement_locked(
          run,
          binding,
          store_authority,
          ReferencedSuccess(producer.scope, slot),
          self.max_snapshot_bytes,
          reads,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match
        self.verify_saved_dependent_model_success(
          authority, resources, run, store, store_authority, original, key, reads,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
  }
  require_saved_model_read_current(authority, run, store).bind(_ => {
    host.journal.recheck_model_run_cut(run.request, reads)
  })
}

///|
fn NativeLocalJournalCapture::verify_saved_dependent_model_success(
  self : Self,
  authority : NativeLocalPolicyAuthority,
  resources : NativeLocalJournalOriginalResources,
  run : NativeClientRunRecord,
  store : @publication_store.Store,
  store_authority : String,
  original : NativeSavedModelSettlement,
  key : Bytes,
  reads : NativeClientJournalReadAccess,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard original.success is Some(success) else { return Err(CustodyLost) }
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
      (
        @publication_store.Invocation,
        "model_invocation_evidence",
        success.observation_cid,
      ),
      (@publication_store.RawDescriptor, "model_raw_response", original.raw_cid),
    ] {
    match require_saved_model_read_current(authority, run, store) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let value = match
      self
      .read_saved_model_store_leaf(
        resources,
        store,
        run.definition,
        original,
        role,
        cid,
        key,
      )
      .bind(wire => {
        let (nodes, depth) = match role {
          @publication_store.Invocation => (1024, 16)
          _ => (256, 8)
        }
        admit_native_saved_model_leaf(reads, wire, kind, nodes~, depth~)
      }) {
      Ok(value) if @publication.run_evidence_value_identity(value) == cid =>
        value
      Ok(_) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    leaves.push(value)
  }
  let maximum = Int64::min(self.max_snapshot_bytes, 1048576L).to_int()
  let wire = match
    self.read_saved_model_store_leaf(
      resources,
      store,
      run.definition,
      original,
      @publication_store.CaptureBundle(maximum),
      success.bundle_cid,
      key,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let limits = @model.model_call_settlement_export_limits(maximum, maximum)
  let nodes = Int::min(limits.max_nodes, wire.length())
  match
    fund_native_saved_model_leaf(reads, wire, maximum, nodes, limits.max_depth) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard @publication.read_model_capture_bundle(
      wire,
      success.bundle_cid,
      maximum,
      nodes,
      limits.max_depth,
    )
    is Ok(bundle) else {
    return Err(CustodyLost)
  }
  defer @publication.release_model_capture_bundle_read(bundle) |> ignore
  guard @publication.model_capture_bundle_count(bundle) == 1 &&
    @publication.model_capture_bundle_record(bundle, 0) is Ok(record) &&
    @publication.bind_model_slot_capture(original.call, leaves[2])
    is Ok(captured) else {
    return Err(CustodyLost)
  }
  let observation = leaves[3]
  if @publication.run_evidence_value_identity(
      @publication.model_capture_record_evidence(record),
    ) !=
    @publication.run_evidence_value_identity(observation) {
    return Err(CustodyLost)
  }
  @publication.verify_retained_model_http_success(
    run.definition,
    original.scope_cid,
    store_authority,
    captured,
    original.attempt,
    leaves[0],
    leaves[1],
    original.authority,
    observation,
    leaves[4],
  ).map_err(_ => CustodyLost)
}
