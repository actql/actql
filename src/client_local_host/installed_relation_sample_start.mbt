///|
pub(all) enum InstalledRelationSampleStartIssue {
  ForeignSampleStart
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
// options, typed returns and temporary controls add H14/R29/W16. This covers
// no output bytes or Sample controller construction.
let installed_relation_sample_start_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 32L,
    reference_slots: 72L,
    scalar_words: 36L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

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
  let bytes = installed_relation_sample_start_bytes
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
