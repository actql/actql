///|
priv struct StoredFilePublicationCapture {
  original : StoredFilePublicationPreflight
  results : Array[@local_run.LocalCapturedTaskResultPublication[Ref[Int], Int]]
  mut manifest : @local_run.LocalCapturedTaskPublicationManifest[Ref[Int], Int]?
  mut capacity : (@resources.Ledger, @resources.CapacityReservation)?
  mut retained : Int64
  mut execution : Int64
  mut state_export : Int?
}

///|
fn select_sdk_file_publication_capture(
  value : Instance,
  source : Int,
) -> (Int, StoredFilePublicationPreflight)? {
  guard value.physical_starts.get(source)
    is Some({ file_managed: Some(managed), .. }) &&
    !managed.closing &&
    managed.capture_work is Some(work) &&
    work.results_ready &&
    !work.closing &&
    !work.failed else {
    return None
  }
  for handle, record in value.publication_preflights {
    if record.origin is FilePublicationPreflight(file) &&
      file.start == source &&
      physical_equal(file.work, work) &&
      record.produced &&
      !record.closing &&
      file.prepared is Some(_) &&
      file.request_publisher is Some(_) {
      return Some((handle, file))
    }
  }
  None
}

///|
fn sdk_file_capture_custody_current(
  value : Instance,
  record : StoredPublication,
  file : StoredFilePublicationCapture,
) -> Int {
  if record.closing || value.closing || value.runtime_closing {
    return -5
  }
  guard select_sdk_file_publication_capture(value, record.source)
    is Some((parent, original)) &&
    parent == record.preflight &&
    physical_equal(original, file.original) else {
    return -35
  }
  for ordinal, handle in record.results {
    guard value.result_exports.get(handle)
      is Some(
        {
          result,
          origin: FileNamedResult(named),
          closing: false,
          issue: None,
          stream: Some(_),
          ended: true,
          ..
        }
      ) &&
      result == ordinal &&
      named.parent == parent &&
      physical_equal(named.work, original.work) else {
      return -35
    }
  }
  0
}

///|
fn sdk_file_capture_publication_current(
  value : Instance,
  record : StoredPublication,
  file : StoredFilePublicationCapture,
  account : @authorization.AdmittedAccountConfiguration,
  selected_file_projection? : Bool = false,
) -> Int {
  let custody = sdk_file_capture_custody_current(value, record, file)
  if custody != 0 {
    return custody
  }
  let checked = file_publication_preflight_current(
    value,
    file.original,
    account,
    selected_file_projection~,
  )
  if checked != 0 {
    return checked
  }
  file_publication_request_current(value, file.original.work)
}

///|
fn sdk_file_capture_require_current(
  value : Instance,
  record : StoredPublication,
  file : StoredFilePublicationCapture,
  account : @authorization.AdmittedAccountConfiguration,
) -> Result[Unit, @local_run.LocalCapturedTaskPublicationPreflightIssue[Int]] {
  let status = sdk_file_capture_publication_current(
    value, record, file, account,
  )
  if status == 0 {
    Ok(())
  } else {
    Err(@local_run.Binding(@local_run.Current(@host.Physical(status))))
  }
}

///|
fn sdk_file_capture_limits(
  value : Instance,
) -> @local_run.LocalPublicationIntentLimits {
  {
    max_results: value.workspace_slots,
    max_wire_bytes: 1048576,
    max_nodes: 100000,
    max_depth: 64,
  }
}

///|
fn prepare_sdk_file_publication_capture(
  value : Instance,
  record : StoredPublication,
  file : StoredFilePublicationCapture,
  account : @authorization.AdmittedAccountConfiguration,
) -> Int {
  let checked = sdk_file_capture_publication_current(
    value, record, file, account,
  )
  if checked != 0 {
    return checked
  }
  if record.prepared {
    return 0
  }
  if record.invoked || file.original.capture_started {
    return -33
  }
  guard file.original.prepared is Some(preflight) &&
    file.original.work.host is Some((_, dag, _)) else {
    return -35
  }
  // Spend the selected original before reading or funding its Result
  // inventory. Closing a refused child must not reopen this Work's capture.
  file.original.capture_started = true
  record.invoked = true
  let borrow = match record.borrow {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) else { return -31 }
  let (originals, max_work, max_workspace) = match
    publication_capture_input(value, cursor) {
    Ok(value) => value
    Err(code) => return code
  }
  if originals.length() !=
    @local_run.local_captured_task_publication_preflight_count(preflight) {
    return -35
  }
  let handles : Array[Int] = []
  for ordinal, original in originals {
    guard @decode.int32(original) is Ok(handle) &&
      !handles.contains(handle) &&
      value.result_exports.get(handle)
      is Some(
        {
          origin: FileNamedResult(named),
          result,
          stream: Some(_),
          ended: true,
          pending: false,
          closing: false,
          issue: None,
          ..
        }
      ) &&
      result == ordinal &&
      named.parent == record.preflight &&
      physical_equal(named.work, file.original.work) else {
      return -35
    }
    handles.push(handle)
  }
  record.results = handles
  record.max_work = max_work.to_int64()
  record.max_workspace = max_workspace
  record.pending = true
  let result = seal_sdk_file_publication_results(
    value, record, file, preflight, dag, account,
  )
  record.pending = false
  if result != 0 {
    record.failed = true
  }
  result
}

///|
fn seal_sdk_file_publication_results(
  value : Instance,
  record : StoredPublication,
  file : StoredFilePublicationCapture,
  preflight : @local_run.LocalCapturedTaskPublicationPreflight[Ref[Int], Int],
  dag : @strategy.CapturedDAG,
  account : @authorization.AdmittedAccountConfiguration,
) -> Int {
  // Fixed wrappers, the per-Result inventory and one measuring cursor.
  // Output/receipt inputs already belong to the finished Result streams.
  let count = record.results.length().to_int64()
  guard @execution.execution_capacity_inventory_add(
      0L,
      CursorRootSlots,
      count,
      16,
    )
    is Some(retained) &&
    @execution.execution_capacity_inventory_add(
      retained,
      CursorRootSlots,
      128L,
      1,
    )
    is Some(execution) else {
    return -4
  }
  let ledger = @strategy.captured_dag_ledger(dag)
  let capacity = match
    @resources.reserve_capacity(ledger, retained, execution) {
    Ok(capacity) => capacity
    Err(_) => return -4
  }
  file.capacity = Some((ledger, capacity))
  file.retained = retained
  file.execution = execution
  let current = () => {
    sdk_file_capture_require_current(value, record, file, account)
  }
  match current() {
    Err(issue) => return file_preflight_issue(issue)
    Ok(_) => ()
  }
  let limits = sdk_file_capture_limits(value)
  for ordinal, handle in record.results {
    guard value.result_exports.get(handle) is Some({ stream: Some(stream), .. }) else {
      return -35
    }
    match
      @local_run.issue_local_captured_task_result_publication(
        preflight,
        ordinal,
        stream,
        limits,
        current,
        (retained, execution) => {
          grow_sdk_file_publication_capacity(file, retained, execution)
        },
      ) {
      Err(issue) => return file_preflight_issue(issue)
      Ok(result) => file.results.push(result)
    }
  }
  record.prepared = true
  0
}

///|
fn grow_sdk_file_publication_capacity(
  file : StoredFilePublicationCapture,
  retained : Int64,
  temporary : Int64,
) -> Bool {
  guard file.capacity is Some((ledger, capacity)) &&
    @execution.checked_preparation_add_product(file.retained, retained, 1L)
    is Some(next_retained) else {
    return false
  }
  // Prior outputs stay retained. One constructor uses the scratch at a time.
  let next_execution = Int64::max(file.execution, temporary)
  if @resources.grow_capacity_reservation(
      ledger, capacity, next_retained, next_execution,
    )
    is Err(_) {
    return false
  }
  file.retained = next_retained
  file.execution = next_execution
  true
}

///|
fn advance_sdk_file_publication_capture(
  value : Instance,
  record : StoredPublication,
  file : StoredFilePublicationCapture,
  account : @authorization.AdmittedAccountConfiguration,
  quantum : Int,
) -> Result[(Bool, Int), Int] {
  guard file.original.prepared is Some(preflight) else { return Err(-35) }
  let limits = sdk_file_capture_limits(value)
  let current = () => {
    sdk_file_capture_require_current(value, record, file, account)
  }
  if record.index < file.results.length() {
    if record.snapshot is None {
      match
        @local_run.start_local_captured_task_result_snapshot(
          file.results[record.index],
          limits,
          current,
          (retained, temporary) => {
            if grow_sdk_file_publication_capacity(file, retained, temporary) {
              Ok(())
            } else {
              Err(@local_run.Intent(@local_run.InventoryLimit))
            }
          },
        ) {
        Err(issue) => return Err(file_preflight_issue(issue))
        Ok(snapshot) => record.snapshot = Some(snapshot)
      }
    }
    let snapshot = record.snapshot.unwrap()
    let (done, work) = match snapshot.advance(quantum) {
      Ok(progress) => progress
      Err(_) => return Err(-32)
    }
    if done {
      match snapshot.finish() {
        Ok(complete) => record.snapshots.push(complete)
        Err(_) => return Err(-32)
      }
      record.snapshot = None
      record.index += 1
    }
    return Ok((false, work))
  }
  if record.capture is None {
    guard file.original.work.invocation is Some(original) else {
      return Err(-35)
    }
    let fund = (retained, execution) => {
      grow_sdk_file_publication_capacity(file, retained, execution)
    }
    let manifest = match
      @local_run.issue_local_captured_task_publication_manifest(
        preflight,
        file.results,
        limits,
        current,
        fund,
      ) {
      Ok(value) => value
      Err(issue) => return Err(file_preflight_issue(issue))
    }
    file.manifest = Some(manifest)
    match
      @local_run.start_local_captured_task_publication_capture(
        manifest,
        original.observation,
        original.source_evidence,
        record.snapshots,
        limits,
        record.max_workspace,
        current,
        fund,
      ) {
      Ok((capture, receipt)) => {
        record.capture = Some(capture)
        record.receipt = Some(receipt)
      }
      Err(issue) => return Err(file_preflight_issue(issue))
    }
  }
  record.capture.unwrap().advance(quantum).map_err(_ => -32)
}

///|
fn retire_sdk_file_publication_capture(
  record : StoredPublication,
  file : StoredFilePublicationCapture,
) -> Int {
  record.snapshot = None
  record.capture = None
  record.receipt = None
  record.captured = None
  record.snapshots.clear()
  file.manifest = None
  file.results.clear()
  if file.capacity is Some((ledger, capacity)) {
    if @resources.settle_capacity(ledger, capacity) is Err(_) {
      return -4
    }
    file.capacity = None
  }
  0
}
