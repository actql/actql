///|
priv struct TaskLifetime {
  mut live : Bool
  mut pins : Int
}

///|
/// A bounded borrow of one exact cell-backed task output. Closing the
/// ordinary output port revokes new borrows, but cannot release its allocation
/// while a consumer still owns this pin. The original completion must also
/// remain available. Managed resident material needs its own physical owner
/// and is not admitted through this port.
struct CapturedOutputPin {
  run : CapturedDAG
  task : Int
  output : @execution.CompletedOutput
  mut live : Bool
}

///|
/// One exact checked Result occurrence together with its live physical pin.
/// Neither a caller-provided name nor a second occurrence can relabel the
/// borrowed producer. This is input custody, not public egress or Effect
/// mutation authority.
struct CapturedResultBorrow {
  occurrence : @execution.ManagedResultOccurrence
  pin : CapturedOutputPin
}

///|
priv enum CapturedResidentReference {
  Managed(@execution.ManagedCompletionReference)
  Carrier(@execution.CarrierManagedCompletionReference)
}

///|
/// A checked Result consumer pin for a resident generation. The installed
/// Host keeps the concrete output and must present it again at a typed use
/// boundary. This pin retains the physical allocation but does not expose
/// rows, establish a logical CID, or authorize Effect use or public egress.
struct CapturedResidentResultBorrow {
  run : CapturedDAG
  task : Int
  occurrence : @execution.ManagedResultOccurrence
  reference : CapturedResidentReference
  mut live : Bool
}

///|
/// All-or-nothing retention of checked Result occurrences. This owns only
/// physical input liveness; it does not authorize disclosure or an Effect.
struct CapturedResultOutputSet {
  borrows : Array[CapturedResultBorrow]
  mut live : Bool
}

///|
/// Borrow an exact checked Result occurrence from its completed task. This
/// remains Host-private retention, not permission to disclose the Result or
/// use it as an Effect input. A different Program owner cannot relabel it.
pub fn pin_captured_result_output(
  run : CapturedDAG,
  task : Int,
  occurrence : @execution.ManagedResultOccurrence,
  max_pins : Int,
) -> Result[CapturedOutputPin, RunIssue] {
  let owner = @execution.managed_result_occurrence_owner(occurrence)
  let port = @execution.managed_result_occurrence_port(occurrence)
  let target = @ports.port_target(port)
  guard run.graph.owners.get(task) is Some(actual) &&
    physical_equal(actual, owner) else {
    return Err(ForeignCandidate)
  }
  if captured_task_target(run, task) != Some(target) {
    return Err(UnsupportedGraph)
  }
  let pin = match pin_captured_task_output(run, task, target, max_pins) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let output = captured_output_pin_materialized(pin)
  if !@execution.completed_output_matches_port(output, owner, target) {
    release_captured_output_pin(pin) |> ignore
    return Err(ForeignCandidate)
  }
  Ok(pin)
}

///|
pub fn borrow_captured_result_output(
  run : CapturedDAG,
  task : Int,
  occurrence : @execution.ManagedResultOccurrence,
  max_pins : Int,
) -> Result[CapturedResultBorrow, RunIssue] {
  pin_captured_result_output(run, task, occurrence, max_pins).map(pin => {
    occurrence,
    pin,
  })
}

///|
pub fn captured_result_borrow_occurrence(
  borrow : CapturedResultBorrow,
) -> @execution.ManagedResultOccurrence {
  borrow.occurrence
}

///|
pub fn captured_result_borrow_output(
  borrow : CapturedResultBorrow,
) -> @execution.CompletedOutput {
  captured_output_pin_materialized(borrow.pin)
}

///|
/// A retained Result is usable only while its own consumer pin and the
/// producer completion are both live. Another consumer's pin cannot revive
/// this borrow after release.
pub fn captured_result_borrow_available(borrow : CapturedResultBorrow) -> Bool {
  @execution.completed_output_available(captured_result_borrow_output(borrow))
}

///|
pub fn release_captured_result_borrow(borrow : CapturedResultBorrow) -> Bool {
  release_captured_output_pin(borrow.pin)
}

///|
fn resident_result_borrow_ready(
  run : CapturedDAG,
  task : Int,
  occurrence : @execution.ManagedResultOccurrence,
  max_pins : Int,
) -> Result[Unit, RunIssue] {
  if max_pins <= 0 || task < 0 || task >= run.outputs.length() {
    return Err(ForeignCandidate)
  }
  let owner = @execution.managed_result_occurrence_owner(occurrence)
  let target = @ports.port_target(
    @execution.managed_result_occurrence_port(occurrence),
  )
  guard run.graph.owners.get(task) is Some(actual) &&
    physical_equal(actual, owner) &&
    captured_task_target(run, task) == Some(target) else {
    return Err(ForeignCandidate)
  }
  if !task_done(run, task) || !run.lifetimes[task].live {
    return Err(NotReady)
  }
  Ok(())
}

///|
/// Pin the exact managed generation without expanding it into cell rows.
/// The Host must retain the concrete output and recheck this borrow before
/// each consumer use, including after an asynchronous wait.
pub fn[T] borrow_captured_managed_result_output(
  run : CapturedDAG,
  task : Int,
  occurrence : @execution.ManagedResultOccurrence,
  output : @execution.ManagedCompletedOutput[T],
  max_pins : Int,
) -> Result[CapturedResidentResultBorrow, RunIssue] {
  match resident_result_borrow_ready(run, task, occurrence, max_pins) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard run.outputs[task] is Some(Managed(reference)) &&
    @execution.managed_completed_output_matches_port(
      output,
      @execution.managed_result_occurrence_owner(occurrence),
      @ports.port_target(@execution.managed_result_occurrence_port(occurrence)),
    ) else {
    return Err(ForeignCandidate)
  }
  if !@execution.managed_completed_reference_available(reference) {
    return Err(NotReady)
  }
  if !@execution.managed_completed_reference_matches(reference, output) {
    return Err(ForeignCandidate)
  }
  if run.lifetimes[task].pins >= max_pins {
    return Err(Physical(@resources.HoldingLimit))
  }
  run.lifetimes[task].pins += 1
  Ok({ run, task, occurrence, reference: Managed(reference), live: true, })
}

///|
/// Pin one exact Carrier-managed generation under the same task accounting.
pub fn borrow_captured_carrier_result_output(
  run : CapturedDAG,
  task : Int,
  occurrence : @execution.ManagedResultOccurrence,
  output : @execution.CarrierManagedCompletedOutput,
  max_pins : Int,
) -> Result[CapturedResidentResultBorrow, RunIssue] {
  match resident_result_borrow_ready(run, task, occurrence, max_pins) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard run.outputs[task] is Some(CarrierManaged(reference)) &&
    @execution.carrier_managed_completed_output_matches_port(
      output,
      @execution.managed_result_occurrence_owner(occurrence),
      @ports.port_target(@execution.managed_result_occurrence_port(occurrence)),
    ) else {
    return Err(ForeignCandidate)
  }
  if !@execution.carrier_managed_completed_reference_available(reference) {
    return Err(NotReady)
  }
  if !@execution.carrier_managed_completed_reference_matches(reference, output) {
    return Err(ForeignCandidate)
  }
  if run.lifetimes[task].pins >= max_pins {
    return Err(Physical(@resources.HoldingLimit))
  }
  run.lifetimes[task].pins += 1
  Ok({ run, task, occurrence, reference: Carrier(reference), live: true, })
}

///|
pub fn captured_resident_result_borrow_available(
  borrow : CapturedResidentResultBorrow,
) -> Bool {
  if !borrow.live {
    return false
  }
  match borrow.reference {
    Managed(reference) =>
      @execution.managed_completed_reference_available(reference)
    Carrier(reference) =>
      @execution.carrier_managed_completed_reference_available(reference)
  }
}

///|
pub fn[T] captured_resident_result_borrow_matches_managed(
  borrow : CapturedResidentResultBorrow,
  output : @execution.ManagedCompletedOutput[T],
) -> Bool {
  match borrow.reference {
    Managed(reference) =>
      captured_resident_result_borrow_available(borrow) &&
      @execution.managed_completed_reference_matches(reference, output)
    Carrier(_) => false
  }
}

///|
pub fn captured_resident_result_borrow_matches_carrier(
  borrow : CapturedResidentResultBorrow,
  output : @execution.CarrierManagedCompletedOutput,
) -> Bool {
  match borrow.reference {
    Carrier(reference) =>
      captured_resident_result_borrow_available(borrow) &&
      @execution.carrier_managed_completed_reference_matches(reference, output)
    Managed(_) => false
  }
}

///|
pub fn captured_resident_result_borrow_occurrence(
  borrow : CapturedResidentResultBorrow,
) -> @execution.ManagedResultOccurrence {
  borrow.occurrence
}

///|
pub fn release_captured_resident_result_borrow(
  borrow : CapturedResidentResultBorrow,
) -> Bool {
  if !borrow.live {
    return false
  }
  borrow.live = false
  borrow.run.lifetimes[borrow.task].pins -= 1
  collect_captured_retention(borrow.run)
  true
}

///|
/// Share the checked Result projection and order without creating another
/// serializer or copying its rows. The borrow must stay live through export.
pub fn start_captured_result_borrow_export(
  borrow : CapturedResultBorrow,
  result_view : @execution.CompletedResultViewLimits,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema_limits : @execution.RelationSchemaIdentityLimits,
  max_batch_bytes : Int,
) -> Result[
  @execution.CompletedResultRelationExportPreparation,
  @execution.CompletedExportIssue,
] {
  @execution.start_completed_result_relation_export(
    captured_result_borrow_output(borrow),
    borrow.occurrence,
    result_view,
    max_rows,
    values,
    payload_wire,
    logical_wire,
    schema_limits,
    max_batch_bytes,
  )
}

///|
priv struct TaskRetention {
  mut holding : @resources.Holding?
  mut release_confirmed : () -> Bool
  parents : Array[Int]
}

///|
fn task_parents(run : CapturedDAG, task : Int) -> Array[Int] {
  let parents = []
  for edge in run.graph.data {
    if edge.consumer == task && !parents.contains(edge.producer) {
      parents.push(edge.producer)
    }
  }
  parents
}

///|
/// Trusted Host accounting: associate its exact allocation token only after this
/// task has established success. Task zero is the validated captured root.
/// Sharing is by owned token, never equal CIDs. The Host must keep this port
/// open while exporting the allocation to users outside this run.
/// External storage supplies its original physical-release predicate here;
/// logical close and lack of consumers do not establish physical cleanup.
/// The default is for allocations requiring no asynchronous external release.
pub fn retain_captured_task_allocation(
  run : CapturedDAG,
  task : Int,
  holding : @resources.Holding,
  release_confirmed? : () -> Bool = fn() { true },
) -> Result[Unit, @resources.LedgerIssue] {
  if !@resources.holding_belongs_to(run.ledger, holding) {
    return Err(ForeignOwner)
  }
  guard @resources.holding_available(run.ledger, holding) &&
    run.resources.get(task).bind(x => x) is Some(resource) &&
    resource.holding is None &&
    run.lifetimes[task].live else {
    return Err(InvalidCharge)
  }
  for existing in run.resources {
    if existing is Some(existing) &&
      existing.holding is Some(value) &&
      physical_equal(value, holding) {
      return Err(InvalidCharge)
    }
  }
  resource.holding = Some(holding)
  resource.release_confirmed = release_confirmed
  Ok(())
}

///|
/// Poll the original attached physical-release checks after Host cleanup.
/// This does not close any result, acknowledge cleanup, or replace its check.
pub fn refresh_captured_retention(run : CapturedDAG) -> Unit {
  collect_captured_retention(run)
}

///|
/// Borrow an already completed cell-backed output before the Host closes its
/// ordinary port. The caller supplies a finite per-task pin ceiling; no cells
/// or rows are copied. Managed and Carrier outputs require a separate physical
/// retention owner and are rejected here.
pub fn pin_captured_task_output(
  run : CapturedDAG,
  task : Int,
  target : @pipeline.Target,
  max_pins : Int,
) -> Result[CapturedOutputPin, RunIssue] {
  if max_pins <= 0 || task < 0 || task >= run.outputs.length() {
    return Err(ForeignCandidate)
  }
  if !task_done(run, task) ||
    captured_task_target(run, task) != Some(target) ||
    !run.lifetimes[task].live {
    return Err(NotReady)
  }
  guard run.outputs[task] is Some(Materialized(output)) else {
    return Err(UnsupportedGraph)
  }
  if !@execution.completed_has_cell_access(output) {
    return Err(UnsupportedGraph)
  }
  if !@execution.completed_output_available(output) {
    return Err(NotReady)
  }
  if run.lifetimes[task].pins >= max_pins {
    return Err(Physical(@resources.HoldingLimit))
  }
  run.lifetimes[task].pins += 1
  Ok({ run, task, output, live: true, })
}

///|
/// Read a materialized Relation through this exact live pin. The returned
/// alias is revoked when the pin is released, even if the caller retains it.
/// A loss of the original completion remains observable independently.
pub fn captured_output_pin_materialized(
  pin : CapturedOutputPin,
) -> @execution.CompletedOutput {
  @execution.restrict_completed_output(pin.output, fn() { pin.live })
}

///|
/// End one consumer's custody exactly once. The original physical-release
/// predicate still decides when its allocation may leave the ledger.
pub fn release_captured_output_pin(pin : CapturedOutputPin) -> Bool {
  if !pin.live {
    return false
  }
  pin.live = false
  pin.run.lifetimes[pin.task].pins -= 1
  collect_captured_retention(pin.run)
  true
}

///|
/// Acquire every exact checked Result occurrence before a multi-consumer
/// operation starts. Failure releases earlier pins, including repeated
/// occurrences of the same task, without closing the producer's own port.
pub fn pin_captured_result_output_set(
  run : CapturedDAG,
  sources : Array[(Int, @execution.ManagedResultOccurrence)],
  max_pins : Int,
) -> Result[CapturedResultOutputSet, RunIssue] {
  let borrows : Array[CapturedResultBorrow] = []
  for (task, occurrence) in sources {
    match borrow_captured_result_output(run, task, occurrence, max_pins) {
      Ok(borrow) => borrows.push(borrow)
      Err(issue) => {
        for borrow in borrows {
          release_captured_result_borrow(borrow) |> ignore
        }
        return Err(issue)
      }
    }
  }
  Ok({ borrows, live: true, })
}

///|
pub fn captured_result_output_set_borrow_at(
  set : CapturedResultOutputSet,
  index : Int,
) -> CapturedResultBorrow? {
  if set.live {
    set.borrows.get(index)
  } else {
    None
  }
}

///|
pub fn captured_result_output_set_pin_at(
  set : CapturedResultOutputSet,
  index : Int,
) -> CapturedOutputPin? {
  if set.live {
    set.borrows.get(index).map(borrow => borrow.pin)
  } else {
    None
  }
}

///|
pub fn release_captured_result_output_set(
  set : CapturedResultOutputSet,
) -> Bool {
  if !set.live {
    return false
  }
  set.live = false
  for borrow in set.borrows {
    release_captured_result_borrow(borrow) |> ignore
  }
  true
}

///|
/// Release the Host's result port. Already completed descendants keep their own
/// results and the backing allocations they retain; new readers are revoked.
/// Exporting a result outside this run requires the Host to keep its port open
/// for that external use. This is not a GC/foreign-handle discovery mechanism.
pub fn close_captured_task_output(run : CapturedDAG, task : Int) -> Unit {
  if task < 0 || task >= run.outputs.length() {
    return
  }
  if !task_done(run, task) {
    return
  }
  if run.executions[task] is Some(execution) && !execution.disposed {
    close_task_execution(run, execution)
    return
  }
  run.lifetimes[task].live = false
  if task == 0 {
    run.source = None
  }
  // A pinned consumer owns a separate alias until its release. The ordinary
  // port is revoked immediately; its output slot may be dropped now.
  run.outputs[task] = None
  // A cached binding is not a started consumer. Drop our revoked aliases;
  // an in-flight native attempt keeps its input until cleanup is confirmed.
  for edge in run.graph.data {
    if edge.producer == task &&
      !run.done[edge.consumer] &&
      !(run.running is Some((active, _)) && active == edge.consumer) {
      clear_captured_inputs(run, edge.consumer)
    }
  }
  collect_captured_retention(run)
}

///|
fn collect_captured_retention(run : CapturedDAG) -> Unit {
  // Backward edges ensure one descending pass releases newly unreferenced
  // ancestors. This traversal is bounded by the checked graph's task limit.
  for task = run.resources.length() - 1; task >= 0; task = task - 1 {
    guard !run.lifetimes[task].live &&
      run.lifetimes[task].pins == 0 &&
      run.resources[task] is Some(resource) else {
      continue
    }
    let mut needed = false
    if run.executions[task] is Some(execution) &&
      (!execution.disposed || !task_execution_retention_released(execution)) {
      needed = true
    }
    for child in run.resources {
      if child is Some(child) && child.parents.contains(task) {
        needed = true
      }
    }
    if run.running is Some((active, _)) &&
      run.graph.data.any(edge => {
        edge.consumer == active && edge.producer == task
      }) {
      needed = true
    }
    if !needed && (resource.release_confirmed)() {
      if resource.holding is Some(holding) {
        @resources.release_allocation(run.ledger, holding) |> ignore
      }
      run.resources[task] = None
    }
  }
}

///|
/// Invoke only after the original Host confirms stopped/cleaned native work.
fn captured_cleanup_confirmed(
  run : CapturedDAG,
  execution : TaskExecution,
) -> Unit {
  if run.stopped &&
    run.running is Some((_, expected)) &&
    physical_equal(expected, execution) {
    run.running = None
    collect_captured_retention(run)
  }
}
