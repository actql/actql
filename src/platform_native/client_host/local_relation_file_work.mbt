///|
priv enum NativeRelationFileExecutionPlan {
  QueryFileExecution(@local.ClientLocalRequirements)
  WholeFileExecution(@execution.RetainedRowDecodeLimits, Int, Int)
}

///|
priv enum NativeRelationFileExecutionSelection {
  QueryFileSelection(
    @local.ClientInstalledSequenceContracts,
    String,
    String?,
    String?,
    @local.ClientLocalRequirements
  )
  WholeFileSelection(
    @local.ClientInstalledManagedRun,
    @local.ClientInstalledWholeSourceCapacity,
    @row_file.NativeRelationFilePreparedProvider,
    () -> String
  )
}

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
  plan : NativeRelationFileExecutionPlan
  entry : NativeClientRelationFileWorkEntry
  mut output_bridge : @local.LocalValuesResultExport?
  capture_times : (String, String)?
  mut publication_original : (
    @publication.RunEvidenceValue,
    @publication.RunEvidenceValue,
    @publication.RunEvidenceValue,
    @publication.PublicationContract,
    String,
    String,
  )?
  mut publication : @local.ClientProgramPublication?
  mut identity_scan : @execution_query.CapturedSourceCellIdentityScan?
  mut publication_basis : (Int64, Int64)?
  mut publication_growing : Bool
  mut publication_identity_issue : NativeClientSourceWorkIssue?
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
  open_original_relation_file_work_selected(
    self,
    operation,
    entry,
    ledger,
    QueryFileSelection(
      installed_contracts, values_body, fragment_body, ordered_body, requirements,
    ),
    occurrence,
    quantum,
    max_rounds,
  )
}

///|
/// Consume this exact prepared Whole Source entry and its same original Run.
/// No Query fallback, new Source preparation, compiler, Ledger or Root exists.
pub fn NativeLocalHostConnection::open_original_whole_relation_file_source_work(
  self : NativeLocalHostConnection,
  operation : NativeLocalStoreOperation,
  entry : NativeClientRelationFileWorkEntry,
  occurrence : String,
  quantum : Int,
  max_rounds : Int,
  current_time : () -> String,
) -> Result[NativeClientRelationFileWork, NativeClientRelationFileWorkFailure] {
  guard entry.access is Some(access) &&
    access.source is WholeRelationFile(_, _, _, managed, selected, provider) else {
    return entry.unavailable
  }
  let ledger = match entry.take_entered_ledger(self, operation) {
    Some(value) => value
    None => return entry.unavailable
  }
  open_original_relation_file_work_selected(
    self,
    operation,
    entry,
    ledger,
    WholeFileSelection(managed, selected, provider, current_time),
    occurrence,
    quantum,
    max_rounds,
  )
}

///|
fn open_original_relation_file_work_selected(
  host : NativeLocalHostConnection,
  operation : NativeLocalStoreOperation,
  entry : NativeClientRelationFileWorkEntry,
  ledger : @resources.Ledger,
  selected : NativeRelationFileExecutionSelection,
  occurrence : String,
  quantum : Int,
  max_rounds : Int,
) -> Result[NativeClientRelationFileWork, NativeClientRelationFileWorkFailure] {
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
      host.journal,
      request,
      prepared,
      compiled,
      definition,
    ) {
    return Err(unstarted(OriginalRunNotCurrent))
  }
  match
    host.journal.validate_prepared_run_binding(
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
    @host.prepared_client_acquisition_count(prepared) != 1 ||
    @strategy.graph_captured_prefix(@host.prepared_client_graph(prepared)) != 1 ||
    @strategy.graph_result_count(@host.prepared_client_graph(prepared)) != 1 ||
    @strategy.graph_task_count(@host.prepared_client_graph(prepared)) > 32 ||
    @strategy.graph_program_has_effects(@host.prepared_client_graph(prepared)) ||
    @host.client_compiled_run_has_infers(compiled) {
    return Err(unstarted(Configuration))
  }
  let plan = match (selected, access.source) {
    (
      QueryFileSelection(contracts, values, fragment, ordered, requirements),
      RelationFile(_, requirement, _),
    ) => {
      if !requirements.matches(prepared, contracts, values, fragment, ordered) ||
        !@host.client_query_requirement_matches_program(
          prepared, 0, 0, requirement,
        ) {
        return Err(unstarted(Configuration))
      }
      QueryFileExecution(requirements)
    }
    (
      WholeFileSelection(managed, capacity, provider, _),
      WholeRelationFile(_, source, _, original, actual, same),
    ) => {
      if !physical_equal(managed, original) ||
        !physical_equal(capacity, actual) ||
        !physical_equal(provider, same) ||
        !@host.client_source_acquisition_matches_program(prepared, 0, 0, source) {
        return Err(unstarted(Configuration))
      }
      guard @local.installed_managed_capture_publication_geometry_original(
          managed, prepared, request,
        )
        is Some((_, rows, entries, evidence_entries)) else {
        return Err(unstarted(OriginalRunNotCurrent))
      }
      WholeFileExecution(rows, entries, evidence_entries)
    }
    _ => return Err(unstarted(Configuration))
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
  let read = match (selected, access.source) {
    (
      QueryFileSelection(_, _, _, _, requirements),
      RelationFile(declaration, requirement, acquisition),
    ) => {
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
      None
    }
    (
      WholeFileSelection(managed, capacity, _, _),
      WholeRelationFile(declaration, _, _, _, _, _),
    ) => {
      let (read, _, _, actual) = match
        @local.begin_installed_managed_whole_source_read_on_ledger(
          managed,
          prepared,
          request,
          declaration,
          capacity,
          ledger,
          source_limits.page.max_bytes.to_int64(),
          source_limits.page.max_bytes.to_int64(),
        ) {
        Err(issue) => return Err(unstarted(InstalledRun(issue)))
        Ok(value) => value
      }
      // The Run already retains this same read before any later callback.
      let pending = issue => {
        relation_file_work_failure(
          issue,
          access=Some(access.base),
          entry=Some(entry),
          cleanup=Some(() => @local.retire_installed_source_read(read) is Ok(_)),
        )
      }
      if !physical_equal(actual, capacity) {
        return Err(pending(Configuration))
      }
      Some(read)
    }
    _ => return Err(unstarted(Configuration))
  }
  let unstarted = issue => {
    relation_file_work_failure(
      issue,
      access=Some(access.base),
      entry=Some(entry),
      cleanup=Some(() => {
        match read {
          None => true
          Some(read) => @local.retire_installed_source_read(read) is Ok(_)
        }
      }),
    )
  }
  let start = match access.claim() {
    Err(issue) => return Err(unstarted(OriginalOperation(issue)))
    Ok(value) => value
  }
  match access.require_start_current(start) {
    Err(issue) => return Err(unstarted(OriginalOperation(issue)))
    Ok(_) => ()
  }
  let started_at = match selected {
    QueryFileSelection(_, _, _, _, _) => None
    WholeFileSelection(_, _, _, now) => Some(now())
  }
  // Clock callbacks may reenter the original Run. Fence that actual callback
  // before Source Root/reader construction; no new claim or clock sample.
  if started_at is Some(_) {
    match access.require_start_current(start) {
      Err(issue) => return Err(unstarted(OriginalOperation(issue)))
      Ok(_) => ()
    }
  }
  let opened = match (selected, access.source, read) {
    (
      QueryFileSelection(_, _, _, _, _),
      RelationFile(declaration, requirement, acquisition),
      None,
    ) =>
      @row_file.prepare_native_relation_file_capture(
        original.host,
        execution,
        declaration,
        requirement,
        acquisition,
        occurrence,
        selection,
        source_limits,
      )
    (
      WholeFileSelection(_, capacity, provider, _),
      WholeRelationFile(declaration, _, _, _, _, _),
      Some(read),
    ) =>
      @row_file.prepare_native_managed_relation_file_input_capture(
        original.host,
        execution,
        declaration,
        read,
        capacity,
        provider.capacity(),
        occurrence,
        selection,
        source_limits,
        prepared_provider=Some(provider),
      )
    _ => return Err(unstarted(Configuration))
  }
  let source = match opened {
    Err(failure) =>
      return Err(
        relation_file_work_failure(
          RelationFile(failure.issue()),
          access=Some(access.base),
          entry=Some(entry),
          cleanup=Some(() => {
            failure.retry_cleanup() is Ok(true) &&
            (match read {
              None => true
              Some(read) => @local.retire_installed_source_read(read) is Ok(_)
            })
          }),
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
  let capture_times = match (started_at, selected) {
    (Some(started), WholeFileSelection(_, _, _, now)) => Some((started, now()))
    _ => None
  }
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
  let setup = match selected {
    QueryFileSelection(contracts, values, fragment, ordered, requirements) =>
      match
        @local.open_captured_local_retained_host_on_ledger(
          prepared,
          input,
          ledger,
          contracts,
          values,
          fragment,
          ordered,
          requirements=Some(requirements),
        ) {
        Some(value) => value
        None =>
          return Err(
            relation_file_work_failure(
              Configuration,
              access=Some(access.base),
              entry=Some(entry),
              cleanup=Some(source_cleanup),
            ),
          )
      }
    WholeFileSelection(managed, _, _, _) =>
      match
        @local.open_installed_managed_capture_host(managed, prepared, request, [
          input,
        ]) {
        Ok((value, _, _)) => value
        Err(issue) =>
          return Err(
            relation_file_work_failure(
              InstalledCapture(issue),
              access=Some(access.base),
              entry=Some(entry),
              cleanup=Some(source_cleanup),
            ),
          )
      }
  }
  let run = @driver.dispatch_driver_run(@builtin.configured_host_driver(setup))
  let computed = match
    (match plan {
      QueryFileExecution(requirements) =>
        @local.execute_captured_local_tasks_guarded(
          setup,
          capture,
          requirements,
          quantum,
          max_rounds,
          () => access.require_start_current(start) is Ok(_),
          require_live=Some(() => access.poll_execution_original(start)),
        )
      WholeFileExecution(_, _, _) =>
        @local.execute_source_free_local_tasks_guarded(
          setup,
          quantum,
          max_rounds,
          () => access.require_start_current(start) is Ok(_),
          require_live=Some(() => access.poll_execution_original(start)),
        )
    }) {
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
    plan,
    entry,
    output_bridge: None,
    capture_times,
    publication_original: None,
    publication: None,
    identity_scan: None,
    publication_basis: None,
    publication_growing: false,
    publication_identity_issue: None,
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
  if self.publication_growing {
    return false
  }
  if !values_original_cleanup_entered(Some(self.access.base)) {
    return false
  }
  self.close_export()
  if self.identity_scan is Some(scan) {
    if !@execution_query.cancel_captured_source_cell_identity(scan) {
      return false
    }
    self.identity_scan = None
  }
  self.publication_original = None
  self.publication = None
  self.publication_basis = None
  self.publication_identity_issue = None
  self.execution.close() &&
  self.source.close() is Ok(true) &&
  self.entry.arena.finish_business_cleanup()
}
