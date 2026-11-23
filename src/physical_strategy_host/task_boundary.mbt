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
  mut control : CapturedTaskControl?
  mut admitting_control : Bool
}

///|
priv struct CapturedBoundaryRead {
  hooks : CapturedTaskBoundaryHooks
  ledger : @resources.Ledger
  reservation : @resources.CapacityReservation
  record : CapturedBoundaryRecord
  mut returning : Int
  mut delivered : Bool
  mut forking : Bool
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
  SetupInUse
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
/// Explicit bounded original-key setup, before Compute work. Original graph and strategy
/// facts are checked before and after the SAME Run's actual admission. This
/// grants no observation/control permission or public Host capability. The
/// selected Host still admits its pre-Source strategy construction separately.
/// Read-only metadata does not split the graph or select a Debug strategy.
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
    control: None,
    admitting_control: false,
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
fn record_captured_task_boundary_commit(
  run : CapturedDAG,
  task : Int,
  reservation : @resources.Reservation,
) -> Unit {
  if run.activation is Observed(hooks) &&
    !hooks.closing &&
    hooks.original is Some(original) &&
    captured_boundary_setup_matches(run, original) {
    hooks.committed = Some({
      task,
      generation: run.generation,
      strategy_revision: run.revisions,
    })
    commit_captured_task_control(run, hooks, task, reservation)
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
      next_captured_task_ungated(run) == Some(task) &&
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
  if original.returning == 1 || original.forking {
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
  match
    acquire_captured_boundary_read(
      run, hooks, record, phase, captured_boundary_read_bytes,
    ) {
    Err(issue) => Err(issue)
    Ok(value) => Ok(Some(value))
  }
}

///|
/// The existing Owner issues an independent borrow of this SAME original fact.
/// The closed logical projection recipe includes the whole fixed higher
/// wrapper and lookup peak BEFORE its fork is allocated. Callers supply no
/// quote, Boolean admission, Ledger or replacement observation identity.
pub fn fork_captured_task_boundary_for_logical_projection(
  run : CapturedDAG,
  source : CapturedTaskBoundary,
) -> Result[CapturedTaskBoundary, CapturedTaskBoundaryIssue] {
  fork_captured_task_boundary(
    run, source, captured_boundary_logical_projection_bytes,
  )
}

///|
fn fork_captured_task_boundary(
  run : CapturedDAG,
  source : CapturedTaskBoundary,
  bytes : Int64,
) -> Result[CapturedTaskBoundary, CapturedTaskBoundaryIssue] {
  guard source.original is Some(original) else { return Err(ReadReturned) }
  if original.forking || original.returning != 0 {
    return Err(ReadInProgress)
  }
  // Pin BEFORE current as well as reservation callbacks: both can reenter.
  // This original read's own funded word is the fence, not a new Run field.
  original.forking = true
  if !captured_task_boundary_current(run, source) {
    original.forking = false
    return Err(StaleBoundary)
  }
  // Keep the source's funded original record alive through admission.
  let result = acquire_captured_boundary_read(
    run,
    original.hooks,
    original.record,
    source.phase,
    bytes,
  )
  original.forking = false
  result
}

///|
// Private issuance engine. Each caller selects a closed constructor purpose;
// no public numeric capacity request can mint a fork.
fn acquire_captured_boundary_read(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
  record : CapturedBoundaryRecord,
  phase : CapturedTaskBoundaryPhase,
  bytes : Int64,
) -> Result[CapturedTaskBoundary, CapturedTaskBoundaryIssue] {
  if hooks.admitting_read {
    return Err(ReadInProgress)
  }
  let task = record.task
  let generation = record.generation
  let strategy_revision = record.strategy_revision
  hooks.admitting_read = true
  let reservation = match
    @resources.reserve_capacity(run.ledger, bytes, bytes) {
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
      forking: false,
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
  Ok(boundary)
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
      if hooks.closing {
        retire_captured_task_control(hooks)
        if hooks.control is Some(control) &&
          original_control_cleanup_issue(control) is Some(issue) &&
          hooks.original is Some(setup) {
          setup.cleanup_issue = Some(issue)
        }
      }
      if hooks.closing &&
        !hooks.admitting_control &&
        hooks.control is None &&
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

///|
/// Dispose this installed holder only after stop and its actual setup/read
/// returns. This is not a Run-stop or physical-parent acknowledgement. The
/// metadata consumer drops its remaining holder alias before returning its
/// own parent loan; Normal's existing inline activation slot remains unchanged.
pub fn release_captured_task_boundary_hooks(
  run : CapturedDAG,
) -> Result[Unit, CapturedTaskBoundaryIssue] {
  if run.stopped && run.activation is Unarmed {
    return Ok(())
  }
  guard run.activation is Observed(hooks) else { return Err(SetupInUse) }
  if !run.stopped ||
    !hooks.closing ||
    hooks.admitting_read ||
    hooks.admitting_control ||
    hooks.control is Some(_) ||
    hooks.original is Some(_) ||
    hooks.reads is Some(_) {
    return Err(SetupInUse)
  }
  run.activation = Unarmed
  Ok(())
}

///|
pub(all) enum CapturedPausedDependencyIssue {
  Boundary(CapturedTaskBoundaryIssue)
  InvalidDependency
  InputWorkLimit
  DependencyUnavailable(RunIssue)
  Cell(@execution.RelationPresenceIssue)
}

///|
/// Scoped original materialized cell reader for an unfinished dependency.
/// A retained reader becomes empty when its synchronous visit ends.
struct CapturedPausedMaterializedDependency {
  mut original : CapturedPausedDependencyRead?
}

///|
priv struct CapturedPausedDependencyRead {
  loan : CapturedTaskBoundary
  revision : Int
  pin : CapturedOutputPin
}

///|
fn captured_paused_dependency_current(
  run : CapturedDAG,
  boundary : CapturedTaskBoundary,
  expected_revision : Int,
) -> Bool {
  boundary.phase is Settled &&
  boundary.original is Some(read) &&
  read.hooks.control is Some(control) &&
  control.phase is Paused &&
  !control.changing &&
  control.revision == expected_revision &&
  run.running is None &&
  captured_task_boundary_current(run, boundary)
}

///|
fn captured_paused_dependency_pin_current(
  read : CapturedPausedDependencyRead,
) -> Bool {
  let pin = read.pin
  let run = pin.run
  pin.live &&
  captured_paused_dependency_current(run, read.loan, read.revision) &&
  run.lifetimes[pin.task].live &&
  run.outputs[pin.task] is Some(Materialized(actual)) &&
  physical_equal(actual, pin.output)
}

///|
fn current_paused_dependency_read(
  scope : CapturedPausedMaterializedDependency,
) -> CapturedPausedDependencyRead? {
  guard scope.original is Some(read) &&
    captured_paused_dependency_pin_current(read) &&
    @execution.completed_output_available(read.pin.output) &&
    captured_paused_dependency_pin_current(read) else {
    return None
  }
  Some(read)
}

///|
pub fn captured_paused_materialized_dependency_shape(
  scope : CapturedPausedMaterializedDependency,
) -> (Int, Int)? {
  guard current_paused_dependency_read(scope) is Some(read) else { return None }
  Some(
    (
      @execution.completed_row_count(read.pin.output),
      @execution.completed_column_count(read.pin.output),
    ),
  )
}

///|
pub fn read_captured_paused_materialized_dependency_cell(
  scope : CapturedPausedMaterializedDependency,
  row : Int,
  column : Int,
) -> Result[@execution.Value?, CapturedPausedDependencyIssue] {
  guard current_paused_dependency_read(scope) is Some(read) else {
    return Err(Boundary(StaleBoundary))
  }
  let output = read.pin.output
  if row < 0 ||
    row >= @execution.completed_row_count(output) ||
    column < 0 ||
    column >= @execution.completed_column_count(output) {
    return Err(Cell(InvalidLayout))
  }
  let presence = @execution.completed_presence_cell(output, row, column)
  if !captured_paused_dependency_pin_current(read) {
    return Err(Boundary(StaleBoundary))
  }
  match presence {
    Ok(Absent) => Ok(None)
    Ok(Present(value)) => Ok(Some(@execution.capture(value)))
    Err(InvalidLayout) =>
      match @execution.completed_cell(output, row, column) {
        Some(value) => Ok(Some(value))
        None => Err(Cell(InvalidLayout))
      }
    Err(issue) => Err(Cell(issue))
  }
}

///|
/// Resolve an exact checked dependency at the scheduler's current Next task.
/// A caller looking up a retained Sample must still bind its producer output
/// and committed generation. This result carries no row or publication grant.
pub fn captured_paused_next_dependency(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
  revision : Int,
  committed_generation : Int,
  edge_index : Int,
) -> Result[@graph.DataEdge, CapturedPausedDependencyIssue] {
  guard captured_task_control_paused_task(run, hooks)
    is Ok((current, _, next, generation)) &&
    current == revision &&
    generation == committed_generation else {
    return Err(Boundary(StaleBoundary))
  }
  guard run.graph.data_at(edge_index) is Some(edge) &&
    next == Some(edge.consumer) &&
    !task_done(run, edge.consumer) &&
    task_done(run, edge.producer) else {
    return Err(InvalidDependency)
  }
  paused_dependency_target(run.graph, edge)
}

///|
/// Resolve the checked Next edge and that producer's own acknowledged start,
/// committed generation and consumed attempt. No row or retention is opened.
pub fn captured_paused_next_sample_dependency(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
  revision : Int,
  pause_generation : Int,
  edge_index : Int,
) -> Result[(@graph.DataEdge, Int, Int, Int), CapturedPausedDependencyIssue] {
  captured_paused_next_dependency(
    run, hooks, revision, pause_generation, edge_index,
  ).bind(edge => paused_sample_dependency_commit(run, edge))
}

///|
fn paused_sample_dependency_commit(
  run : CapturedDAG,
  edge : @graph.DataEdge,
) -> Result[(@graph.DataEdge, Int, Int, Int), CapturedPausedDependencyIssue] {
  match captured_relation_sample_commit(run, edge.producer) {
    Some((generation, attempt, start)) => Ok((edge, start, generation, attempt))
    None => Err(DependencyUnavailable(MissingOutput))
  }
}

///|
/// Select the actual edge for one original input ordinal on the scheduled
/// Next operation. The ordinal is from the checked logical port, regardless
/// of whether its physical edge was lowered from a Stage or operation input.
pub fn captured_paused_next_sample_input(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
  revision : Int,
  pause_generation : Int,
  input : Int,
  max_work : Int,
) -> Result[(@graph.DataEdge, Int, Int, Int), CapturedPausedDependencyIssue] {
  // Refuse a stale pause before sizing its traversal. This scalar check
  // does not inspect task readiness or touch an input.
  guard revision >= 2 &&
    pause_generation > 0 &&
    captured_task_control_state(run, hooks) is Ok((current, Paused)) &&
    current == revision &&
    run.generation == pause_generation else {
    return Err(Boundary(StaleBoundary))
  }
  if input < 0 {
    return Err(InvalidDependency)
  }
  let graph = run.graph
  let tasks = graph_task_count(graph).to_int64()
  let data = graph_data_count(graph).to_int64()
  let control = graph_control_count(graph).to_int64()
  // Bound the existing scheduler's worst-case complete readiness scan and
  // this one additional input-edge scan, before traversing either.
  let budget = max_work.to_int64()
  if tasks <= 0 ||
    budget <= data ||
    data + control + 1L > (budget - data) / tasks {
    return Err(InputWorkLimit)
  }
  guard captured_task_control_paused_task(run, hooks)
    is Ok((current, _, Some(next), generation)) &&
    current == revision &&
    generation == pause_generation else {
    return Err(Boundary(StaleBoundary))
  }
  guard graph_task_unit_index(graph, next) is Some(stage) &&
    captured_task_target(run, next) is Some(@pipeline.Step(operation)) &&
    graph_stage_operation_task(graph, stage, operation) == Some(next) &&
    @checked.unit_pipeline(graph_program(graph), stage) is Some(pipeline) &&
    @pipeline.step_at(pipeline, operation) is Some(step) &&
    @pipeline.input_occurrence_at(step, input) is Some(occurrence) else {
    return Err(InvalidDependency)
  }
  let mut selected = None
  for edge in graph.data_iter() {
    if edge.consumer == next &&
      paused_sample_input_matches(
        graph,
        edge,
        stage,
        operation,
        input,
        occurrence.target,
      ) {
      if selected is Some(_) {
        return Err(InvalidDependency)
      }
      selected = Some(edge)
    }
  }
  guard selected is Some(edge) && task_done(run, edge.producer) else {
    return Err(InvalidDependency)
  }
  paused_dependency_target(graph, edge).bind(original => {
    paused_sample_dependency_commit(run, original)
  })
}

///|
fn paused_sample_input_matches(
  graph : CheckedDAG,
  edge : @graph.DataEdge,
  stage : Int,
  operation : Int,
  input : Int,
  target : @pipeline.Target,
) -> Bool {
  let operation_input = edge.operation_input == Some((operation, input))
  match target {
    @pipeline.Step(_) =>
      operation_input &&
      edge.source_input is None &&
      edge.target == target &&
      graph_task_unit_index(graph, edge.producer) == Some(stage)
    @pipeline.Input(source) =>
      edge.source_input == Some(source) &&
      (
        operation_input ||
        (edge.operation_input is None && edge.input == source)
      )
  }
}

///|
fn paused_dependency_target(
  graph : CheckedDAG,
  edge : @graph.DataEdge,
) -> Result[@graph.DataEdge, CapturedPausedDependencyIssue] {
  if graph.targets_at(edge.producer).bind(value => value) != Some(edge.target) {
    return Err(DependencyUnavailable(UnsupportedGraph))
  }
  Ok(edge)
}

///|
/// Visit one exact checked edge from a completed materialized producer to the
/// scheduler's Next task. The caller must fund any copying on its own existing
/// owner and encode any retained cells within the synchronous visit.
/// Scope return clears the reader before releasing the pin.
pub fn with_captured_paused_materialized_dependency(
  run : CapturedDAG,
  source : CapturedTaskBoundary,
  revision : Int,
  edge_index : Int,
  max_pins : Int,
  visit : (@graph.DataEdge, CapturedPausedMaterializedDependency) -> Unit,
) -> Result[Unit, CapturedPausedDependencyIssue] {
  guard captured_paused_dependency_current(run, source, revision) &&
    source.original is Some(original) else {
    return Err(Boundary(StaleBoundary))
  }
  let edge = match
    captured_paused_next_dependency(
      run,
      original.hooks,
      revision,
      captured_task_boundary_generation(source),
      edge_index,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let loan = match
    fork_captured_task_boundary(
      run, source, captured_paused_materialized_dependency_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Boundary(issue))
  }
  let observed = visit_paused_materialized_dependency(
    run, loan, revision, edge, max_pins, visit,
  )
  let returned = return_captured_task_boundary(loan)
  // A refusal leaves the same fork on the original cleanup list. Preserve
  // an earlier selection/current failure while its cleanup remains pending.
  match (observed, returned) {
    (Err(issue), _) => Err(issue)
    (_, Err(issue)) => Err(Boundary(issue))
    (Ok(_), Ok(_)) =>
      if captured_paused_dependency_current(run, source, revision) {
        Ok(())
      } else {
        Err(Boundary(StaleBoundary))
      }
  }
}

///|
fn visit_paused_materialized_dependency(
  run : CapturedDAG,
  loan : CapturedTaskBoundary,
  revision : Int,
  edge : @graph.DataEdge,
  max_pins : Int,
  visit : (@graph.DataEdge, CapturedPausedMaterializedDependency) -> Unit,
) -> Result[Unit, CapturedPausedDependencyIssue] {
  if !captured_paused_dependency_current(run, loan, revision) {
    return Err(Boundary(StaleBoundary))
  }
  let pin = match
    pin_captured_task_output(run, edge.producer, edge.target, max_pins) {
    Ok(value) => value
    Err(issue) => return Err(DependencyUnavailable(issue))
  }
  let read = { loan, revision, pin, }
  let scope = { original: Some(read), }
  if current_paused_dependency_read(scope) is Some(_) {
    visit(edge, scope)
  }
  let current = current_paused_dependency_read(scope) is Some(_)
  scope.original = None
  // A still-open producer cannot retire on unpin, so an ordinary capture
  // reads one edge without triggering another whole-graph cleanup pass.
  if run.lifetimes[pin.task].live {
    drop_captured_output_pin(pin) |> ignore
  } else {
    release_captured_output_pin(pin) |> ignore
  }
  if !current || !captured_paused_dependency_current(run, loan, revision) {
    return Err(Boundary(StaleBoundary))
  }
  Ok(())
}
