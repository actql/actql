///|
/// Internal transitions of the existing pause/resume interval. These are not
/// public receipts or Run status: terminal Result publication stays upstream.
pub(all) enum CapturedTaskControlPhase {
  Paused
  Running
  Stepping(Int)
  PausePending
  Completed
  Retired
} derive(Eq, Debug)

///|
pub(all) enum CapturedTaskControlCommand {
  Pause
  ResumeStep
  ResumeTerminal
} derive(Eq, Debug)

///|
pub(all) enum CapturedTaskControlIssue {
  NotPrepared
  ForeignOwner
  AuthorizationMismatch
  BoundaryUnavailable(Int)
  AlreadyStarted
  Stopped
  InProgress
  StaleRevision
  ControlRevisionExhausted
  InvalidTransition
  Resource(@resources.LedgerIssue)
} derive(Eq, Debug)

///|
// Only the SAME installed hook retains this state, never an exported alias.
// The original tuple/subject/context are borrowed admitted Owner DATA. They
// cannot be replaced by another task's strategy generation or cancellation
// counter. Only scalar commit coordinates are retained per task. No command
// log, operation id, timer, Sample payload or scheduler is stored.
priv struct CapturedTaskControl {
  ledger : @resources.Ledger
  reservation : @resources.CapacityReservation
  mut binding : CapturedTaskControlBinding?
  mut revision : Int
  mut phase : CapturedTaskControlPhase
  mut remaining : Int
  entry_task : Int
  // Two scalar words per original task: generation, then consumed attempt.
  mut sample_commits : FixedArray[Int]?
  mut sample_start_revision : Int
  mut changing : Bool
  mut cleanup_issue : @resources.LedgerIssue?
}

///|
priv struct CapturedTaskControlBinding {
  tuple : @authorization.AccessTuple
  subject_cid : String
  context_cid : String
}

///|
// Control record1, binding1, retained binding/control Some2; OLD+NEW
// phase records2; snapshot pair/Ok2; resource refusal/Err2; cleanup Some1;
// reservation/current/planning result carriers3. These sites may conservatively
// coexist. Original spellings, tuple and Account are borrowed, never copied.
// The existing hook setup separately retains the original readiness iterators.
let captured_task_control_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 4L + 2L + 2L + 2L + 1L + 3L,
    // Control ledger/token/binding/phase/commits/cleanup6; binding tuple/subject/context3;
    // retained Some2; snapshot2; refusal2; cleanup1; carrier1.
    reference_slots: 6L + 3L + 2L + 2L + 2L + 1L + 1L,
    // Revision/remaining/entry task/start revision/fence5;
    // binding/control tags2; OLD+NEW phase tags/payload4; snapshot2;
    // refusal3; cleanup1; other result tags3.
    scalar_words: 5L + 2L + 4L + 2L + 3L + 1L + 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
pub fn captured_task_control_construction_bytes(tasks : Int) -> Int64 {
  // Fixed array header and length, its Some, and the two scalars per task.
  captured_task_control_bytes +
  @execution.preparation_representation_cost({
    record_headers: 2L,
    reference_slots: 1L,
    scalar_words: 2L + 2L * tasks.to_int64(),
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
fn captured_control_owner_matches(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
) -> Bool {
  run.activation is Observed(actual) &&
  physical_equal(actual, hooks) &&
  hooks.original is Some(original) &&
  captured_boundary_setup_matches(run, original) &&
  original.strategy_revision == run.revisions
}

///|
fn captured_control_authorized(
  authorization : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  subject_cid : String,
  context_cid : String,
  operation : String,
) -> Bool {
  tuple.operation == operation &&
  @authorization.dispatch_authorization_matches(
    authorization,
    current,
    tuple,
    Activation,
    subject_cid,
    context_cid,
  )
}

///|
// Per-operation capability, not a restriction on legal Programs. In
// particular a fused prefix, Effect, captured acquisition or raw Input does
// not acquire a manufactured logical boundary by installing a controller.
fn checked_control_boundary_available(
  graph : CheckedDAG,
  stage : Int,
  task : Int,
  entry? : Bool = false,
) -> Bool {
  guard @checked.unit_pipeline(graph_program(graph), stage) is Some(pipeline) else {
    return false
  }
  let count = @pipeline.step_count(pipeline)
  guard count > 0 else { return false }
  let selected = match graph_task_selected_step(graph, task) {
    Some(index) => index
    None => {
      if !(graph_task_prefix_end(graph, task) == Some(0) ||
        (graph_task_prefix_end(graph, task) is None && count == 1)) ||
        graph_task_target(graph, task) != Some(@pipeline.Step(0)) {
        return false
      }
      0
    }
  }
  graph_stage_operation_task(graph, stage, selected) == Some(task) &&
  (!entry || @pipeline.serialization_order(pipeline, selected) is None)
}

///|
/// A single captured port does not own a bulk traversal.
fn captured_control_boundary_available(graph : CheckedDAG, task : Int) -> Bool {
  guard graph_task_unit_index(graph, task) is Some(stage) else { return false }
  checked_control_boundary_available(graph, stage, task)
}

///|
/// Find the first unavailable entry boundary on the original checked graph.
/// The caller must fund at most one stage and one operation visit per task.
/// This changes no Run state and confers neither current authority nor capacity.
pub fn checked_task_control_entry_boundary_issue(graph : CheckedDAG) -> Int? {
  let tasks = @graph.graph_task_count(graph)
  let stages = graph.stage_tasks_count()
  if tasks == 0 ||
    stages > tasks ||
    @graph.graph_captured_prefix(graph) != 0 ||
    graph_program_has_effects(graph) {
    return Some(0)
  }
  let mut expected = 0
  for stage in 0..<stages {
    for task in graph.stage_tasks_iter_at(stage).unwrap() {
      // Ordinary checked graphs enumerate physical tasks in authored stage
      // order. A fused alias repeats a physical task and cannot be a stop.
      if task != expected ||
        !checked_control_boundary_available(graph, stage, task, entry=true) {
        return Some(expected)
      }
      expected += 1
    }
  }
  if expected == tasks {
    None
  } else {
    Some(expected)
  }
}

///|
/// Explicit pre-work stop-on-entry on this original Run's single hook. The
/// configured Run owner supplies the real run-unit subject and actual Account
/// decision; this function neither issues authority nor advertises capability.
/// A second setup cannot reset revision or construct per-task control state.
pub fn prepare_captured_task_control(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
  authorization : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  subject_cid : String,
  context_cid : String,
) -> Result[Unit, CapturedTaskControlIssue] {
  if run.stopped || hooks.closing {
    return Err(Stopped)
  }
  if !captured_control_owner_matches(run, hooks) {
    return Err(ForeignOwner)
  }
  if hooks.admitting_control {
    return Err(InProgress)
  }
  if hooks.control is Some(_) {
    return Err(AlreadyStarted)
  }
  if !captured_control_authorized(
      authorization, current, tuple, subject_cid, context_cid, "pause",
    ) {
    return Err(AuthorizationMismatch)
  }
  if !captured_boundary_setup_unstarted(run) {
    return Err(AlreadyStarted)
  }
  if run.done.length() == 0 ||
    captured_compute_first_task(run) != 0 ||
    graph_program_has_effects(run.graph) {
    return Err(BoundaryUnavailable(0))
  }
  // Block activation and recursive setup BEFORE either resource callback.
  hooks.admitting_control = true
  let generation = run.generation
  let tasks = run.done.length()
  // Fund the original boundary and commit slots plus the one unstarted
  // readiness scan. Inspection reuses the admitted entry coordinate.
  let readiness = 1L +
    graph_data_count(run.graph).to_int64() +
    graph_control_count(run.graph).to_int64()
  let units_per_task = 6L + readiness
  if tasks.to_int64() > 2147483647L / units_per_task {
    hooks.admitting_control = false
    return Err(Resource(@resources.PlanningLimit))
  }
  let admitted = @resources.charge_planning(
    run.ledger,
    (tasks.to_int64() * units_per_task).to_int(),
  )
  if admitted is Err(issue) {
    hooks.admitting_control = false
    refresh_captured_task_boundary_cleanup(run)
    return Err(Resource(issue))
  }
  if checked_task_control_entry_boundary_issue(run.graph) is Some(task) {
    hooks.admitting_control = false
    refresh_captured_task_boundary_cleanup(run)
    return Err(BoundaryUnavailable(task))
  }
  guard next_captured_task_ungated(run) is Some(entry_task) else {
    hooks.admitting_control = false
    refresh_captured_task_boundary_cleanup(run)
    return Err(BoundaryUnavailable(0))
  }
  let bytes = captured_task_control_construction_bytes(tasks)
  let reservation = match
    @resources.reserve_capacity(run.ledger, bytes, bytes) {
    Err(issue) => {
      hooks.admitting_control = false
      refresh_captured_task_boundary_cleanup(run)
      return Err(Resource(issue))
    }
    Ok(value) => value
  }
  hooks.control = Some({
    ledger: run.ledger,
    reservation,
    binding: Some({ tuple, subject_cid, context_cid, }),
    revision: 0,
    phase: Paused,
    remaining: tasks,
    entry_task,
    sample_commits: Some(FixedArray::make(2 * tasks, 0)),
    sample_start_revision: 0,
    changing: false,
    cleanup_issue: None,
  })
  hooks.admitting_control = false
  if run.stopped || hooks.closing {
    refresh_captured_task_boundary_cleanup(run)
    return Err(Stopped)
  }
  if !captured_control_owner_matches(run, hooks) || run.generation != generation {
    // The fence rules out task progress during admission. Any other loss of
    // the original strategy refuses and disposes this installed component.
    retire_captured_task_control(hooks)
    return Err(ForeignOwner)
  }
  Ok(())
}

///|
/// Internal bounded observation only. Public reads still need their existing
/// same-Run/current/egress admission and durable projection/receipt supplier.
pub fn captured_task_control_state(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
) -> Result[(Int, CapturedTaskControlPhase), CapturedTaskControlIssue] {
  if run.stopped || hooks.closing {
    return Err(Stopped)
  }
  if !captured_control_owner_matches(run, hooks) {
    return Err(ForeignOwner)
  }
  if hooks.admitting_control {
    return Err(InProgress)
  }
  guard hooks.control is Some(control) else { return Err(NotPrepared) }
  if control.changing {
    return Err(InProgress)
  }
  Ok((control.revision, control.phase))
}

///|
/// Observe the exact admitted first task before any physical start.
pub fn captured_task_control_entry_task(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
) -> Int? {
  guard captured_task_control_state(run, hooks) is Ok((0, Paused)) &&
    hooks.control is Some(control) &&
    control.sample_start_revision == 0 &&
    hooks.committed is None &&
    run.running is None &&
    !resident_provision_pending(run) &&
    !task_done(run, control.entry_task) else {
    return None
  }
  Some(control.entry_task)
}

///|
/// Observe the last original task commit while the same controller is paused.
pub fn captured_task_control_paused_task(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
) -> Result[(Int, Int, Int?, Int), CapturedTaskControlIssue] {
  match captured_task_control_state(run, hooks) {
    Err(issue) => Err(issue)
    Ok((revision, Paused)) => {
      guard revision >= 2 &&
        hooks.committed is Some(original) &&
        original.generation == run.generation &&
        original.strategy_revision == run.revisions &&
        original.task >= captured_compute_first_task(run) &&
        original.task < run.done.length() &&
        run.done[original.task] else {
        return Err(InvalidTransition)
      }
      Ok(
        (
          revision,
          original.task,
          next_captured_task_ungated(run),
          original.generation,
        ),
      )
    }
    Ok(_) => Err(InvalidTransition)
  }
}

///|
/// One existing Run's compare-and-transition. No durable receipt is implied;
/// the existing Journal owner must admit/commit/lookup that separate facet.
pub fn command_captured_task_control(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
  expected_revision : Int,
  command : CapturedTaskControlCommand,
  authorization : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  subject_cid : String,
  context_cid : String,
) -> Result[Unit, CapturedTaskControlIssue] {
  if run.stopped || hooks.closing {
    return Err(Stopped)
  }
  if !captured_control_owner_matches(run, hooks) {
    return Err(ForeignOwner)
  }
  if hooks.admitting_control {
    return Err(InProgress)
  }
  guard hooks.control is Some(control) else { return Err(NotPrepared) }
  if control.changing {
    return Err(InProgress)
  }
  // End this borrowed binding's lexical lifetime BEFORE any resource/current
  // callback can stop and settle the controller. No higher semantic context
  // survives an autonomous cleanup acknowledgement in this command frame.
  let authorized = match control.binding {
    None => false
    Some(binding) =>
      binding.subject_cid == subject_cid &&
      binding.context_cid == context_cid &&
      binding.tuple.principal == tuple.principal &&
      binding.tuple.connection == tuple.connection &&
      binding.tuple.resource == tuple.resource &&
      captured_control_authorized(
        authorization,
        current,
        tuple,
        subject_cid,
        context_cid,
        if command == Pause {
          "pause"
        } else {
          "resume"
        },
      )
  }
  if !authorized {
    return Err(AuthorizationMismatch)
  }
  if expected_revision != control.revision {
    return Err(StaleRevision)
  }
  // Reserve revision headroom BEFORE work for a command and its one eventual
  // automatic pause/terminal transition. Exhaustion cannot occur after commit.
  if control.revision > 2147483645 {
    return Err(ControlRevisionExhausted)
  }
  let phase = match (command, control.phase) {
    (Pause, Running) | (Pause, Stepping(_)) =>
      if run.running is Some(_) {
        PausePending
      } else {
        Paused
      }
    (ResumeStep, Paused) => {
      guard next_captured_task_ungated(run) is Some(task) else {
        return Err(InvalidTransition)
      }
      Stepping(task)
    }
    (ResumeTerminal, Paused) => Running
    _ => return Err(InvalidTransition)
  }
  let generation = run.generation
  let bytes = captured_task_control_construction_bytes(run.done.length())
  control.changing = true
  let checked = @resources.grow_capacity_reservation(
    control.ledger,
    control.reservation,
    bytes,
    bytes,
  )
  control.changing = false
  if run.stopped || hooks.closing {
    refresh_captured_task_boundary_cleanup(run)
    return Err(Stopped)
  }
  if checked is Err(issue) {
    return Err(Resource(issue))
  }
  if !captured_control_owner_matches(run, hooks) ||
    run.generation != generation ||
    control.revision != expected_revision {
    return Err(StaleRevision)
  }
  control.phase = phase
  control.revision += 1
  Ok(())
}

///|
fn captured_task_control_allows_activation(run : CapturedDAG) -> Bool {
  guard run.activation is Observed(hooks) else { return true }
  if hooks.admitting_control {
    return false
  }
  guard hooks.control is Some(control) else { return !hooks.closing }
  if hooks.closing ||
    control.changing ||
    !captured_control_owner_matches(run, hooks) ||
    control.binding is None {
    return false
  }
  match control.phase {
    Running | Stepping(_) => true
    _ => false
  }
}

///|
// Called only for the original slot's first successful output commit. Before
// and settled are the two phases of one operation credit. The same already
// funded Debug control owns the remaining count.
fn commit_captured_task_control(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
  task : Int,
  reservation : @resources.Reservation,
) -> Unit {
  guard hooks.control is Some(control) else { return }
  if !captured_control_owner_matches(run, hooks) || control.binding is None {
    return
  }
  if control.sample_start_revision > 0 &&
    control.sample_commits is Some(commits) {
    let relation = match run.outputs[task] {
      Some(Materialized(output)) => @execution.completed_has_cell_access(output)
      Some(Managed(_)) => true
      _ => false
    }
    if relation {
      let attempt = @resources.completed_output_attempt_sequence(
        run.ledger,
        reservation,
      )
      if attempt > 0 {
        // commit_task_output already excluded a second commit of this slot.
        commits[2 * task] = run.generation
        commits[2 * task + 1] = attempt
      }
    }
  }
  control.remaining -= 1
  if control.remaining == 0 {
    control.phase = Completed
    control.revision += 1
  } else if control.phase == Stepping(task) || control.phase == PausePending {
    control.phase = Paused
    control.revision += 1
  }
}

///|
// This record has no exported alias or physical child. Remove the semantic
// context before settlement; a declined return restores only token custody.
// The fence prevents owner reentry from refunding the containing hook early.
fn retire_captured_task_control(hooks : CapturedTaskBoundaryHooks) -> Unit {
  if hooks.admitting_control {
    return
  }
  guard hooks.control is Some(control) else { return }
  if control.changing {
    return
  }
  hooks.admitting_control = true
  hooks.control = None
  control.binding = None
  control.sample_commits = None
  control.sample_start_revision = 0
  control.phase = Retired // Scalar tombstone, never a Run outcome.
  match @resources.settle_capacity(control.ledger, control.reservation) {
    Err(issue) => {
      control.cleanup_issue = Some(issue)
      hooks.control = Some(control)
    }
    Ok(_) => ()
  }
  hooks.admitting_control = false
}

///|
fn original_control_cleanup_issue(
  control : CapturedTaskControl,
) -> @resources.LedgerIssue? {
  control.cleanup_issue
}
