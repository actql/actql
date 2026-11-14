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
pub fn start_managed_task(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    value.computes.get(record.compute) is Some(compute) &&
    compute.host is Some(host) &&
    compute.start is Some(start) &&
    value.run_configurations.get(record.current_configuration) is Some(current) &&
    stored_compute_original_run(value, compute)
    is Some({ outcome: Some(Ok(plan)), .. }) else {
    return -2
  }
  if value.closing || record.closing || compute.closing {
    return -5
  }
  // Fix original publication scope before the activation Owner is invoked.
  // Current Run/Source access is separate from the task dispatch permit.
  guard compute_publication_preflight(value, record.compute)
    is Some((_, preflight)) else {
    return -36
  }
  if !stored_preflight_current(value, preflight, current.account) {
    return -32
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
pub fn close_managed_task(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) else {
    return -2
  }
  // Seal new task/export admission immediately, but preserve the original
  // output's liveness and reservation until its existing pins are returned.
  record.closing = true
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
pub fn feed_managed_task(nonce : Int64, handle : Int, quantum : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    record.operations is Some(operations) &&
    value.computes.get(record.compute) is Some({ closing: false, .. }) else {
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
  // Captured and supplied reads are already bound by the existing driver.
  // Only managed completed-output ports require a row transfer here.
  if record.positions.length() != operations.inputs.length() {
    record.issue = Some(@local_run.Configuration)
    return -32
  }
  for _ in 0..<quantum {
    let mut port = 0
    while port < record.finished_inputs.length() && record.finished_inputs[port] {
      port += 1
    }
    if port == record.finished_inputs.length() {
      return 0
    }
    let transfer = operations.inputs[port]
    let input = @execution.managed_producer_read_input_index(transfer.input)
    guard record.producers.get(input) is Some(producer) && producer > 0 else {
      record.issue = Some(@local_run.UnsupportedCapability)
      return -32
    }
    record.pending = true
    let outcome : Result[Unit, @local_run.LocalComputeIssue] = match
      stored_producer(value, record.compute, producer) {
      Some({ completed: Some(output), operations: Some(parent), .. }) => {
        if !@execution.managed_producer_read_matches_reference(
            transfer.input,
            @execution.managed_completed_reference(output),
          ) {
          record.pending = false
          record.issue = Some(@local_run.UnsupportedCapability)
          return -32
        }
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
        ControlWorkLimit(_) => 82
        ExecutionCapacityRefusal(_, _, _, _) => 83
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

///|
/// Read one existing Owner assessment, without rerunning search or dispatch.
/// Int64 quantities retain exact declared capacities and current reservations.
pub fn managed_task_assessment(
  nonce : Int64,
  handle : Int,
  index : Int,
  field : Int,
) -> Int64 {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    value.computes.get(record.compute) is Some({ host: Some(host), .. }) else {
    return -2L
  }
  let run = @local_run.local_compute_run(host)
  guard @strategy.strategy_report_at(run, index) is Some(assessment) else {
    return -2L
  }
  let limits = @resources.ledger_admission_limits(value.root)
  let usage = @resources.ledger_usage(value.root)
  match field {
    0 =>
      match assessment.rejection {
        None => 0L
        Some(RetentionLimit) => 1L
        Some(ExecutionLimit) => 2L
        Some(TransferLimit) => 3L
        Some(AttemptLimit) => 4L
        Some(HoldingLimit) => 5L
        Some(_) => 6L
      }
    1 => assessment.transfer_bytes
    2 => assessment.retained_bytes
    3 => assessment.execution_bytes
    4 => limits.retained_bytes
    5 => usage.held_bytes + usage.reserved_retention_bytes
    6 => limits.execution_bytes
    7 => usage.reserved_execution_bytes
    _ => -3L
  }
}

///|
/// Explicit end comes from the original CapturedDAG's completed task facts,
/// never from a missing handle, transport error or Python scheduling decision.
pub fn reserve_next_sdk_task(
  nonce : Int64,
  compute : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    !value.closing &&
    !value.runtime_closing &&
    value.computes.get(compute)
    is Some(
      { closing: false, origin: SourceFree(_, start), host: Some(host), .. } as record
    ) &&
    stored_compute_original_run(value, record)
    is Some({ configuration, outcome: Some(Ok(plan)), .. }) &&
    value.run_configurations.get(configuration) is Some({ sdk: Some(_), .. }) &&
    value.run_configurations.get(current_configuration) is Some(current) &&
    value.physical_starts.get(start) is Some({ sdk_step: Some(step), .. }) &&
    compute_publication_preflight(value, compute) is Some((_, preflight)) else {
    return -2
  }
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return code
  }
  let code = validate_sdk_start_claim(value, step, plan)
  if code != 0 {
    return code
  }
  if !stored_preflight_current(value, preflight, current.account) {
    return -32
  }
  let run = @local_run.local_compute_run(host)
  let graph = @strategy.captured_dag_graph(run)
  let first = @strategy.captured_compute_first_task(run)
  let count = @strategy.graph_task_count(graph)
  // Every task handle remains borrowed until its Result children close. The
  // original physical workspace selection bounds this retained inventory.
  if count < first || count - first > value.workspace_slots {
    return -4
  }
  if @strategy.next_captured_task(run) is Some(_) {
    return reserve_managed_task(nonce, compute, current_configuration)
  }
  for task in first..<count {
    if !@strategy.captured_task_completed(run, task) {
      return -33
    }
  }
  0
}
