///|
struct NativeClientRelationFileWork {
  access : NativeLocalRelationOriginalAccess
  start : NativeClientWorkFirstStart
  prepared : @host.PreparedClientProgram
  compiled : @host.ClientCompiledRun
  definition : @publication.PublicationContract
  source : @row_file.NativeRelationFileCapture
  run : @strategy.CapturedDAG
  source_usage : @resources.LedgerUsage
  execution : @local.LocalValuesExecution
  requirements : @local.ClientLocalRequirements
  entry : NativeClientRelationFileWorkEntry
  mut output_bridge : @local.LocalValuesResultExport?
  mut stopping : Bool
}

///|
/// Preserve the first failed original occurrence and its exact cleanup duty.
/// Retry closes only those children, without claiming or reopening any Work.
struct NativeClientRelationFileWorkFailure {
  issue : NativeClientSourceWorkIssue
  mut cleanup : (() -> Bool)?
  mut access : NativeLocalValuesOriginalAccess?
  entry : NativeClientRelationFileWorkEntry?
}

///|
pub fn NativeClientRelationFileWorkFailure::issue(
  self : NativeClientRelationFileWorkFailure,
) -> NativeClientSourceWorkIssue {
  self.issue
}

///|
pub fn NativeClientRelationFileWorkFailure::close(
  self : NativeClientRelationFileWorkFailure,
) -> Bool {
  if self.cleanup is Some(_) || self.access is Some(_) {
    guard self.entry is Some(entry) &&
      entry.used &&
      entry.arena.matches_business_scope(true) else {
      return false
    }
    if !values_original_cleanup_entered(self.access) {
      return false
    }
  }
  if self.cleanup is Some(cleanup) && !cleanup() {
    return false
  }
  self.cleanup = None
  if self.entry is Some(entry) {
    if entry.used {
      if !entry.arena.finish_business_cleanup() {
        return false
      }
    } else if !entry.cancel_unclaimed_in_original_read() {
      return false
    }
  }
  self.access = None
  true
}

///|
fn relation_file_work_failure(
  issue : NativeClientSourceWorkIssue,
  access? : NativeLocalValuesOriginalAccess? = None,
  cleanup? : (() -> Bool)? = None,
  entry? : NativeClientRelationFileWorkEntry? = None,
) -> NativeClientRelationFileWorkFailure {
  { issue, access, cleanup, entry, }
}

///|
// A quote is DATA, not a reservation or permission. Compare every simultaneous
// dimension against this already-installed original Ledger's remaining supply.
fn relation_file_inventory_available(
  ledger : @resources.Ledger,
  source : @resources.LedgerLimits,
  compute : @resources.LedgerLimits,
) -> Bool {
  // Common counts the whole graph's attempts/holdings, including Source
  // task zero. Its byte quote covers only the suffix. Add the Source bytes
  // and transfer, without inventing a second Source task reservation.
  if source.attempts != 1 ||
    source.holdings != 1 ||
    compute.attempts < 2 ||
    compute.holdings < 2 {
    return false
  }
  guard @resources.add_ledger_limits(
      { ..source, attempts: 0, holdings: 0, },
      compute,
    )
    is Some(required) else {
    return false
  }
  let limits = @resources.ledger_limits(ledger)
  let usage = @resources.ledger_usage(ledger)
  required.planning_work <= limits.planning_work - usage.planning_work &&
  required.attempts <=
  limits.attempts - usage.attempts - usage.reserved_attempts &&
  required.holdings <= limits.holdings - usage.holdings &&
  required.transfer_bytes <=
  limits.transfer_bytes -
  usage.transferred_bytes -
  usage.uncertain_transfer_bytes -
  usage.reserved_transfer_bytes &&
  required.retained_bytes <=
  limits.retained_bytes - usage.held_bytes - usage.reserved_retention_bytes &&
  required.execution_bytes <=
  limits.execution_bytes - usage.reserved_execution_bytes
}

///|
/// Internal installed-Host assembly of one declared relation-file Source and
/// real Common Compute suffix. The coordinator already admitted this exact
/// business execution and the original Submission/Run under its captured Read.
/// This entry takes no caller Ledger or Allow and never enables CLI admission.
/// Paths are selected Host data, not a replacement immutable installation.
pub fn NativeLocalHostConnection::open_original_relation_file_source_work(
  self : NativeLocalHostConnection,
  operation : NativeLocalStoreOperation,
  entry : NativeClientRelationFileWorkEntry,
  installed_contracts : @local.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  requirements : @local.ClientLocalRequirements,
  occurrence : String,
  quantum : Int,
  max_rounds : Int,
) -> Result[NativeClientRelationFileWork, NativeClientRelationFileWorkFailure] {
  let ledger = match entry.take_entered_ledger(self, operation) {
    Some(value) => value
    None => return entry.unavailable
  }
  let selection = entry.selection
  let source_limits = entry.limits
  let access = entry.access.unwrap()
  let original = entry.original
  // The nominal once-only take above established this same live payload.
  let (prepared, compiled, definition) = entry.payload.unwrap()
  let request = access.base.request
  let execution = match operation.receiver.domain {
    StoreBusinessDomain(value) => value
    StoreRunObservationDomain => return entry.unavailable
  }
  let (declaration, requirement, acquisition) = match access.source {
    RelationFile(declaration, requirement, acquisition) =>
      (declaration, requirement, acquisition)
    SourceFree => return entry.unavailable
  }
  let unstarted = (issue : NativeClientSourceWorkIssue) => {
    relation_file_work_failure(
      issue,
      access=Some(access.base),
      entry=Some(entry),
    )
  }
  if !access.current() {
    return Err(
      unstarted(
        OriginalOperation(access.base.primary.unwrap_or(AuthorizationDenied)),
      ),
    )
  }
  // Recheck immediately after original Read current: that exchange could
  // invalidate or replace correspondence. Never rebuild the cache in business.
  if !relation_file_prepared_binding_current(
      self.journal,
      request,
      prepared,
      compiled,
      definition,
    ) {
    return Err(unstarted(OriginalRunNotCurrent))
  }
  match
    self.journal.validate_prepared_run_binding(
      request, prepared, compiled, definition,
    ) {
    Err(issue) => return Err(unstarted(Journal(issue)))
    Ok(_) => ()
  }
  // The exact requirements owner already rejected Graph carriers before
  // construction. matches below binds that immutable prepared graph, so do not
  // repeat its allocating task/input scan in this business preflight.
  if quantum <= 0 ||
    max_rounds <= 0 ||
    !requirements.matches(
      prepared, installed_contracts, values_body, fragment_body, ordered_body,
    ) ||
    !@host.client_query_requirement_matches_program(prepared, 0, 0, requirement) ||
    @host.prepared_client_acquisition_count(prepared) != 1 ||
    @strategy.graph_captured_prefix(@host.prepared_client_graph(prepared)) != 1 ||
    @strategy.graph_result_count(@host.prepared_client_graph(prepared)) != 1 ||
    @strategy.graph_task_count(@host.prepared_client_graph(prepared)) > 32 ||
    @strategy.graph_program_has_effects(@host.prepared_client_graph(prepared)) ||
    @host.client_compiled_run_has_infers(compiled) {
    return Err(unstarted(Configuration))
  }
  match access.lookup() {
    Ok(Retained(record)) if @publication.publication_contract_identity(
        record.definition,
      ) ==
      @publication.publication_contract_identity(definition) &&
      !record.physical_start_claimed &&
      !record.cancellation_requested &&
      record.checkpoint is None => ()
    Ok(_) => return Err(unstarted(NeedsOriginalReconciliation))
    Err(issue) => return Err(unstarted(OriginalOperation(issue)))
  }
  let source_inventory = match
    @row_file.native_relation_file_capture_limits(
      declaration, requirement, acquisition, selection, source_limits,
    ) {
    Err(issue) => return Err(unstarted(RelationFile(issue)))
    Ok(value) => value
  }
  guard entry.arena.owns_only_control() &&
    requirements.simultaneous_limits() is Some(compute_inventory) &&
    relation_file_inventory_available(
      ledger, source_inventory, compute_inventory,
    ) else {
    return Err(unstarted(Configuration))
  }
  let start = match access.claim() {
    Err(issue) => return Err(unstarted(OriginalOperation(issue)))
    Ok(value) => value
  }
  match access.require_start_current(start) {
    Err(issue) => return Err(unstarted(OriginalOperation(issue)))
    Ok(_) => ()
  }
  let source = match
    @row_file.prepare_native_relation_file_capture(
      original.host,
      execution,
      declaration,
      requirement,
      acquisition,
      occurrence,
      selection,
      source_limits,
    ) {
    Err(failure) =>
      return Err(
        relation_file_work_failure(
          RelationFile(failure.issue()),
          access=Some(access.base),
          entry=Some(entry),
          cleanup=Some(() => failure.retry_cleanup() is Ok(true)),
        ),
      )
    Ok(value) => value
  }
  let source_cleanup = () => source.close() is Ok(true)
  let mut complete = false
  for _ in 0..<max_rounds {
    match access.require_start_current(start) {
      Err(issue) =>
        return Err(
          relation_file_work_failure(
            OriginalOperation(issue),
            access=Some(access.base),
            entry=Some(entry),
            cleanup=Some(source_cleanup),
          ),
        )
      Ok(_) => ()
    }
    match source.advance(quantum) {
      Err(failure) =>
        return Err(
          relation_file_work_failure(
            RelationFile(failure.issue()),
            access=Some(access.base),
            entry=Some(entry),
            cleanup=Some(source_cleanup),
          ),
        )
      Ok(true) => {
        complete = true
        break
      }
      Ok(false) => ()
    }
  }
  if !complete {
    return Err(
      relation_file_work_failure(
        Configuration,
        access=Some(access.base),
        entry=Some(entry),
        cleanup=Some(source_cleanup),
      ),
    )
  }
  let source_usage = @resources.ledger_usage(ledger)
  match access.require_start_current(start) {
    Err(issue) =>
      return Err(
        relation_file_work_failure(
          OriginalOperation(issue),
          access=Some(access.base),
          entry=Some(entry),
          cleanup=Some(source_cleanup),
        ),
      )
    Ok(_) => ()
  }
  let capture = match source.capture() {
    Err(issue) =>
      return Err(
        relation_file_work_failure(
          RelationFile(issue),
          access=Some(access.base),
          entry=Some(entry),
          cleanup=Some(source_cleanup),
        ),
      )
    Ok(value) => value
  }
  let input = match @rows.row_capture_source(capture) {
    Err(issue) =>
      return Err(
        relation_file_work_failure(
          CaptureIdentity(issue),
          access=Some(access.base),
          entry=Some(entry),
          cleanup=Some(source_cleanup),
        ),
      )
    Ok(value) => value
  }
  guard @local.open_captured_local_retained_host_on_ledger(
      prepared,
      input,
      ledger,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      requirements=Some(requirements),
    )
    is Some(setup) else {
    return Err(
      relation_file_work_failure(
        Configuration,
        access=Some(access.base),
        entry=Some(entry),
        cleanup=Some(source_cleanup),
      ),
    )
  }
  let run = @driver.dispatch_driver_run(@builtin.configured_host_driver(setup))
  let computed = match
    @local.execute_captured_local_tasks_guarded(
      setup,
      capture,
      requirements,
      quantum,
      max_rounds,
      () => access.require_start_current(start) is Ok(_),
      require_live=Some(() => access.poll_execution_original(start)),
    ) {
    Err(failure) =>
      return Err(
        relation_file_work_failure(
          match access.base.primary {
            Some(issue) => OriginalOperation(issue)
            None =>
              LocalExecution(
                @local.local_values_execution_failure_issue(failure),
              )
          },
          access=Some(access.base),
          entry=Some(entry),
          cleanup=Some(() => {
            @local.retry_local_values_execution_failure_cleanup(failure) &&
            source_cleanup()
          }),
        ),
      )
    Ok(value) => value
  }
  let owner : NativeClientRelationFileWork = {
    access,
    start,
    prepared,
    compiled,
    definition,
    source,
    run,
    source_usage,
    execution: computed,
    requirements,
    entry,
    output_bridge: None,
    stopping: false,
  }
  match owner.require_current() {
    Err(issue) =>
      return Err(
        relation_file_work_failure(
          issue,
          access=Some(access.base),
          entry=Some(entry),
          cleanup=Some(() => owner.close()),
        ),
      )
    Ok(_) => ()
  }
  Ok(owner)
}

///|
fn NativeClientRelationFileWork::require_current(
  self : NativeClientRelationFileWork,
) -> Result[Unit, NativeClientSourceWorkIssue] {
  if !self.entry.arena.matches_business_scope(false) {
    return self.entry.unavailable_current
  }
  if self.stopping ||
    !relation_file_prepared_binding_current(
      self.start.journal,
      self.start.request,
      self.prepared,
      self.compiled,
      self.definition,
    ) {
    return Err(OriginalRunNotCurrent)
  }
  if self.access.base.primary is Some(issue) {
    return Err(OriginalOperation(issue))
  }
  match
    self.start.journal.validate_prepared_run_binding(
      self.start.request,
      self.prepared,
      self.compiled,
      self.definition,
    ) {
    Err(issue) => return Err(Journal(issue))
    Ok(_) => ()
  }
  self.access
  .require_start_current(self.start)
  .map_err(issue => OriginalOperation(issue))
}

///|
pub fn NativeClientRelationFileWork::close(
  self : NativeClientRelationFileWork,
) -> Bool {
  if !self.entry.arena.matches_business_scope(true) {
    return false
  }
  self.stopping = true
  if !values_original_cleanup_entered(Some(self.access.base)) {
    return false
  }
  self.close_export()
  self.execution.close() &&
  self.source.close() is Ok(true) &&
  self.entry.arena.finish_business_cleanup()
}
