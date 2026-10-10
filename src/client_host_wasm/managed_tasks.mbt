///|
/// Custody of an existing managed operation, not a task counter or completion
/// Owner. Activation, progress and failure remain in the existing Core driver.
priv struct StoredManagedTask {
  compute : Int
  current_configuration : Int
  task : Int
  mut invoked : Bool
  mut pending : Bool
  mut closing : Bool
  mut issue : @local_run.LocalComputeIssue?
  mut operations : @managed.LocalManagedDispatchOperations[Int]?
  mut progress : @managed.LocalManagedAdvance?
  producers : Array[Int]
  positions : Array[Int]
  finished_inputs : Array[Bool]
  live : Ref[Bool]
  mut completed : @execution.ManagedCompletedOutput[Int]?
  mut finalization_invoked : Bool
}

///|
fn stored_producer(
  value : Instance,
  compute : Int,
  task : Int,
) -> StoredManagedTask? {
  for record in value.tasks.values() {
    if record.compute == compute && record.task == task {
      return Some(record)
    }
  }
  None
}

///|
#export_name("actql_task_reserve")
pub fn reserve_managed_task(
  nonce : Int64,
  compute : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.computes.get(compute) is Some(record) &&
    record.outcome is Some(Ok(_)) &&
    !record.closing &&
    record.host is Some(host) &&
    record.start is Some(_) &&
    value.run_configurations.contains(current_configuration) &&
    @strategy.next_captured_task(@local_run.local_compute_run(host))
    is Some(task) else {
    return -2
  }
  if value.closing ||
    value.next_handle == 2147483647 ||
    value.tasks
    .values()
    .any(other => other.compute == compute && other.task == task) {
    return -3
  }
  let handle = value.next_handle
  value.tasks[handle] = {
    compute,
    current_configuration,
    task,
    invoked: false,
    pending: false,
    closing: false,
    issue: None,
    operations: None,
    progress: None,
    producers: @local_run.local_compute_producers(host),
    positions: [],
    finished_inputs: [],
    live: Ref(true),
    completed: None,
    finalization_invoked: false,
  }
  value.next_handle += 1
  handle
}

///|
#export_name("actql_task_start")
pub fn start_managed_task(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    value.computes.get(record.compute) is Some(compute) &&
    compute.host is Some(host) &&
    compute.start is Some(start) &&
    value.run_configurations.get(record.current_configuration) is Some(current) &&
    value.native_attempts.get(compute.attempt) is Some(original) &&
    value.native_sources.get(original.configuration) is Some(source) &&
    value.runs.get(source.run) is Some({ outcome: Some(Ok(plan)), .. }) else {
    return -2
  }
  if value.closing || record.closing || compute.closing {
    return -5
  }
  if record.operations is Some(_) || record.issue is Some(_) {
    return 0
  }
  if record.invoked {
    return -33
  }
  record.invoked = true
  let completed : Array[@execution.ManagedCompletedOutput[Int]] = []
  for producer in record.producers {
    if producer == 0 {
      continue
    }
    guard stored_producer(value, record.compute, producer)
      is Some({ completed: Some(output), closing: false, .. }) else {
      record.issue = Some(@local_run.UnsupportedCapability)
      return 0
    }
    completed.push(output)
  }
  let subject = @host.prepared_client_identity(
      @local_run.local_run_prepared(plan),
    ).program_definition_cid
  let permit = match
    @authorization.bind_dispatch_authorization(
      current.account,
      current.tuple,
      @authorization.Activation,
      subject,
      current.context_cid,
    ) {
    Ok(permit) => permit
    Err(_) => {
      record.issue = Some(@local_run.AuthorizationMismatch)
      return 0
    }
  }
  record.pending = true
  match
    @local_run.start_local_compute_task(
      host,
      start,
      completed,
      permit,
      current.account,
      current.tuple,
      current.context_cid,
    ) {
    Ok(Some(operations)) => {
      record.operations = Some(operations)
      for _ in operations.inputs {
        record.positions.push(0)
        record.finished_inputs.push(false)
      }
    }
    Ok(None) => record.issue = Some(@local_run.UnsupportedCapability)
    Err(issue) => record.issue = Some(issue)
  }
  record.pending = false
  0
}

///|
#export_name("actql_task_started")
pub fn managed_task_started(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) else {
    return -2
  }
  if record.closing {
    return -5
  }
  if record.pending {
    return -33
  }
  if record.issue is Some(_) {
    return -32
  }
  if record.operations is Some(_) {
    0
  } else {
    -33
  }
}

///|
/// Advance the existing provider within the caller's finite quantum. No
/// expression evaluation, work accounting or async stop decision is duplicated.
#export_name("actql_task_advance")
pub fn advance_managed_task(nonce : Int64, handle : Int, quantum : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    record.operations is Some(operations) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if quantum <= 0 {
    return -3
  }
  if record.pending || record.issue is Some(_) {
    return -33
  }
  if record.finalization_invoked {
    return -5
  }
  if record.finished_inputs.any(finished => !finished) {
    return -7
  }
  record.pending = true
  match (operations.advance)(quantum) {
    Ok(progress) => record.progress = Some(progress)
    Err(issue) => record.issue = Some(@local_run.Managed(issue))
  }
  record.pending = false
  if record.issue is Some(_) {
    -32
  } else {
    0
  }
}

///|
#export_name("actql_task_progress")
pub fn managed_task_progress(nonce : Int64, handle : Int, field : Int) -> Int64 {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    !record.pending &&
    record.progress is Some(progress) else {
    return -33L
  }
  match field {
    0 => if progress.complete { 1L } else { 0L }
    1 => if progress.waiting { 1L } else { 0L }
    2 => progress.progress
    3 => progress.work
    _ => -3L
  }
}

///|
#export_name("actql_task_close")
pub fn close_managed_task(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) else {
    return -2
  }
  if value.result_exports.values().any(result => result.task == handle) {
    return -9
  }
  if value.tasks
    .values()
    .any(other => {
      other.compute == record.compute && other.producers.contains(record.task)
    }) {
    return -9
  }
  record.closing = true
  record.live.val = false
  if record.pending {
    return -33
  }
  if record.operations is Some(operations) {
    (operations.close)()
    if value.computes.get(record.compute) is Some({ host: Some(host), .. }) {
      @strategy.close_captured_task_output(
        @local_run.local_compute_run(host),
        record.task,
      )
    }
    if !(operations.execution_stopped)() || !(operations.cleanup_refresh)() {
      return -9
    }
  }
  value.tasks.remove(handle) |> ignore
  0
}

///|
/// Feed only the selected original Core Source/completed producer. Python
/// supplies neither rows nor identity, and each append is attempted once.
#export_name("actql_task_feed")
pub fn feed_managed_task(nonce : Int64, handle : Int, quantum : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    record.operations is Some(operations) &&
    value.computes.get(record.compute) is Some(compute) &&
    value.native_attempts.get(compute.attempt) is Some(original) &&
    original.outcome is Some(Ok(native)) &&
    original.observation is Some(observation) &&
    value.native_sources.get(original.configuration)
    is Some({ outcome: Some(Ok(configuration)), .. }) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if quantum <= 0 {
    return -3
  }
  if record.pending || record.issue is Some(_) {
    return -33
  }
  if record.producers.length() != operations.inputs.length() {
    return -32
  }
  let limits = @native_host.configured_native_host_limits(
    @local_run.local_native_source_configuration(configuration),
  )
  for _ in 0..<quantum {
    let mut port = 0
    while port < record.finished_inputs.length() && record.finished_inputs[port] {
      port += 1
    }
    if port == record.finished_inputs.length() {
      return 0
    }
    let transfer = operations.inputs[port]
    let producer = record.producers[port]
    record.pending = true
    let outcome : Result[Unit, @local_run.LocalComputeIssue] = if producer == 0 {
      match
        @native_host.native_host_retained_output(
          native,
          observation,
          limits.output_entries,
          limits.output_name_bytes,
        ) {
        Err(_) => Err(@local_run.Configuration)
        Ok(output) => {
          let row = record.positions[port]
          if row == @execution.completed_row_count(output) {
            (transfer.finish)()
            .map(_ => record.finished_inputs[port] = true)
            .map_err(issue => @local_run.Managed(issue))
          } else {
            match
              @execution.completed_output_row_wire(
                output,
                row,
                limits.transport.max_bytes,
                limits.transport.max_nodes,
                64,
              ) {
              Err(_) => Err(@local_run.Configuration)
              Ok(wire) =>
                (transfer.append)(wire)
                .map(_ => record.positions[port] += 1)
                .map_err(issue => @local_run.Managed(issue))
            }
          }
        }
      }
    } else {
      match stored_producer(value, record.compute, producer) {
        Some({ completed: Some(output), operations: Some(parent), .. }) => {
          let row = record.positions[port]
          if row == @execution.managed_completed_output_row_count(output) {
            (transfer.finish)()
            .map(_ => record.finished_inputs[port] = true)
            .map_err(issue => @local_run.Managed(issue))
          } else {
            match (parent.output_row)(row) {
              Err(issue) => Err(@local_run.Managed(issue))
              Ok(wire) =>
                (transfer.append)(wire)
                .map(_ => record.positions[port] += 1)
                .map_err(issue => @local_run.Managed(issue))
            }
          }
        }
        _ => Err(@local_run.UnsupportedCapability)
      }
    }
    if outcome is Err(issue) {
      record.issue = Some(issue)
    }
    record.pending = false
    if record.issue is Some(_) {
      return -32
    }
  }
  0
}

///|
#export_name("actql_task_prepare_finalization")
pub fn prepare_managed_task_finalization(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    record.operations is Some(operations) &&
    record.progress is Some({ complete: true, .. }) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if record.pending || record.issue is Some(_) {
    return -33
  }
  if record.finalization_invoked {
    return 0
  }
  record.finalization_invoked = true
  record.pending = true
  record.progress = None
  let live = record.live
  let result = (operations.prepare_finalization)(
    handle,
    operations.storage_bytes,
    () => live.val,
  )
  if result is Err(issue) {
    record.issue = Some(@local_run.Managed(issue))
  }
  record.pending = false
  if record.issue is Some(_) {
    -32
  } else {
    0
  }
}

///|
#export_name("actql_task_advance_finalization")
pub fn advance_managed_task_finalization(
  nonce : Int64,
  handle : Int,
  quantum : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    record.operations is Some(operations) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if quantum <= 0 {
    return -3
  }
  if record.pending || record.issue is Some(_) {
    return -33
  }
  if !record.finalization_invoked {
    return -7
  }
  record.pending = true
  match (operations.advance_finalization)(quantum) {
    Ok(progress) => record.progress = Some(progress)
    Err(issue) => record.issue = Some(@local_run.Managed(issue))
  }
  record.pending = false
  if record.issue is Some(_) {
    -32
  } else {
    0
  }
}

///|
#export_name("actql_task_complete")
pub fn complete_managed_task(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    record.operations is Some(operations) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if record.pending || record.issue is Some(_) {
    return -33
  }
  if record.completed is Some(_) {
    return 0
  }
  if !record.finalization_invoked || record.progress is None {
    return -7
  }
  guard record.progress is Some({ complete: true, .. }) else { return -7 }
  record.pending = true
  let result = match (operations.settle)() {
    Err(issue) => Err(issue)
    Ok(_) => {
      let live = record.live
      (operations.complete)(handle, operations.storage_bytes, () => live.val)
    }
  }
  match result {
    Ok(output) => record.completed = Some(output)
    Err(issue) => record.issue = Some(@local_run.Managed(issue))
  }
  record.pending = false
  if record.issue is Some(_) {
    -32
  } else {
    0
  }
}

///|
#export_name("actql_task_inputs_ready")
pub fn managed_task_inputs_ready(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    record.operations is Some(_) else {
    return -2
  }
  if record.pending {
    return -33
  }
  if record.issue is Some(_) {
    return -32
  }
  if record.finished_inputs.any(finished => !finished) {
    -7
  } else {
    0
  }
}

///|
/// Retained typed failure projection for the trusted physical Host. These
/// private categories neither publish diagnostics nor authorize re-execution.
#export_name("actql_task_issue")
pub fn managed_task_issue(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) else {
    return -2
  }
  match record.issue {
    None => if record.operations is Some(_) { 0 } else { -33 }
    Some(AuthorizationMismatch) => 1
    Some(UnsupportedCapability) => 2
    Some(Configuration) => 3
    Some(Task(_)) => 4
    Some(Obligations(_)) => 5
    Some(Dispatch(_)) => 6
    Some(Managed(issue)) =>
      match issue {
        Configuration(_) => 71
        Preparation(_) => 72
        Dispatch(_) => 73
        Execution(_) => 74
        Search(_) => 75
        ManagedValues(_) => 76
        ManagedCopy(_) => 77
        ManagedRetention(_) => 78
        ManagedCompletion(_) => 79
        IdentityExport(_) => 80
        CarrierSnapshot(_) => 81
      }
    Some(Estimate(issue)) =>
      match issue {
        InvalidConfiguration => 91
        NoStrategy => 92
        ForeignSelection => 93
        EstimateOverflow => 94
        Resources(issue) =>
          match issue {
            RetentionLimit => 951
            ExecutionLimit => 952
            AttemptLimit => 953
            _ => 950
          }
        Search(_) => 96
        Implementation(_) => 97
      }
    Some(Start(_)) => 10
    Some(StartNotPermitted) => 11
  }
}
