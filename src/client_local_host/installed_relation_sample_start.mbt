///|
pub(all) enum InstalledRelationSampleStartIssue {
  ForeignSampleStart
  SampleStartRequiresControl
  SampleStartRun(ClientInstalledManagedRunIssue)
  SampleStartCapacity(@resources.PreparationCapacityIssue)
  SampleStartControl(@strategy.CapturedTaskControlIssue)
}

///|
pub(all) enum InstalledRelationSampleEntryCommand {
  PrepareEntry
  ResumeEntryStep(Int)
  ResumeEntryTerminal(Int)
}

///|
// The same Request, retained compiler and physical setup must still belong
// to one installed owner. This check takes no external callbacks.
fn installed_relation_sample_start_matches(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  captured : @strategy.CapturedDAG,
) -> Bool {
  physical_equal(owner.request, request) &&
  owner.ledger is Some(ledger) &&
  physical_equal(ledger, @strategy.captured_dag_ledger(captured)) &&
  owner.source_free_captured is Some(actual) &&
  physical_equal(actual, captured) &&
  owner.publication_definition is Some(original) &&
  physical_equal(original, definition) &&
  @publication_host.client_compiled_run_has_original_definition(
    compiled, definition,
  ) &&
  installed_managed_run_compilation_original(owner, prepared) is Some(artifact) &&
  @publication_host.client_compiled_run_matches_pure_compilation(
    compiled, prepared, artifact,
  )
}

///|
// Node's bounded selection/action packets, ready and revision closures,
// original setup/definition references, bridge argument vectors and Result
// conversion (H18/R43/W20). Core's reserve/current and acknowledgement
// options, typed returns and temporary controls add H14/R29/W16.
// The selected Journal handoff adds the option and view records, retained
// methods and captured references, scope checks and bridge frames, and an
// observation return slot (H40/R192/W64). The selected scalar probe and
// reservation callback use another H6/R22/W8. The original charged ticket,
// checked CID projection, transactional recheck and fixed start row/bind
// packets add H24/R62/W24. Row and codec backing is admitted separately
// after the probe and before the first retained read.
// The dispatch-held adoption port, its original authority packet, Journal
// writer receiver, scoped current/receive calls and receipt reference add
// H24/R64/W32. The prefix and SQL construction keep their own scoped quote.
// The installed Driver route, authorization packet and revocable Owner and
// profile getters remain live through Compute (H18/R42/W26).
// One installed Account/tuple binding and its synchronous two-phase receiver
// borrow the same setup before and after ACK, including bridge arguments
// and before/after current observations (H24/R56/W22).
// The resuming start ticket retains its scalar quote and synchronous resize
// receiver until the transaction repeats the extent check (H7/R18/W10).
// The checked Map CID is borrowed through the Core tuple, runtime receiver,
// Journal reply and dispatch arguments into the suspended controller (R6).
let installed_relation_sample_start_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 175L,
    reference_slots: 534L,
    scalar_words: 222L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
// The live entry keeps the Node controller, scope and functions, Journal
// handoff, pending wait Promise/listener and its cleanup, bridge arguments
// and Core phase/action result carriers on the same original reservation.
// The continued path borrows the checked Step IDs and retains one bounded
// pause receipt, acknowledgement, and deadline timer alongside the wait.
// Include the pause time in the row, receipt, current query and observation.
// The committed generation adds two Core tuples, park and current query
// arguments, the SQL row, pause and resume projections, and resume bridge input.
// The accepted time occupies a transaction local, SQL argument and row,
// and the retained receipt handed off to the Driver.
// The next Step adds SQL binds/row fields, pause and receipt projections,
// a Core argument and nullable branches. The resume guard carries the
// completed Step into the Journal CAS on the same scope. Four CID copies
// cover UTF-16 selection, SQLite argument/return and Journal handoff.
// Inspect's scalar probe borrows the bound Map and two revision values
// before the separate caller-owned projection reservation (R4/W2).
// Resume receipt issue borrows the existing Run Definition on the controller
// and uses one fixed issue-selection record (H1/R5). The command Read funds
// the actual receipt construction.
let installed_sample_debug_entry_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 45L,
    reference_slots: 143L,
    scalar_words: 66L,
    owned_utf16_units: 3L * 71L,
    owned_wire_bytes: 71L,
  },
).unwrap()

///|
fn installed_relation_sample_journal_bytes(bytes : Int) -> Int64? {
  guard bytes > 0 &&
    bytes <= 2147483519 &&
    program_artifact_parse_layout((bytes, bytes, bytes)) is Some(parse) &&
    @encode.text_writer_construction_inventory(bytes, bytes, bytes)
    is Some(text) &&
    @encode.hash_writer_construction_inventory(bytes + 4, bytes + 1)
    is Some(hash) &&
    compilation_canonical_emitter_layout(bytes + 1) is Some(emitter) else {
    return None
  }
  let n = bytes.to_int64()
  // One stored-byte envelope includes the Run, intent, restart and epoch.
  // Each byte bounds a JSON node/key/text position. The currentness reads
  // may coexist with the starting and last checked originals. Count four
  // generations, plus a second raw Run/key copy in each ready/restart check.
  // Co-count readmitted Common Definition/intent and both canonical sinks;
  // JavaScript row, JSON snapshot and canonical restart controls are separate.
  @execution.preparation_representation_cost({
    record_headers: 4L *
    (
      4L * n +
      2L * parse.temporary.record_headers +
      text.record_headers +
      hash.record_headers +
      2L * emitter.record_headers
    ),
    reference_slots: 4L *
    (
      8L * n +
      2L * parse.temporary.reference_slots +
      text.reference_slots +
      hash.reference_slots +
      2L * emitter.reference_slots
    ),
    scalar_words: 4L *
    (
      4L * n +
      2L * parse.temporary.scalar_words +
      text.scalar_words +
      hash.scalar_words +
      2L * emitter.scalar_words
    ),
    owned_utf16_units: 4L *
    (
      9L * n +
      2L * parse.temporary.owned_utf16_units +
      text.owned_utf16_units +
      hash.owned_utf16_units
    ),
    owned_wire_bytes: 4L *
    (3L * n + 2L * parse.temporary.owned_wire_bytes + hash.owned_wire_bytes),
  })
}

///|
/// Fund the synchronous installed receiver with the original adopted body's
/// live reservation. Returning the receiver drops its temporary aliases; the
/// parent keeps the admitted high-water debit until its ordinary retirement.
pub fn reserve_installed_relation_sample_start(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  captured : @strategy.CapturedDAG,
  journal_bytes? : Int = 0,
  debug_entry? : Bool = false,
  previous_journal_bytes? : Int = 0,
) -> Result[Unit, InstalledRelationSampleStartIssue] {
  if owner.source_free_opening {
    return Err(SampleStartRun(CleanupPending))
  }
  guard installed_relation_sample_start_matches(
      owner, prepared, request, compiled, definition, captured,
    ) &&
    managed_run_publication_body(owner, prepared) is Ok(holder) else {
    return Err(ForeignSampleStart)
  }
  let (retained, execution) = match
    @resources.preparation_body_borrow_reserved_extents(holder) {
    Err(issue) => return Err(SampleStartCapacity(issue))
    Ok(extents) => extents
  }
  if journal_bytes < 0 ||
    previous_journal_bytes < 0 ||
    (journal_bytes == 0 && previous_journal_bytes != 0) ||
    (
      journal_bytes > 0 &&
      previous_journal_bytes != owner.sample_start_journal_bytes
    ) {
    return Err(SampleStartCapacity(InvalidExtent))
  }
  let bytes = if journal_bytes == 0 {
    installed_relation_sample_start_bytes +
    (if debug_entry { installed_sample_debug_entry_bytes } else { 0L })
  } else {
    if debug_entry {
      return Err(SampleStartCapacity(InvalidExtent))
    }
    guard installed_relation_sample_journal_bytes(journal_bytes) is Some(cost) else {
      return Err(SampleStartCapacity(InvalidExtent))
    }
    // The original Journal start ticket holds the earlier quote without a
    // refund. The larger envelope covers all coexisting old/new row and codec
    // generations; an exact debit of the difference avoids funding them twice.
    if owner.sample_start_journal_bytes == 0 {
      cost
    } else {
      guard installed_relation_sample_journal_bytes(
          owner.sample_start_journal_bytes,
        )
        is Some(previous) else {
        return Err(SampleStartCapacity(InvalidExtent))
      }
      Int64::max(0L, cost - previous)
    }
  }
  guard @execution.checked_preparation_add_product(retained, bytes, 1L)
    is Some(retained) &&
    @execution.checked_preparation_add_product(execution, bytes, 1L)
    is Some(execution) else {
    return Err(SampleStartCapacity(InvalidExtent))
  }
  owner.source_free_opening = true
  let reserved = @resources.reserve_preparation_publication_phase(
    holder, prepared, retained, execution,
  )
  owner.source_free_opening = false
  match reserved {
    Err(issue) => return Err(SampleStartCapacity(issue))
    Ok(_) => ()
  }
  guard installed_relation_sample_start_matches(
      owner, prepared, request, compiled, definition, captured,
    ) &&
    managed_run_publication_body(owner, prepared) is Ok(current) &&
    physical_equal(current, holder) else {
    return Err(ForeignSampleStart)
  }
  owner.sample_start_journal_bytes = Int::max(
    owner.sample_start_journal_bytes,
    journal_bytes,
  )
  Ok(())
}

///|
/// Attach the fixed Journal start handoff on the same installed Debug setup.
/// The opted-in dispatcher supplies the acknowledged revision before work.
/// Sample custody and disclosure require their own current owner admissions.
pub fn acknowledge_installed_relation_sample_start(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  captured : @strategy.CapturedDAG,
  revision : Int,
) -> Result[Unit, InstalledRelationSampleStartIssue] {
  if !installed_relation_sample_start_matches(
      owner, prepared, request, compiled, definition, captured,
    ) {
    return Err(ForeignSampleStart)
  }
  match check_installed_managed_run(owner, prepared, request) {
    Err(issue) => return Err(SampleStartRun(issue))
    Ok(_) => ()
  }
  if !installed_relation_sample_start_matches(
      owner, prepared, request, compiled, definition, captured,
    ) {
    return Err(ForeignSampleStart)
  }
  guard @strategy.captured_task_boundary_hooks(captured) is Some(hooks) else {
    return Err(SampleStartControl(@strategy.NotPrepared))
  }
  @strategy.acknowledge_captured_relation_sample_start(
    captured,
    hooks,
    @publication.publication_contract_identity(definition),
    @publication.run_publication_execution_context(
      @publication_host.client_compiled_run_admission(compiled),
    ),
    revision,
  ).map_err(issue => SampleStartControl(issue))
}

///|
/// An explicitly unattended Sample profile prepares the existing live
/// controller before the Journal claim. Its first resume uses the same
/// controller only after the Journal's acknowledged revision was latched.
pub fn advance_installed_relation_sample_start_control(
  profile : ClientCheckedRelationSampleProfile,
  owner : ClientInstalledManagedRun,
  captured : @strategy.CapturedDAG,
  account : @authorization.AdmittedAccountConfiguration,
  principal : String,
  connection : String,
  start_acknowledged : Bool,
) -> Result[Unit, InstalledRelationSampleStartIssue] {
  if !physical_equal(profile.captured, captured) ||
    !installed_relation_sample_profile_current(owner, profile) {
    return Err(ForeignSampleStart)
  }
  if !(profile.start_mode is UnattendedTerminal) ||
    @strategy.captured_relation_sample_start_selected(captured) !=
    start_acknowledged {
    return Err(SampleStartRequiresControl)
  }
  advance_installed_relation_sample_control(
    profile,
    captured,
    account,
    principal,
    connection,
    if start_acknowledged {
      @strategy.ResumeTerminal
    } else {
      @strategy.Pause
    },
  )
}

///|
/// Prepare a stop-on-entry profile, then activate only its exact acknowledged
/// start. The existing Journal owner supplies the accepted command and revision.
pub fn advance_installed_relation_sample_debug_entry(
  profile : ClientCheckedRelationSampleProfile,
  owner : ClientInstalledManagedRun,
  captured : @strategy.CapturedDAG,
  account : @authorization.AdmittedAccountConfiguration,
  principal : String,
  connection : String,
  command : InstalledRelationSampleEntryCommand,
) -> Result[Unit, InstalledRelationSampleStartIssue] {
  if !physical_equal(profile.captured, captured) ||
    !installed_relation_sample_profile_current(owner, profile) {
    return Err(ForeignSampleStart)
  }
  guard profile.start_mode is PausedEntry else {
    return Err(SampleStartRequiresControl)
  }
  let selected : @strategy.CapturedTaskControlCommand = match command {
    PrepareEntry => {
      if @strategy.captured_relation_sample_start_selected(captured) {
        return Err(SampleStartRequiresControl)
      }
      Pause
    }
    ResumeEntryStep(revision) | ResumeEntryTerminal(revision) => {
      if !@strategy.captured_relation_sample_start_matches_revision(
          captured, revision,
        ) {
        return Err(SampleStartRequiresControl)
      }
      if command is ResumeEntryStep(_) {
        ResumeStep
      } else {
        ResumeTerminal
      }
    }
  }
  advance_installed_relation_sample_control(
    profile, captured, account, principal, connection, selected,
  )
}

///|
/// Read the actual boundary on the same acknowledged installed Debug Run.
pub fn installed_relation_sample_debug_entry_runnable(
  profile : ClientCheckedRelationSampleProfile,
  owner : ClientInstalledManagedRun,
  captured : @strategy.CapturedDAG,
  start_revision : Int,
) -> Result[Bool, InstalledRelationSampleStartIssue] {
  let hooks = match
    installed_debug_task_control(profile, owner, captured, start_revision) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @strategy.captured_task_control_state(captured, hooks) {
    Ok((_, Running | Stepping(_))) => Ok(true)
    Ok((_, Paused)) => Ok(false)
    Ok(_) => Err(SampleStartControl(@strategy.InvalidTransition))
    Err(issue) => Err(SampleStartControl(issue))
  }
}

///|
fn installed_debug_task_control(
  profile : ClientCheckedRelationSampleProfile,
  owner : ClientInstalledManagedRun,
  captured : @strategy.CapturedDAG,
  start_revision : Int,
) -> Result[
  @strategy.CapturedTaskBoundaryHooks,
  InstalledRelationSampleStartIssue,
] {
  guard physical_equal(profile.captured, captured) &&
    installed_relation_sample_profile_current(owner, profile) else {
    return Err(ForeignSampleStart)
  }
  guard profile.start_mode is PausedEntry &&
    @strategy.captured_relation_sample_start_matches_revision(
      captured, start_revision,
    ) else {
    return Err(SampleStartRequiresControl)
  }
  guard @strategy.captured_task_boundary_hooks(captured) is Some(hooks) else {
    return Err(SampleStartControl(@strategy.NotPrepared))
  }
  Ok(hooks)
}

///|
/// Observe a checked Step from this Run's latest actual committed task.
pub fn installed_relation_sample_debug_task_pause(
  profile : ClientCheckedRelationSampleProfile,
  owner : ClientInstalledManagedRun,
  captured : @strategy.CapturedDAG,
  start_revision : Int,
) -> Result[(Int, String, String, Int), InstalledRelationSampleStartIssue] {
  let hooks = match
    installed_debug_task_control(profile, owner, captured, start_revision) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @strategy.captured_task_control_paused_task(captured, hooks) {
    Err(issue) => Err(SampleStartControl(issue))
    Ok((revision, task, next_task, committed_generation)) => {
      guard profile.driver_outputs.get(task) is Some((step_id, _, _)) else {
        return Err(SampleStartControl(@strategy.BoundaryUnavailable(task)))
      }
      // The completed Step identifies the Sample and the command boundary.
      // The next Step is a separate view of the scheduler's original choice.
      let next_step = match next_task {
        Some(index) =>
          match profile.driver_outputs.get(index) {
            Some((step, _, _)) => step
            None => ""
          }
        None => ""
      }
      Ok((revision, step_id, next_step, committed_generation))
    }
  }
}

///|
pub(all) enum InstalledRelationSampleNextInputIssue {
  NextInputForeignOriginal
  NextInputStalePause
  NextInputWorkLimit
} derive(Eq, Debug)

///|
/// Bind the selected Next input to an original retained producer on the same
/// installed Run. The Host's Read owns the lookup and any returned Sample.
pub fn installed_relation_sample_debug_next_input(
  profile : ClientCheckedRelationSampleProfile,
  owner : ClientInstalledManagedRun,
  captured : @strategy.CapturedDAG,
  start_revision : Int,
  control_revision : Int,
  pause_generation : Int,
  next_step_id : String,
  input : Int,
  max_work : Int,
) -> Result[
  (String, String, String, Int, Int)?,
  InstalledRelationSampleNextInputIssue,
] {
  let hooks = match
    installed_debug_task_control(profile, owner, captured, start_revision) {
    Ok(value) => value
    Err(ForeignSampleStart) => return Err(NextInputForeignOriginal)
    Err(_) => return Err(NextInputStalePause)
  }
  let (edge, start, generation, attempt) = match
    @strategy.captured_paused_next_sample_input(
      captured, hooks, control_revision, pause_generation, input, max_work,
    ) {
    Ok(value) => value
    Err(InputWorkLimit) => return Err(NextInputWorkLimit)
    Err(Boundary(_)) => return Err(NextInputStalePause)
    Err(_) => return Ok(None)
  }
  if start != start_revision {
    return Err(NextInputStalePause)
  }
  guard profile.driver_outputs.get(edge.consumer) is Some((consumer, _, _)) else {
    return Ok(None)
  }
  if consumer != next_step_id {
    return Err(NextInputStalePause)
  }
  Ok(
    profile.driver_outputs
    .get(edge.producer)
    .map(output => {
      let (producer, port, contract) = output
      (producer, port, contract, generation, attempt)
    }),
  )
}

///|
/// Check the installed Account before accepting a durable resume. Physical
/// activation still binds the same tuple, subject and context at handoff.
pub fn installed_relation_sample_debug_resume_allowed(
  profile : ClientCheckedRelationSampleProfile,
  owner : ClientInstalledManagedRun,
  captured : @strategy.CapturedDAG,
  account : @authorization.AdmittedAccountConfiguration,
  principal : String,
  connection : String,
) -> Bool {
  physical_equal(profile.captured, captured) &&
  installed_relation_sample_profile_current(owner, profile) &&
  profile.start_mode is PausedEntry &&
  @authorization.evaluate_account(
    account,
    installed_relation_sample_control_tuple(principal, connection, false),
  )
  is Allow(_)
}

///|
/// Consume only the still-current live boundary of an acknowledged command.
pub fn resume_installed_relation_sample_debug_task(
  profile : ClientCheckedRelationSampleProfile,
  owner : ClientInstalledManagedRun,
  captured : @strategy.CapturedDAG,
  account : @authorization.AdmittedAccountConfiguration,
  principal : String,
  connection : String,
  start_revision : Int,
  control_revision : Int,
  step_id : String,
  next_step_id : String,
  committed_generation : Int,
  step : Bool,
) -> Result[Unit, InstalledRelationSampleStartIssue] {
  let boundary = installed_relation_sample_debug_task_pause(
    profile, owner, captured, start_revision,
  )
  match boundary {
    Err(issue) => return Err(issue)
    Ok((revision, original_step, original_next, generation)) =>
      if revision != control_revision ||
        original_step != step_id ||
        original_next != next_step_id ||
        generation != committed_generation {
        return Err(SampleStartControl(@strategy.StaleRevision))
      }
  }
  advance_installed_relation_sample_control(
    profile,
    captured,
    account,
    principal,
    connection,
    if step {
      @strategy.ResumeStep
    } else {
      @strategy.ResumeTerminal
    },
    expected_revision=control_revision,
  )
}

///|
fn advance_installed_relation_sample_control(
  profile : ClientCheckedRelationSampleProfile,
  captured : @strategy.CapturedDAG,
  account : @authorization.AdmittedAccountConfiguration,
  principal : String,
  connection : String,
  command : @strategy.CapturedTaskControlCommand,
  expected_revision? : Int = 0,
) -> Result[Unit, InstalledRelationSampleStartIssue] {
  let subject = @publication.publication_contract_identity(profile.definition)
  let context = @publication.run_publication_execution_context(
    @publication_host.client_compiled_run_admission(profile.compiled),
  )
  let tuple = installed_relation_sample_control_tuple(
    principal,
    connection,
    command is Pause,
  )
  guard @authorization.bind_dispatch_authorization(
      account,
      tuple,
      Activation,
      subject,
      context,
    )
    is Ok(authorized) else {
    return Err(SampleStartControl(@strategy.AuthorizationMismatch))
  }
  if !(command is Pause) {
    guard @strategy.captured_task_boundary_hooks(captured) is Some(hooks) else {
      return Err(SampleStartControl(@strategy.NotPrepared))
    }
    return @strategy.command_captured_task_control(
      captured, hooks, expected_revision, command, authorized, account, tuple, subject,
      context,
    ).map_err(issue => SampleStartControl(issue))
  }
  let hooks = match
    @strategy.prepare_captured_task_boundary_hooks(
      captured,
      @strategy.captured_dag_graph(captured),
      @strategy.captured_dag_strategy_revision(captured),
    ) {
    Err(_) => return Err(SampleStartControl(@strategy.NotPrepared))
    Ok(value) => value
  }
  @strategy.prepare_captured_task_control(
    captured, hooks, authorized, account, tuple, subject, context,
  ).map_err(issue => SampleStartControl(issue))
}

///|
fn installed_relation_sample_control_tuple(
  principal : String,
  connection : String,
  pause : Bool,
) -> @authorization.AccessTuple {
  {
    principal,
    connection,
    resource: "run",
    operation: if pause {
      "pause"
    } else {
      "resume"
    },
  }
}
