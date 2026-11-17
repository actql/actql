///|
/// Internal task facts, not logical step identities, permission or a scheduler.
pub(all) enum CapturedTaskBoundaryPhase {
  Before
  Settled
  OutputEmitted
} derive(Eq, Debug)

///|
// Nominal immutable facts. Only two latest slots are retained by the hook;
// an older fact survives solely under an actual outstanding read reservation.
priv struct CapturedBoundaryRecord {
  task : Int
  generation : Int
  strategy_revision : Int
}

///|
// Issued only after the SAME Run Ledger reserves the actual constructor peak.
// Preparing/SetupCleanup live in the existing activation slot, not a new root.
priv struct CapturedBoundarySetup {
  owner : StrategyOfferOwner
  graph : CheckedDAG
  ledger : @resources.Ledger
  reservation : @resources.CapacityReservation
  generation : Int
  strategy_revision : Int
  mut returning : Bool
  mut refusal : CapturedTaskBoundaryIssue?
  mut cleanup_issue : @resources.LedgerIssue?
}

///|
struct CapturedTaskBoundaryHooks {
  mut original : CapturedBoundarySetup?
  mut before : CapturedBoundaryRecord?
  mut committed : CapturedBoundaryRecord?
  mut activation_grant : (Int, Int)?
  mut reads : CapturedTaskBoundary?
  mut admitting_read : Bool
  mut closing : Bool
}

///|
priv struct CapturedBoundaryRead {
  hooks : CapturedTaskBoundaryHooks
  ledger : @resources.Ledger
  reservation : @resources.CapacityReservation
  record : CapturedBoundaryRecord
  mut returning : Int
  mut delivered : Bool
}

///|
/// A same-Run reserved read borrow. Return it after the consumer disposes its
/// view. Stop revokes currentness but cannot acknowledge this borrow's return.
/// Returned tombstones contain only their original scalar snapshot, no owner.
struct CapturedTaskBoundary {
  mut original : CapturedBoundaryRead?
  mut previous : CapturedTaskBoundary?
  mut next : CapturedTaskBoundary?
  task : Int
  generation : Int
  strategy_revision : Int
  phase : CapturedTaskBoundaryPhase
}

///|
pub(all) enum CapturedTaskBoundaryIssue {
  AlreadyStarted
  Stopped
  ForeignGraph
  ForeignStrategy
  StaleBoundary
  ReadReturned
  ReadInProgress
  Resource(@resources.LedgerIssue)
} derive(Eq, Debug)

///|
fn captured_boundary_setup_unstarted(run : CapturedDAG) -> Bool {
  if run.running is Some(_) {
    return false
  }
  for task in captured_compute_first_task(run)..<run.done.length() {
    if run.done[task] ||
      run.executions[task] is Some(_) ||
      run.resources[task] is Some(_) {
      return false
    }
  }
  true
}

///|
fn captured_boundary_setup_matches(
  run : CapturedDAG,
  original : CapturedBoundarySetup,
) -> Bool {
  physical_equal(original.owner, run.offer_owner) &&
  physical_equal(original.graph, run.graph) &&
  physical_equal(original.ledger, run.ledger)
}

///|
// No physical child exists in these metadata owners. Disposal clears all
// retained references before the reservation acknowledgement is advertised.
fn retire_captured_boundary_setup(
  run : CapturedDAG,
  original : CapturedBoundarySetup,
) -> Bool {
  if original.returning {
    return false
  }
  original.returning = true
  match @resources.settle_capacity(original.ledger, original.reservation) {
    Err(issue) => {
      original.returning = false
      if original.cleanup_issue is None {
        original.cleanup_issue = Some(issue)
      }
      false
    }
    Ok(_) => {
      match run.activation {
        SetupCleanup(actual) if physical_equal(actual, original) =>
          run.activation = Unarmed
        Observed(hooks) if hooks.original is Some(actual) &&
          physical_equal(actual, original) => {
          hooks.original = None
          run.activation = Unarmed
        }
        _ => ()
      }
      true
    }
  }
}

///|
/// Explicit Debug setup, before Compute work. Original graph and strategy
/// facts are checked before and after the SAME Run's actual admission. This
/// grants no observation/control permission or public Host capability. The
/// selected Host still admits its pre-Source strategy construction separately.
pub fn prepare_captured_task_boundary_hooks(
  run : CapturedDAG,
  graph : CheckedDAG,
  strategy_revision : Int,
) -> Result[CapturedTaskBoundaryHooks, CapturedTaskBoundaryIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if !physical_equal(graph, run.graph) {
    return Err(ForeignGraph)
  }
  if strategy_revision != run.revisions {
    return Err(ForeignStrategy)
  }
  match run.activation {
    Observed(hooks) => {
      guard !hooks.closing &&
        hooks.original is Some(original) &&
        captured_boundary_setup_matches(run, original) else {
        return Err(AlreadyStarted)
      }
      return Ok(hooks)
    }
    Preparing | SetupCleanup(_) | Granted(_, _) => return Err(AlreadyStarted)
    Unarmed => ()
  }
  // Inline fence BEFORE any current/admission port. Reentry cannot activate a
  // task or construct another holder while this original setup is pending.
  let owner = run.offer_owner
  let generation = run.generation
  run.activation = Preparing
  let tasks = run.done.length() - captured_compute_first_task(run)
  if tasks < 0 || tasks > 1073741823 {
    run.activation = Unarmed
    return Err(Resource(@resources.PlanningLimit))
  }
  match @resources.charge_planning(run.ledger, 2 * tasks) {
    Err(issue) => {
      run.activation = Unarmed
      return Err(Resource(issue))
    }
    Ok(_) => ()
  }
  if run.stopped || !captured_boundary_setup_unstarted(run) {
    run.activation = Unarmed
    return Err(if run.stopped { Stopped } else { AlreadyStarted })
  }
  let reservation = match
    @resources.reserve_capacity(
      run.ledger,
      captured_boundary_setup_bytes,
      captured_boundary_setup_bytes,
    ) {
    Err(issue) => {
      run.activation = Unarmed
      return Err(Resource(issue))
    }
    Ok(value) => value
  }
  let original = {
    owner,
    graph,
    ledger: run.ledger,
    reservation,
    generation,
    strategy_revision,
    returning: false,
    refusal: None,
    cleanup_issue: None,
  }
  run.activation = SetupCleanup(original)
  let refusal : CapturedTaskBoundaryIssue? = if run.stopped {
    Some(Stopped)
  } else if !captured_boundary_setup_matches(run, original) {
    Some(ForeignGraph)
  } else if run.revisions != original.strategy_revision ||
    run.generation != original.generation {
    Some(ForeignStrategy)
  } else if !captured_boundary_setup_unstarted(run) {
    Some(AlreadyStarted)
  } else {
    None
  }
  if refusal is Some(issue) {
    original.refusal = refusal
    retire_captured_boundary_setup(run, original) |> ignore
    // A refusal is not cleanup acknowledgement. Pending setup remains in the
    // SAME activation slot and refresh retries its original reservation.
    return Err(issue)
  }
  let hooks = {
    original: Some(original),
    before: None,
    committed: None,
    activation_grant: None,
    reads: None,
    admitting_read: false,
    closing: false,
  }
  run.activation = Observed(hooks)
  Ok(hooks)
}

///|
fn record_captured_task_boundary_before(run : CapturedDAG, task : Int) -> Unit {
  if run.activation is Observed(hooks) &&
    !hooks.closing &&
    hooks.original is Some(original) &&
    captured_boundary_setup_matches(run, original) {
    hooks.before = Some({
      task,
      generation: run.generation,
      strategy_revision: run.revisions,
    })
  }
}

///|
// Reservation settlement and output visibility remain the same atomic commit.
fn record_captured_task_boundary_commit(run : CapturedDAG, task : Int) -> Unit {
  if run.activation is Observed(hooks) &&
    !hooks.closing &&
    hooks.original is Some(original) &&
    captured_boundary_setup_matches(run, original) {
    hooks.committed = Some({
      task,
      generation: run.generation,
      strategy_revision: run.revisions,
    })
  }
}

///|
fn captured_boundary_record_current(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
  record : CapturedBoundaryRecord,
  phase : CapturedTaskBoundaryPhase,
) -> Bool {
  if run.stopped ||
    hooks.closing ||
    !(hooks.original is Some(original) &&
    captured_boundary_setup_matches(run, original)) ||
    !(run.activation is Observed(actual) && physical_equal(actual, hooks)) ||
    record.generation != run.generation ||
    record.strategy_revision != run.revisions {
    return false
  }
  let task = record.task
  if task < captured_compute_first_task(run) || task >= run.done.length() {
    return false
  }
  match phase {
    Before =>
      next_captured_task(run) == Some(task) &&
      captured_task_activation_granted(run, task)
    Settled | OutputEmitted =>
      run.done[task] && run.outputs[task] is Some(_) && run.lifetimes[task].live
  }
}

///|
fn unlink_captured_boundary_read(
  boundary : CapturedTaskBoundary,
  hooks : CapturedTaskBoundaryHooks,
) -> Unit {
  match boundary.previous {
    Some(previous) => previous.next = boundary.next
    None => hooks.reads = boundary.next
  }
  if boundary.next is Some(next) {
    next.previous = boundary.previous
  }
  boundary.previous = None
  boundary.next = None
  boundary.original = None
  if hooks.reads is None && !hooks.closing && hooks.original is Some(setup) {
    setup.cleanup_issue = None
  }
}

///|
/// Return only after disposing this read. A failed original reservation return
/// stays owned in the active-borrow list; it is never a cleanup ACK.
pub fn return_captured_task_boundary(
  boundary : CapturedTaskBoundary,
) -> Result[Unit, CapturedTaskBoundaryIssue] {
  guard boundary.original is Some(original) else { return Err(ReadReturned) }
  if original.returning == 1 {
    return Err(ReadInProgress)
  }
  original.returning = 1
  match @resources.settle_capacity(original.ledger, original.reservation) {
    Err(issue) => {
      original.returning = 2
      if original.hooks.original is Some(setup) && setup.cleanup_issue is None {
        setup.cleanup_issue = Some(issue)
      }
      Err(Resource(issue))
    }
    Ok(_) => {
      unlink_captured_boundary_read(boundary, original.hooks)
      Ok(())
    }
  }
}

///|
/// Each actual read constructor acquires its own same-Ledger capacity before
/// allocating its wrapper/snapshot/list links. Admission cannot grant access.
/// No Sample/rows/history is retained, and absent facts construct no borrow.
pub fn read_captured_task_boundary(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
  phase : CapturedTaskBoundaryPhase,
) -> Result[CapturedTaskBoundary?, CapturedTaskBoundaryIssue] {
  let selected = match phase {
    Before => hooks.before
    _ => hooks.committed
  }
  guard selected is Some(record) else { return Ok(None) }
  if !captured_boundary_record_current(run, hooks, record, phase) {
    return Ok(None)
  }
  if hooks.admitting_read {
    return Err(ReadInProgress)
  }
  let task = record.task
  let generation = record.generation
  let strategy_revision = record.strategy_revision
  hooks.admitting_read = true
  let reservation = match
    @resources.reserve_capacity(
      run.ledger,
      captured_boundary_read_bytes,
      captured_boundary_read_bytes,
    ) {
    Err(issue) => {
      hooks.admitting_read = false
      return Err(Resource(issue))
    }
    Ok(value) => value
  }
  let boundary = {
    original: Some({
      hooks,
      ledger: run.ledger,
      reservation,
      record,
      returning: 0,
      delivered: false,
    }),
    previous: None,
    next: hooks.reads,
    task,
    generation,
    strategy_revision,
    phase,
  }
  if hooks.reads is Some(first) {
    first.previous = Some(boundary)
  }
  hooks.reads = Some(boundary)
  hooks.admitting_read = false
  let current = match phase {
    Before => hooks.before
    _ => hooks.committed
  }
  if !(current is Some(actual) && physical_equal(actual, record)) ||
    !captured_boundary_record_current(run, hooks, record, phase) {
    return_captured_task_boundary(boundary) |> ignore
    refresh_captured_task_boundary_cleanup(run)
    return Err(StaleBoundary)
  }
  boundary.original.unwrap().delivered = true
  Ok(Some(boundary))
}

///|
pub fn captured_task_boundary_current(
  run : CapturedDAG,
  boundary : CapturedTaskBoundary,
) -> Bool {
  guard boundary.original is Some(original) && original.returning == 0 else {
    return false
  }
  let hooks = original.hooks
  let selected = match boundary.phase {
    Before => hooks.before
    _ => hooks.committed
  }
  selected is Some(record) &&
  physical_equal(record, original.record) &&
  captured_boundary_record_current(run, hooks, record, boundary.phase)
}

///|
pub fn captured_task_boundary_matches_graph(
  boundary : CapturedTaskBoundary,
  graph : CheckedDAG,
) -> Bool {
  boundary.original is Some(read) &&
  read.returning == 0 &&
  read.hooks.original is Some(setup) &&
  physical_equal(setup.graph, graph)
}

///|
pub fn captured_task_boundary_task(boundary : CapturedTaskBoundary) -> Int {
  boundary.task
}

///|
pub fn captured_task_boundary_generation(
  boundary : CapturedTaskBoundary,
) -> Int {
  boundary.generation
}

///|
pub fn captured_task_boundary_strategy_revision(
  boundary : CapturedTaskBoundary,
) -> Int {
  boundary.strategy_revision
}

///|
pub fn captured_task_boundary_phase(
  boundary : CapturedTaskBoundary,
) -> CapturedTaskBoundaryPhase {
  boundary.phase
}

///|
// No new current/read/grant callback is installed in task emission. Only
// explicit cleanup uses the existing resource owner's original return engine.
fn refresh_captured_task_boundary_cleanup(run : CapturedDAG) -> Unit {
  match run.activation {
    SetupCleanup(original) =>
      retire_captured_boundary_setup(run, original) |> ignore
    Observed(hooks) => {
      // At most ONE pending head per refresh. Issued reads require their
      // actual consumer return; polling neither scans nor acknowledges them.
      if hooks.reads is Some(boundary) &&
        boundary.original is Some(original) &&
        (original.returning == 2 || !original.delivered) {
        return_captured_task_boundary(boundary) |> ignore
      }
      if hooks.closing &&
        !hooks.admitting_read &&
        hooks.reads is None &&
        hooks.original is Some(original) {
        retire_captured_boundary_setup(run, original) |> ignore
      }
    }
    _ => ()
  }
}

///|
fn stop_captured_task_boundary_hooks(run : CapturedDAG) -> Unit {
  if run.activation is Observed(hooks) {
    hooks.closing = true
    hooks.activation_grant = None
    hooks.before = None
    hooks.committed = None
  }
  refresh_captured_task_boundary_cleanup(run)
}

///|
pub fn captured_task_boundary_cleanup_pending(run : CapturedDAG) -> Bool {
  match run.activation {
    Preparing | SetupCleanup(_) => true
    Observed(hooks) =>
      hooks.original is Some(original) &&
      (hooks.closing || original.cleanup_issue is Some(_))
    _ => false
  }
}

///|
pub fn captured_task_boundary_cleanup_issue(
  run : CapturedDAG,
) -> @resources.LedgerIssue? {
  match run.activation {
    SetupCleanup(original) => original.cleanup_issue
    Observed(hooks) =>
      match hooks.original {
        Some(original) => original.cleanup_issue
        None => None
      }
    _ => None
  }
}

///|
pub fn captured_task_boundary_setup_failure(
  run : CapturedDAG,
) -> CapturedTaskBoundaryIssue? {
  match run.activation {
    SetupCleanup(original) => original.refusal
    Observed(hooks) =>
      match hooks.original {
        Some(original) => original.refusal
        None => None
      }
    _ => None
  }
}

///|
/// Optional installed holder only. Absence never enables Debug for Normal.
pub fn captured_task_boundary_hooks(
  run : CapturedDAG,
) -> CapturedTaskBoundaryHooks? {
  match run.activation {
    Observed(hooks) => Some(hooks)
    _ => None
  }
}
