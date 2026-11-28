///|
fn file_publication_preflight(
  value : Instance,
  work : StoredSDKFileCaptureWork,
) -> Bool {
  value.publication_preflights
  .values()
  .any(child => {
    child.origin is FilePublicationPreflight(file) &&
    physical_equal(file.work, work)
  })
}

///|
fn file_preflight_issue(
  issue : @local_run.LocalCapturedTaskPublicationPreflightIssue[Int],
) -> Int {
  match issue {
    Binding(issue) => sdk_publication_binding_issue(issue)
    Intent(InventoryLimit) => -4
    Intent(ComputeAlreadyStarted) => -33
    Intent(_) => -32
    Payload(PayloadLimit) => -4
    Payload(RequestMismatch) => -35
    Payload(_) => -32
    Source(CleanupPending) => -9
    Source(InsufficientCapacity | MetadataCapacityUnavailable) => -4
    Source(_) => -35
  }
}

///|
/// One Read of the held physical claim covers both observation and use.
/// The callbacks recheck that same reader and the live Work, without opening
/// another read during a physical Store transaction.
fn[T] with_file_publication_preflight_read(
  value : Instance,
  file : StoredFilePublicationPreflight,
  consume : (
    @local_run.LocalCapturedTaskStartObservation[Ref[Int], Int],
    @local_host.ClientInstalledManagedRun,
    @row_host.RowSourceCapture,
    @query.CapturedSourceRelationIdentity,
    StoredRunConfiguration,
    @host.ClientSavedSubmissionSnapshot,
    @host.ClientJournalPhysicalRow,
    () -> Result[Unit, @local_run.LocalRunPublicationBindingIssue[Int]],
  ) -> Result[T, Int],
  selected_file_projection? : Bool = false,
) -> Result[T, Int] {
  let work = file.work
  guard !work.closing &&
    !work.failed &&
    work.invocation_ready &&
    work.invocation is Some(invocation) &&
    value.physical_starts.get(file.start) is Some(custody) &&
    custody.file_managed is Some(managed) &&
    !managed.closing &&
    managed.capture_work is Some(active) &&
    physical_equal(active, work) &&
    managed.source.capture == Some(work.source) &&
    sdk_file_physical_claim(value, custody) is Some((step, claim)) &&
    claim.observed is Some(observed) &&
    value.materials.get(step) is Some(material) &&
    value.original_metadata.get(work.source) is Some(original) &&
    original.produced &&
    !original.output_closed &&
    original.project is Some(FileCapture(child)) &&
    child.start == file.start &&
    child.captured is Some(source) &&
    child.identity is Some(identity) else {
    return Err(-35)
  }
  let owner = match
    @local_host.observe_request_capture_transfer(managed.transfer) {
    Ok(Some(owner)) => owner
    Err(CleanupPending) => return Err(-9)
    _ => return Err(-35)
  }
  let result = with_sdk_file_start_read(
    value,
    step,
    material,
    claim,
    true,
    (_, _, configuration, snapshot, locator, current, _) => {
      fn recheck() -> Result[
        Unit,
        @local_run.LocalRunPublicationBindingIssue[Int],
      ] {
        current()
        .map_err(code => {
          @local_run.LocalRunPublicationBindingIssue::Current(
            @host.ClientLocalAdoptedCurrentIssue::Physical(code),
          )
        })
        .bind(_ => {
          guard managed.capture_work is Some(active) &&
            physical_equal(active, work) &&
            !work.closing &&
            !work.failed &&
            work.invocation_ready &&
            work.invocation is Some(actual) &&
            physical_equal(actual, invocation) &&
            claim.observed is Some(actual_claim) &&
            physical_equal(actual_claim, observed) &&
            value.original_metadata.get(work.source) is Some(still) &&
            physical_equal(still, original) &&
            still.produced &&
            !still.output_closed else {
            return Err(@local_run.CustodyLost)
          }
          Ok(())
        })
      }
      match recheck() {
        Err(issue) => return Err(sdk_publication_binding_issue(issue))
        Ok(_) => ()
      }
      consume(
        observed, owner, source, identity, configuration, snapshot, locator, recheck,
      )
    },
    live=Some((file.start, custody, managed)),
    preflight=Some(file),
    selected_file_projection~,
  )
  let retired = sdk_file_start_retire_read(value, claim)
  match result {
    Err(code) => Err(code)
    Ok(_) if retired != 0 => Err(retired)
    Ok(value) => Ok(value)
  }
}

///|
fn file_publication_preflight_current(
  value : Instance,
  file : StoredFilePublicationPreflight,
  account : @authorization.AdmittedAccountConfiguration,
  selected_file_projection? : Bool = false,
) -> Int {
  guard file.prepared is Some(preflight) else { return -2 }
  match
    with_file_publication_preflight_read(
      value,
      file,
      (_, _, _, _, configuration, snapshot, locator, current) => {
        @local_run.check_local_captured_task_publication_preflight_current(
          preflight,
          snapshot,
          locator,
          account,
          configuration.context_cid,
          current,
        ).map_err(file_preflight_issue)
      },
      selected_file_projection~,
    ) {
    Ok(_) => 0
    Err(code) => code
  }
}

///|
/// Use the issuer's own Definition bound for each checked name and bounded
/// Request/Attempt keys. Only the preimages of this inventory enter the quote.
fn checked_publication_preflight_capacity(
  prepared : @host.PreparedClientProgram,
  run_namespace : String,
  clock : @local_run.LocalCapturedTaskPublicationClock,
  count : Int,
  limits : @local_run.LocalPublicationIntentLimits,
  retention : @publication.PublicationContract,
) -> (Int64, Int64)? {
  guard @publication.publication_contract_wire_usage(retention)
    is Some((retention_bytes, retention_nodes, _)) else {
    return None
  }
  let graph = @host.prepared_client_graph(prepared)
  let mut names = 0L
  for index in 0..<count {
    guard @strategy.graph_result_name(graph, index) is Some(name) else {
      return None
    }
    guard @execution.checked_preparation_add_product(
        names,
        name.length().to_int64(),
        1L,
      )
      is Some(next) &&
      next <= 2147483647L else {
      return None
    }
    names = next
  }
  let size = count.to_int64()
  let definition = 512L * size + 6L * names
  let limit = limits.max_wire_bytes.to_int64()
  let request = Int64::min(
    limit,
    1024L + 6L * run_namespace.length().to_int64() + 192L * size + 6L * names,
  )
  let attempt = Int64::min(
    limit,
    1024L +
    6L *
    (
      clock.attempt_id.length().to_int64() +
      clock.fence_cid.length().to_int64() +
      clock.external_idempotency_key
      .map(key => key.length().to_int64())
      .unwrap_or(0L)
    ),
  )
  // Retention projection changes two canonical CID strings with the same
  // geometry. All Results borrow the one derived original.
  let bytes = definition + request + attempt + retention_bytes.to_int64()
  let retention_slots = retention_nodes.to_int64()
  // Bounded encoder, admission and comparison representations share one
  // original reservation. Retained contracts and the vectors coexist.
  guard limit > 0L &&
    bytes <= 2147483647L &&
    @host.client_protocol_metadata_construction_bytes(
      bytes.to_int(),
      26L + 12L * size + retention_slots,
      copies=2,
    )
    is Some((retained, _)) &&
    @host.client_protocol_metadata_construction_bytes(
      bytes.to_int(),
      34L + 24L * size + 2L * retention_slots,
      copies=6,
    )
    is Some((execution, _)) else {
    return None
  }
  Some((retained, execution))
}

///|
fn prepare_file_publication_preflight(
  value : Instance,
  record : StoredPublicationPreflight,
  file : StoredFilePublicationPreflight,
  current : StoredRunConfiguration,
) -> Int {
  if value.closing || value.runtime_closing || record.closing {
    return -5
  }
  if record.produced {
    return file_publication_preflight_current(value, file, current.account)
  }
  if record.invoked || record.pending {
    return -33
  }
  guard file.work.invocation is Some(invocation) &&
    file.work.host is Some((_, dag, _)) else {
    return -35
  }
  record.invoked = true
  let borrow = match record.borrow {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) else { return -31 }
  let clock = match sdk_publication_preflight_clock(cursor) {
    Ok(value) => value
    Err(code) => return code
  }
  let limits : @local_run.LocalPublicationIntentLimits = {
    max_results: value.workspace_slots,
    max_wire_bytes: 1048576,
    max_nodes: 100000,
    max_depth: 64,
  }
  let ledger = @strategy.captured_dag_ledger(dag)
  record.pending = true
  let result = build_file_publication_preflight(
    value, record, file, current, invocation, clock, limits, ledger,
  )
  record.pending = false
  result
}

///|
fn build_file_publication_preflight(
  value : Instance,
  record : StoredPublicationPreflight,
  file : StoredFilePublicationPreflight,
  current : StoredRunConfiguration,
  invocation : StoredSDKFilePublicationOriginal,
  clock : @local_run.LocalCapturedTaskPublicationClock,
  limits : @local_run.LocalPublicationIntentLimits,
  ledger : @resources.Ledger,
) -> Int {
  let held_bytes : Ref[Int64] = Ref(0L)
  let result = with_file_publication_preflight_read(value, file, (
    observed,
    owner,
    source,
    identity,
    original,
    snapshot,
    locator,
    recheck,
  ) => {
    if original.sdk is None || !physical_equal(original, current) {
      return Err(-35)
    }
    @local_run.prepare_local_captured_task_publication_preflight(
      observed,
      owner,
      source,
      identity,
      invocation.invocation,
      snapshot,
      locator,
      current.account,
      current.context_cid,
      clock,
      limits,
      recheck,
      (count, limits) => {
        guard file.capacity is None &&
          checked_publication_preflight_capacity(
            file.work.prepared,
            original.run_namespace,
            clock,
            count,
            limits,
            @host.client_local_run_policy_original_retention(
              invocation._finite_policy,
            ),
          )
          is Some((retained, execution)) else {
          return Err(@local_run.CapacityExceeded)
        }
        match @resources.reserve_capacity(ledger, retained, execution) {
          Err(_) => Err(@local_run.CapacityExceeded)
          Ok(capacity) => {
            file.capacity = Some((ledger, capacity))
            held_bytes.val = retained
            Ok(())
          }
        }
      },
    ).map_err(file_preflight_issue)
  })
  let preflight = match result {
    Err(code) => return code
    Ok(preflight) => preflight
  }
  // Keep the owner even if shrinking or output supply refuses. The original
  // close disposes of it before releasing the ledger reservation.
  file.prepared = Some(preflight)
  guard file.capacity is Some((_, capacity)) else { return -4 }
  if @resources.shrink_capacity_reservation(
      ledger,
      capacity,
      held_bytes.val,
      0L,
    )
    is Err(_) {
    return -4
  }
  let checked = file_publication_preflight_current(value, file, current.account)
  if checked != 0 {
    return checked
  }
  if record.closing || value.closing || value.runtime_closing {
    return -5
  }
  let (request, attempt) = @local_run.local_captured_task_publication_preflight_contracts(
    preflight,
  )
  supply_publication_preflight(value, record, request, attempt)
}

///|
/// An ordinary close cannot discard preflight backing while its exact
/// synchronous Read is still retained. This does not infer a physical ACK.
fn file_preflight_read_active(
  value : Instance,
  file : StoredFilePublicationPreflight,
) -> Bool {
  value.physical_starts.get(file.start) is Some(custody) &&
  custody.sdk_step is Some(handle) &&
  value.materials.get(handle) is Some({ file_start: Some(claim), .. }) &&
  claim.reading is Some(FileStartPreflightRead(owner)) &&
  physical_equal(owner, file)
}

///|
/// Only the trusted Host's serialized terminal cleanup may enter this after
/// the Wasm invocation unwinds. Close ports still require their original
/// physical returns; clearing these call latches frees no resource and
/// acknowledges no Reader, Stop, write or transaction.
pub fn begin_file_prepublication_cleanup_after_unwind(
  nonce : Int64,
  handle : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publication_preflights.get(handle) is Some(parent) &&
    parent.origin is FilePublicationPreflight(file) &&
    value.physical_starts.get(file.start) is Some(custody) &&
    custody.file_managed is Some(managed) &&
    managed.capture_work is Some(work) &&
    physical_equal(work, file.work) &&
    managed.source.capture == Some(work.source) &&
    sdk_file_physical_claim(value, custody) is Some((_, claim)) else {
    return -2
  }
  // A publisher may be retained, but no publication or payload past this
  // preflight is part of this terminal entrance.
  if value.publications.values().any(record => record.preflight == handle) {
    return -9
  }
  seal_interrupted_file_prepublication(value, handle, parent, file, claim)
}

///|
/// Apply the terminal transition only after the entry has selected the
/// actual preflight, physical start and adopted Work.
fn seal_interrupted_file_prepublication(
  value : Instance,
  handle : Int,
  parent : StoredPublicationPreflight,
  file : StoredFilePublicationPreflight,
  claim : StoredSDKFileStart,
) -> Int {
  let work = file.work
  match claim.reading {
    Some(FileStartPreflightRead(owner)) if !physical_equal(owner, file) =>
      return -35
    Some(FileStartMaterialRead) => return -9
    _ => ()
  }
  for result in value.result_exports.values() {
    if result.origin is FileNamedResult(child) && child.parent == handle {
      if child.start != file.start || !physical_equal(child.work, work) {
        return -35
      }
    }
  }
  // Mark the exact owners before removing an interrupted synchronous latch.
  // A later retry of this terminal call can only rejoin these same owners.
  parent.closing = true
  work.closing = true
  if claim.reading is Some(FileStartPreflightRead(_)) {
    claim.reading = None
  }
  parent.pending = false
  for result in value.result_exports.values() {
    if result.origin is FileNamedResult(child) && child.parent == handle {
      result.closing = true
      // A close that entered physical retirement owns a different pending
      // responsibility. Only its original cleanup path may resolve it.
      if !child.retiring {
        result.pending = false
      }
    }
  }
  for chunk in value.result_chunks.values() {
    if value.result_exports.get(chunk.result) is Some(result) &&
      result.origin is FileNamedResult(child) &&
      child.parent == handle {
      chunk.closing = true
      if !child.retiring {
        chunk.pending = false
      }
    }
  }
  0
}

///|
fn retire_file_publication_preflight(
  file : StoredFilePublicationPreflight,
) -> Int {
  file.prepared = None
  if file.capacity is Some((ledger, capacity)) {
    if @resources.settle_capacity(ledger, capacity) is Err(_) {
      return -4
    }
    file.capacity = None
  }
  0
}
