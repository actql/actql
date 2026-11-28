///|
pub(all) struct CapturedContinuationRelationLimits {
  rows : Int
  wire : @execution.RowWireLimits
  values : @execution.ValueLimits
  schema : @execution.RelationSchemaIdentityLimits
  work : Int
  workspace_slots : Int
  workspace_bytes : Int64
}

///|
/// Complete canonical data and source facts from the live scoped export.
/// The receiver must bind these to the original Run, Plan and port, and
/// acquire its own storage before keeping bytes beyond the call.
pub(all) struct CapturedContinuationRelation {
  start_revision : Int
  pause_revision : Int
  task : Int
  committed_generation : Int
  attempt : Int
  relation_cid : String
  relation_wire : String
  relation_bytes : Int
  schema_cid : String
  schema_wire : String
  schema_bytes : Int
  rows : Int
}

///|
pub fn[T] with_captured_task_continuation_relation(
  run : CapturedDAG,
  cut : CapturedTaskContinuation,
  task : Int,
  completed : @execution.ManagedCompletedOutput[T],
  original : @execution.CompletedOutput,
  authorize : () -> Bool,
  limits : CapturedContinuationRelationLimits,
  visit : (CapturedContinuationRelation, () -> Bool) -> Bool,
  handoff_bytes? : Int64 = 0L,
) -> Result[Unit, CapturedTaskContinuationIssue] {
  with_task_continuation_relation_read(
    run,
    cut,
    task,
    limits,
    visit,
    handoff_bytes,
    (backing, scan) => {
      with_task_continuation_output(
        run,
        cut,
        task,
        completed,
        original,
        authorize,
        backing,
        (current, loan) => scan(original, current, loan),
      )
    },
  )
}

///|
/// Continue retaining an actual materialized output on a restored DAG. The
/// receiving graph owns its typed cells and the original occurrence; the
/// scoped conversion borrows the existing output instead of a retired Driver.
pub fn with_captured_task_continuation_materialized_relation(
  run : CapturedDAG,
  cut : CapturedTaskContinuation,
  task : Int,
  authorize : () -> Bool,
  limits : CapturedContinuationRelationLimits,
  visit : (CapturedContinuationRelation, () -> Bool) -> Bool,
  handoff_bytes? : Int64 = 0L,
) -> Result[Unit, CapturedTaskContinuationIssue] {
  with_task_continuation_relation_read(
    run,
    cut,
    task,
    limits,
    visit,
    handoff_bytes,
    (backing, scan) => {
      with_task_continuation_materialized_output(
        run, cut, task, authorize, backing, scan,
      )
    },
  )
}

///|
fn with_task_continuation_relation_read(
  run : CapturedDAG,
  cut : CapturedTaskContinuation,
  task : Int,
  limits : CapturedContinuationRelationLimits,
  visit : (CapturedContinuationRelation, () -> Bool) -> Bool,
  handoff_bytes : Int64,
  read : (
    Int64,
    (@execution.CompletedOutput, () -> Bool, CapturedTaskBoundary) -> Unit,
  ) -> Result[Unit, CapturedTaskContinuationIssue],
) -> Result[Unit, CapturedTaskContinuationIssue] {
  // Fund the wrapper on the original boundary. The same reservation
  // grows to cover measured inventory before each constructor.
  let controls = @execution.preparation_representation_cost({
    record_headers: 16L,
    reference_slots: 29L,
    scalar_words: 19L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  let available = 9223372036854775807L -
    captured_continuation_output_read_bytes -
    controls
  if handoff_bytes < 0L ||
    handoff_bytes > available ||
    limits.workspace_bytes < 0L ||
    limits.workspace_bytes > available - handoff_bytes ||
    limits.work <= 0 {
    return Err(OutputCapacity)
  }
  let result : Ref[Result[Unit, CapturedTaskContinuationIssue]] = Ref(
    Err(StalePause),
  )
  let borrowed = read(controls + handoff_bytes, (original, current, loan) => {
    guard loan.original is Some(read) else { return }
    let base = captured_continuation_output_read_bytes +
      controls +
      handoff_bytes
    let mut retained = base
    let mut execution = base
    let fund = fn(capacity : @execution.ExecutionCapacity) {
      let next_retained = @execution.execution_capacity_retained_bytes(capacity)
      let next_execution = @execution.execution_capacity_execution_bytes(
        capacity,
      )
      if next_retained > limits.workspace_bytes ||
        next_execution > limits.workspace_bytes {
        return Err(CapturedTaskContinuationIssue::OutputCapacity)
      }
      let wanted_retained = Int64::max(retained, base + next_retained)
      let wanted_execution = Int64::max(execution, base + next_execution)
      if wanted_retained > retained || wanted_execution > execution {
        if @resources.grow_capacity_reservation(
            run.ledger,
            read.reservation,
            wanted_retained,
            wanted_execution,
          )
          is Err(issue) {
          return Err(Boundary(Resource(issue)))
        }
        retained = wanted_retained
        execution = wanted_execution
      }
      Ok(())
    }
    result.val = scan_task_continuation_relation(
      run, cut, task, original, current, limits, fund, visit,
    )
  })
  borrowed.bind(_ => result.val)
}

///|
fn scan_task_continuation_relation(
  run : CapturedDAG,
  cut : CapturedTaskContinuation,
  task : Int,
  original : @execution.CompletedOutput,
  current : () -> Bool,
  limits : CapturedContinuationRelationLimits,
  fund : (@execution.ExecutionCapacity) -> Result[
    Unit,
    CapturedTaskContinuationIssue,
  ],
  visit : (CapturedContinuationRelation, () -> Bool) -> Bool,
) -> Result[Unit, CapturedTaskContinuationIssue] {
  guard @execution.completed_relation_identity_scan_start_construction_capacity(
      original,
      retain_body=true,
    )
    is Some(start) else {
    return Err(OutputCapacity)
  }
  if fund(start) is Err(issue) {
    return Err(issue)
  }
  if !current() {
    return Err(StalePause)
  }
  if @resources.charge_planning(run.ledger, 1) is Err(issue) {
    return Err(Boundary(Resource(issue)))
  }
  if !current() {
    return Err(StalePause)
  }
  let restricted = @execution.restrict_completed_output(original, current)
  let scan = match
    @execution.start_completed_relation_identity_scan(
      restricted,
      limits.rows,
      limits.values,
      limits.wire,
      limits.wire,
      limits.schema,
      limits.work - 1,
      limits.workspace_slots,
      incremental_metadata=true,
      retain_body=true,
    ) {
    Ok(value) => value
    Err(_) => return Err(OutputEncoding)
  }
  defer @execution.cancel_completed_relation_identity_scan(scan) |> ignore
  let mut remaining = limits.work - 1
  while true {
    guard @execution.completed_relation_identity_scan_next_construction_capacity(
        scan,
      )
      is Some(next) else {
      return Err(OutputCapacity)
    }
    if fund(next) is Err(issue) {
      return Err(issue)
    }
    if remaining == 0 {
      return Err(WorkLimit)
    }
    if @resources.charge_planning(run.ledger, 1) is Err(issue) {
      return Err(Boundary(Resource(issue)))
    }
    remaining -= 1
    if !current() {
      return Err(StalePause)
    }
    let done = match
      @execution.advance_completed_relation_identity_scan(
        scan,
        1,
        construction_capacity=Some(next),
      ) {
      Ok((done, 1)) => done
      Ok(_) | Err(_) => return Err(OutputEncoding)
    }
    if done {
      break
    }
  }
  guard @execution.completed_relation_identity_scan_next_construction_capacity(
      scan,
    )
    is Some(finish) else {
    return Err(OutputCapacity)
  }
  if fund(finish) is Err(issue) {
    return Err(issue)
  }
  guard @execution.completed_relation_identity_scan_body_finish_work(scan)
    is Some(finish_work) &&
    finish_work <= remaining else {
    return Err(WorkLimit)
  }
  if @resources.charge_planning(run.ledger, finish_work) is Err(issue) {
    return Err(Boundary(Resource(issue)))
  }
  if !current() {
    return Err(StalePause)
  }
  let receipt = match @execution.finish_completed_relation_identity_scan(scan) {
    Ok(value) => value
    Err(_) => return Err(OutputEncoding)
  }
  defer @execution.cancel_completed_relation_export_receipt(receipt)
  guard @execution.completed_relation_export_has_output_identity(
      receipt, original,
    ) &&
    @execution.completed_relation_identity_scan_body(scan, receipt)
    is Some(relation_wire) &&
    captured_task_continuation_completion(run, cut, task)
    is Some((committed_generation, attempt, true)) else {
    return Err(StalePause)
  }
  let relation = @execution.completed_relation_export_identity(receipt)
  let schema = @execution.completed_relation_export_schema_identity(receipt)
  let (bytes, _, rows) = @execution.logical_relation_usage(relation)
  let (schema_bytes, _, _) = @execution.relation_schema_usage(schema)
  if bytes > limits.wire.max_bytes ||
    schema_bytes > limits.wire.max_bytes - bytes {
    return Err(OutputCapacity)
  }
  if !current() {
    return Err(StalePause)
  }
  let accepted = visit(
    {
      start_revision: cut.start_revision,
      pause_revision: cut.revision,
      task,
      committed_generation,
      attempt,
      relation_cid: @execution.logical_relation_cid(relation),
      relation_wire,
      relation_bytes: bytes,
      schema_cid: @execution.relation_schema_cid(schema),
      schema_wire: @execution.relation_schema_wire(schema),
      schema_bytes,
      rows,
    },
    current,
  )
  if !current() {
    Err(StalePause)
  } else if !accepted {
    Err(OutputRefused)
  } else {
    Ok(())
  }
}
