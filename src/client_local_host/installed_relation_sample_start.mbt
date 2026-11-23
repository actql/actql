///|
pub(all) enum InstalledRelationSampleStartIssue {
  ForeignSampleStart
  SampleStartRequiresControl
  SampleStartRun(ClientInstalledManagedRunIssue)
  SampleStartCapacity(@resources.PreparationCapacityIssue)
  SampleStartControl(@strategy.CapturedTaskControlIssue)
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
let installed_relation_sample_start_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 168L,
    reference_slots: 510L,
    scalar_words: 212L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
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
  let bytes = if journal_bytes == 0 {
    installed_relation_sample_start_bytes
  } else {
    match installed_relation_sample_journal_bytes(journal_bytes) {
      Some(cost) => cost
      None => return Err(SampleStartCapacity(InvalidExtent))
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
  if !profile.unattended_start ||
    @strategy.captured_relation_sample_start_selected(captured) !=
    start_acknowledged {
    return Err(SampleStartRequiresControl)
  }
  let subject = @publication.publication_contract_identity(profile.definition)
  let context = @publication.run_publication_execution_context(
    @publication_host.client_compiled_run_admission(profile.compiled),
  )
  let tuple : @authorization.AccessTuple = {
    principal,
    connection,
    resource: "run",
    operation: if start_acknowledged {
      "resume"
    } else {
      "pause"
    },
  }
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
  if start_acknowledged {
    guard @strategy.captured_task_boundary_hooks(captured) is Some(hooks) else {
      return Err(SampleStartControl(@strategy.NotPrepared))
    }
    return @strategy.command_captured_task_control(
      captured,
      hooks,
      0,
      ResumeTerminal,
      authorized,
      account,
      tuple,
      subject,
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
