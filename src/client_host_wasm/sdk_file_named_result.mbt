///|
priv struct StoredSDKFileNamedResult {
  parent : Int
  start : Int
  work : StoredSDKFileCaptureWork
  mut preparation : @local_host.LocalWholeNamedResultPreparation?
  mut capacity : (@resources.Ledger, @resources.CapacityReservation)?
  mut retained : Int64
  mut initial_execution : Int64
  mut execution : Int64
  mut quote_failure : Int?
  mut retiring : Bool
}

///|
fn reserve_sdk_file_named_result(
  value : Instance,
  start : Int,
  managed : StoredSDKFileManaged,
  result : Int,
  current : StoredRunConfiguration,
) -> Int {
  guard !managed.closing &&
    managed.capture_work is Some(work) &&
    !work.closing &&
    !work.failed &&
    work.results_ready &&
    work.result is Some(_) else {
    return -7
  }
  for parent, record in value.publication_preflights {
    if record.origin is FilePublicationPreflight(file) &&
      physical_equal(file.work, work) {
      guard file.start == start &&
        !record.closing &&
        record.produced &&
        file.prepared is Some(prepared) &&
        @local_run.local_captured_task_publication_preflight_result(
          prepared, result,
        )
        is Some(_) else {
        return -2
      }
      let checked = file_publication_preflight_current(
        value,
        file,
        current.account,
      )
      if checked != 0 {
        return checked
      }
      let checked = file_publication_request_current(value, work)
      if checked != 0 {
        return checked
      }
      if value.result_exports
        .values()
        .any(child => {
          child.origin is FileNamedResult(input) &&
          physical_equal(input.work, work) &&
          child.result == result
        }) {
        return -3
      }
      return reserve_result_export_record(
        value,
        result,
        FileNamedResult({
          parent,
          start,
          work,
          preparation: None,
          capacity: None,
          retained: 0L,
          initial_execution: 0L,
          execution: 0L,
          quote_failure: None,
          retiring: false,
        }),
      )
    }
  }
  -7
}

///|
fn sdk_file_result_original(
  value : Instance,
  file : StoredSDKFileNamedResult,
) -> Result[
  (@local_host.ClientInstalledManagedRun, WholeFileJournalOriginal),
  Int,
] {
  if value.closing || value.runtime_closing || file.work.closing {
    return Err(-5)
  }
  guard file.work.results_ready &&
    !file.work.failed &&
    file.work.result is Some(_) &&
    value.publication_preflights.get(file.parent)
    is Some(
      {
        closing: false,
        produced: true,
        origin: FilePublicationPreflight(preflight),
        ..
      }
    ) &&
    preflight.start == file.start &&
    physical_equal(preflight.work, file.work) &&
    preflight.prepared is Some(_) else {
    return Err(-35)
  }
  let (custody, managed, owner, journal, _) = match
    sdk_file_source_current(value, file.start) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  guard managed.capture_work is Some(work) &&
    physical_equal(work, file.work) &&
    value.physical_starts.get(file.start) is Some(active) &&
    physical_equal(active, custody) else {
    return Err(-35)
  }
  let checked = file_publication_request_current(value, file.work)
  if checked != 0 {
    return Err(checked)
  }
  Ok((owner, journal))
}

///|
fn check_sdk_file_result_current(
  value : Instance,
  file : StoredSDKFileNamedResult,
) -> Int {
  match sdk_file_result_original(value, file) {
    Err(code) => code
    Ok(_) => 0
  }
}

///|
fn sdk_file_result_failure(
  record : StoredResultExport,
  issue : StoredResultExportIssue,
) -> Int {
  if record.issue is None {
    record.issue = Some(issue)
  }
  result_export_issue_code(record.issue.unwrap())
}

///|
fn sdk_file_result_copy(
  value : Instance,
  file : StoredSDKFileNamedResult,
  retained_delta : Int64,
  decoder : Int64,
) -> Bool {
  if file.quote_failure is Some(_) {
    return false
  }
  let checked = file_publication_request_current(value, file.work)
  if checked != 0 {
    file.quote_failure = Some(checked)
    return false
  }
  guard file.capacity is Some((ledger, capacity)) &&
    @execution.checked_preparation_add_product(
      file.retained,
      retained_delta,
      1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      file.initial_execution,
      decoder,
      1L,
    )
    is Some(temporary) else {
    file.quote_failure = Some(-4)
    return false
  }
  let execution = Int64::max(file.execution, temporary)
  if @resources.grow_capacity_reservation(ledger, capacity, retained, execution)
    is Err(_) {
    file.quote_failure = Some(-4)
    return false
  }
  file.retained = retained
  file.execution = execution
  let checked = file_publication_request_current(value, file.work)
  if checked != 0 {
    file.quote_failure = Some(checked)
    return false
  }
  true
}

///|
fn start_sdk_file_result_export(
  value : Instance,
  record : StoredResultExport,
  file : StoredSDKFileNamedResult,
) -> Int {
  if value.closing || record.closing {
    return -5
  }
  if record.issue is Some(issue) {
    return result_export_issue_code(issue)
  }
  if record.pending {
    return -33
  }
  if file.preparation is Some(_) {
    return 0
  }
  if record.invoked {
    return -33
  }
  let (owner, journal) = match sdk_file_result_original(value, file) {
    Err(code) => return sdk_file_result_failure(record, FileCurrent(code))
    Ok(value) => value
  }
  guard file.work.result is Some(execution) &&
    file.work.invocation is Some(invocation) &&
    file.work.host is Some((_, dag, _)) &&
    value.publication_preflights.get(file.parent)
    is Some({ origin: FilePublicationPreflight(preflight), .. }) &&
    preflight.prepared is Some(prepared) &&
    @local_run.local_captured_task_publication_preflight_result(
      prepared,
      record.result,
    )
    is Some((definition, _)) else {
    return sdk_file_result_failure(record, FileCurrent(-35))
  }
  // The preflight owns the sealed Definition. This reservation backs only
  // the cursors, copied limit records and callback/borrow controls. Rows and
  // selected Result metadata use the same reservation before materialization.
  guard @execution.execution_capacity_inventory_add(0L, CursorRootSlots, 64L, 1)
    is Some(retained) &&
    @execution.execution_capacity_inventory_add(
      retained,
      CursorRootSlots,
      16L,
      1,
    )
    is Some(peak) else {
    return sdk_file_result_failure(record, Capacity)
  }
  record.invoked = true
  record.pending = true
  let ledger = @strategy.captured_dag_ledger(dag)
  let capacity = match @resources.reserve_capacity(ledger, retained, peak) {
    Err(_) => {
      record.pending = false
      return sdk_file_result_failure(record, Capacity)
    }
    Ok(capacity) => capacity
  }
  file.capacity = Some((ledger, capacity))
  file.retained = retained
  file.initial_execution = peak
  file.execution = peak
  let materials = journal.candidate.task_materials.plan
  let prepared = @local_host.start_installed_whole_named_result_export(
    owner,
    file.work.prepared,
    file.work.request,
    materials.compiled,
    invocation.invocation,
    execution,
    record.result,
    definition,
    16777216,
    (retained, decoder) => {
      if record.closing {
        if file.quote_failure is None {
          file.quote_failure = Some(-5)
        }
        return false
      }
      sdk_file_result_copy(value, file, retained, decoder)
    },
  )
  let result = match prepared {
    Err(issue) => sdk_file_result_failure(record, FileExport(issue))
    Ok(preparation) => {
      file.preparation = Some(preparation)
      let code = check_sdk_file_result_current(value, file)
      if code == 0 {
        0
      } else {
        sdk_file_result_failure(record, FileCurrent(code))
      }
    }
  }
  record.pending = false
  result
}

///|
fn advance_sdk_file_result_export(
  value : Instance,
  record : StoredResultExport,
  file : StoredSDKFileNamedResult,
  quantum : Int,
  feed~ : Bool,
) -> Int {
  if value.closing || record.closing || record.stream is Some(_) {
    return -5
  }
  if quantum <= 0 {
    return -3
  }
  if record.pending {
    return -33
  }
  if record.issue is Some(issue) {
    return result_export_issue_code(issue)
  }
  guard file.preparation is Some(preparation) else { return -7 }
  if feed && preparation.inputs_ready() {
    return 0
  }
  if !feed && !preparation.inputs_ready() {
    return -7
  }
  let checked = check_sdk_file_result_current(value, file)
  if checked != 0 {
    return sdk_file_result_failure(record, FileCurrent(checked))
  }
  record.pending = true
  let progress = preparation.advance(quantum)
  let result = match progress {
    Ok(progress) => {
      let code = check_sdk_file_result_current(value, file)
      if code == 0 {
        record.progress = Some(progress)
        0
      } else {
        sdk_file_result_failure(record, FileCurrent(code))
      }
    }
    Err(issue) =>
      if file.quote_failure is Some(primary) {
        sdk_file_result_failure(record, FileCurrent(primary))
      } else {
        sdk_file_result_failure(record, FileExport(issue))
      }
  }
  record.pending = false
  result
}

///|
fn finish_sdk_file_result_export(
  value : Instance,
  record : StoredResultExport,
  file : StoredSDKFileNamedResult,
) -> Int {
  if value.closing || record.closing {
    return -5
  }
  if record.pending {
    return -33
  }
  if record.issue is Some(issue) {
    return result_export_issue_code(issue)
  }
  if record.stream is Some(_) {
    return 0
  }
  guard record.progress is Some((true, _)) &&
    file.preparation is Some(preparation) else {
    return -7
  }
  let checked = check_sdk_file_result_current(value, file)
  if checked != 0 {
    return sdk_file_result_failure(record, FileCurrent(checked))
  }
  record.pending = true
  let result = match preparation.finish() {
    Err(issue) => sdk_file_result_failure(record, FileExport(issue))
    Ok(stream) => {
      let checked = check_sdk_file_result_current(value, file)
      if checked != 0 {
        sdk_file_result_failure(record, FileCurrent(checked))
      } else {
        check_sdk_file_result_definition(value, record, file, stream)
      }
    }
  }
  record.pending = false
  result
}

///|
fn check_sdk_file_result_definition(
  value : Instance,
  record : StoredResultExport,
  file : StoredSDKFileNamedResult,
  stream : @host.PublicationOutputExport,
) -> Int {
  guard value.publication_preflights.get(file.parent)
    is Some(
      {
        origin: FilePublicationPreflight(preflight),
        closing: false,
        produced: true,
        ..
      }
    ) &&
    physical_equal(preflight.work, file.work) &&
    preflight.prepared is Some(prepared) &&
    @local_run.local_captured_task_publication_preflight_result(
      prepared,
      record.result,
    )
    is Some((expected, _)) &&
    stream.definition() is Ok(actual) &&
    physical_equal(expected, actual) else {
    return sdk_file_result_failure(record, FileCurrent(-35))
  }
  record.stream = Some(stream)
  0
}

///|
fn retire_sdk_file_result_export(
  record : StoredResultExport,
  file : StoredSDKFileNamedResult,
) -> Int {
  record.stream = None
  if file.preparation is Some(preparation) {
    preparation.close()
    file.preparation = None
  }
  if file.capacity is Some((ledger, capacity)) {
    if @resources.settle_capacity(ledger, capacity) is Err(_) {
      return -4
    }
    file.capacity = None
  }
  0
}
