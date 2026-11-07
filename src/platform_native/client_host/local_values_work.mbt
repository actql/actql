///|
/// Direct Local assembly of the existing Values tasks and original Run journal.
/// This holds their original cleanup responsibility; it introduces no Run,
/// scheduler, approval, Source, publication receipt or read grant of its own.
struct NativeClientValuesWork {
  start : NativeClientWorkFirstStart
  prepared : @host.PreparedClientProgram
  compiled : @host.ClientCompiledRun
  definition : @publication.PublicationContract
  normalization : @host.ClientLocalNormalization
  run : @strategy.CapturedDAG
  execution : @local.LocalValuesExecution
  mut requirements : @local.ClientLocalRequirements?
  current : () -> Bool
  original_access : NativeLocalValuesOriginalAccess?
  managed : @local.ClientInstalledManagedRun?
  mut publication_invocation : (
    @publication.RunEvidenceValue,
    @publication.PublicationContract,
  )?
  mut publication : @local.ClientProgramPublication?
}

///|
pub(all) enum NativeClientValuesWorkIssue {
  AuthorizationDenied
  UnsupportedProfile
  Configuration
  Journal(NativeClientRunJournalIssue)
  Start(NativeClientSourceWorkIssue)
  Normalization(@host.ClientLocalNormalizationIssue)
  Execution(@local.LocalValuesExecutionIssue)
  Export(@local.LocalValuesResultExportIssue)
  OriginalOperation(
    NativeClientValuesWorkIssue?,
    NativeLocalStoreOperationIssue
  )
}

///|
/// A failed occurrence keeps its original cleanup handle. Retrying this handle
/// neither renews authority nor repeats Compute or a physical start claim.
struct NativeClientValuesWorkFailure {
  issue : NativeClientValuesWorkIssue
  cleanup : () -> Bool
  mut cleaned : Bool
  mut original_access : NativeLocalValuesOriginalAccess?
  requires_execution_scope : Bool
}

///|
pub fn native_client_values_work_failure_issue(
  failure : NativeClientValuesWorkFailure,
) -> NativeClientValuesWorkIssue {
  failure.issue
}

///|
pub fn NativeClientValuesWorkFailure::close(
  self : NativeClientValuesWorkFailure,
) -> Bool {
  if !self.cleaned {
    if self.requires_execution_scope &&
      !values_original_cleanup_entered(self.original_access) {
      return false
    }
    self.cleaned = (self.cleanup)()
  }
  self.cleaned
}

///|
fn local_values_work_failure(
  issue : NativeClientValuesWorkIssue,
  cleanup? : () -> Bool = () => true,
  original_access? : NativeLocalValuesOriginalAccess? = None,
  requires_execution_scope? : Bool = false,
) -> NativeClientValuesWorkFailure {
  { issue, cleanup, cleaned: false, original_access, requires_execution_scope, }
}

///|
/// Inspect only the existing supported shape before accepting a new Run.
/// Physical start and current authority remain with the original work Owner.
pub fn native_client_local_values_profile_supported(
  prepared : @host.PreparedClientProgram,
) -> Bool {
  let graph = @host.prepared_client_graph(prepared)
  let task_count = @strategy.graph_task_count(graph)
  // Keep the existing Local host's bounded task inventory. This shape check
  // neither quotes its simultaneous holdings nor acquires their supplier.
  if @host.prepared_client_acquisition_count(prepared) != 0 ||
    @host.prepared_client_uses_graph_carrier(prepared) ||
    @strategy.graph_program_has_effects(graph) ||
    !@strategy.graph_source_free_inputs_complete(graph) ||
    task_count < 1 ||
    task_count > 32 {
    return false
  }
  for task in 0..<task_count {
    if @host.prepared_client_infer_execution_occurrence(prepared, task)
      is Some(_) {
      return false
    }
  }
  true
}

///|
fn stop_unstarted_values_setup(run : @strategy.CapturedDAG) -> Unit {
  @strategy.stop_captured_dag(run)
  let graph = @strategy.captured_dag_graph(run)
  for task in 0..<@strategy.graph_task_count(graph) {
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
}

///|
fn open_native_client_local_values_work(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  installed_contracts : @local.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  finalization_quantum : Int,
  max_finalization_rounds : Int,
  current : () -> Bool,
  ledger? : @resources.Ledger? = None,
  original_access? : NativeLocalValuesOriginalAccess? = None,
  requirements? : @local.ClientLocalRequirements? = None,
  managed? : @local.ClientInstalledManagedRun? = None,
) -> Result[NativeClientValuesWork, NativeClientValuesWorkFailure] {
  if !current() {
    return Err(
      local_values_work_failure(
        values_original_issue(original_access, AuthorizationDenied),
      ),
    )
  }
  if !native_client_local_values_profile_supported(prepared) ||
    finalization_quantum <= 0 ||
    max_finalization_rounds <= 0 {
    return Err(local_values_work_failure(UnsupportedProfile))
  }
  match
    journal.validate_prepared_run_binding(
      request, prepared, compiled, definition,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(local_values_work_failure(Journal(issue)))
  }
  // The existing acceptance transaction must already own this exact Run.
  // Unresolved history cannot be repaired by installing a supplied definition.
  let retained = match original_access {
    Some(access) => access.lookup()
    None => journal.lookup(request, current()).map_err(issue => Journal(issue))
  }
  match retained {
    Ok(Retained(record)) => {
      if @publication.publication_contract_identity(record.definition) !=
        @publication.publication_contract_identity(definition) {
        return Err(local_values_work_failure(Journal(ForeignRun)))
      }
      if record.physical_start_claimed ||
        record.cancellation_requested ||
        record.checkpoint is Some(_) {
        return Err(
          local_values_work_failure(Start(NeedsOriginalReconciliation)),
        )
      }
    }
    Ok(UnresolvedHistory) =>
      return Err(local_values_work_failure(Start(NeedsOriginalReconciliation)))
    Err(issue) => return Err(local_values_work_failure(issue))
  }
  let normalization = match
    @host.issue_prepared_client_local_normalization(prepared) {
    Ok(value) => value
    Err(issue) => return Err(local_values_work_failure(Normalization(issue)))
  }
  let requirements = match requirements {
    Some(original) => original
    None =>
      match
        @local.prepare_source_free_local_requirements(
          prepared, installed_contracts, values_body, fragment_body, ordered_body,
        ) {
        Some(original) => original
        None => return Err(local_values_work_failure(Configuration))
      }
  }
  // A supplied Ledger remains the existing Resource Owner. A refused setup
  // cannot fall back to the legacy constructor and silently obtain a new one.
  let selected = match managed {
    Some(original) => {
      guard ledger is Some(backing) else {
        return Err(local_values_work_failure(Configuration))
      }
      match
        @local.open_installed_managed_source_free_host(
          original,
          prepared,
          request,
          installed_contracts,
          values_body,
          fragment_body,
          ordered_body,
          false,
          backing=Some(backing),
        ) {
        Err(_) => return Err(local_values_work_failure(Configuration))
        Ok(value) => value
      }
    }
    None =>
      match ledger {
        Some(original) =>
          @local.open_source_free_local_retained_host_on_ledger(
            prepared,
            original,
            installed_contracts,
            values_body,
            fragment_body,
            ordered_body,
            requirements=Some(requirements),
          )
        None =>
          @local.open_source_free_local_retained_host(
            prepared,
            installed_contracts,
            values_body,
            1L,
            0L,
            0L,
            0L,
            fragment_body~,
            ordered_body~,
            requirements=Some(requirements),
          )
      }
  }
  guard selected is Some(setup) else {
    return Err(local_values_work_failure(Configuration))
  }
  let run = @driver.dispatch_driver_run(@builtin.configured_host_driver(setup))
  // Claim only the accepted immutable Run through its existing journal.
  if !current() {
    return Err(
      values_unstarted_failure(
        run,
        original_access,
        values_original_issue(original_access, AuthorizationDenied),
      ),
    )
  }
  let claimed = match original_access {
    Some(access) => access.claim()
    None =>
      claim_native_client_retained_work_first_start(journal, request, current).map_err(issue => {
          Start(issue)
        },
      )
  }
  let start = match claimed {
    Ok(value) => value
    Err(issue) =>
      return Err(values_unstarted_failure(run, original_access, issue))
  }
  let execution = match
    @local.execute_source_free_local_tasks_guarded(
      setup,
      finalization_quantum,
      max_finalization_rounds,
      () => {
        values_original_current(
          original_access, start, journal, request, current,
        )
        is Ok(_)
      },
      require_live=original_access.map(access => {
        () => access.poll_execution_original(start)
      }),
    ) {
    Ok(value) => value
    Err(failure) =>
      return Err(
        local_values_work_failure(
          values_original_issue(
            original_access,
            Execution(@local.local_values_execution_failure_issue(failure)),
          ),
          cleanup=() => {
            @local.retry_local_values_execution_failure_cleanup(failure)
          },
          original_access~,
          requires_execution_scope=original_access is Some(_),
        ),
      )
  }
  Ok({
    start,
    prepared,
    compiled,
    definition,
    normalization,
    run,
    execution,
    requirements: Some(requirements),
    current,
    original_access,
    managed,
    publication_invocation: None,
    publication: None,
  })
}

///|
/// Submit scope comes from the currently adopted Host/Account, not the Program
/// or a caller allow flag. A source-free Run needs no installed Source or Source
/// read permission. Result publication and delivery still have their own gates.
/// Trusted installed callers may supply their already-funded original Ledger;
/// this entry neither issues its backing nor transfers a preparation budget.
pub fn NativeLocalHostConnection::open_values_work(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  installed_contracts : @local.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  finalization_quantum : Int,
  max_finalization_rounds : Int,
  ledger? : @resources.Ledger? = None,
) -> Result[NativeClientValuesWork, NativeClientValuesWorkFailure] {
  let authority = match
    native_local_policy_authority(
      self,
      crypto,
      principal,
      connection,
      request,
      None,
    ) {
    Ok(value) => value
    Err(issue) => return Err(local_values_work_failure(Journal(issue)))
  }
  open_native_client_local_values_work(
    self.journal,
    request,
    prepared,
    compiled,
    definition,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    finalization_quantum,
    max_finalization_rounds,
    () => authority.current_for(self.journal, request),
    ledger~,
  )
}

///|
/// Publication borrows the original plan already consumed by this work's
/// configuration. Reading it does not re-prepare sequences or grant a Start.
/// It is immutable DATA; existing publication methods retain their separate
/// current/Account gates. Closing this work fences further plan borrowing.
pub fn NativeClientValuesWork::publication_limits(
  self : NativeClientValuesWork,
  max_payload_bytes : Int,
) -> (@execution.RetainedRowDecodeLimits, @host.PublicationOutputExportLimits)? {
  guard self.requirements is Some(original) else { return None }
  original.publication_limits(self.prepared, max_payload_bytes)
}

///|
pub fn NativeClientValuesWork::prepare_result_export(
  self : NativeClientValuesWork,
  result_index : Int,
  row_limits : @execution.RetainedRowDecodeLimits,
  max_entries : Int,
  max_name_bytes : Int,
  limits : @host.PublicationOutputExportLimits,
) -> Result[@local.LocalValuesResultExport, NativeClientValuesWorkIssue] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let output = match
    self.execution.prepare_result_export(
      result_index, row_limits, max_entries, max_name_bytes, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Export(issue))
  }
  match self.require_current() {
    Ok(_) => Ok(output)
    Err(issue) => {
      output.close()
      Err(issue)
    }
  }
}

///|
fn NativeClientValuesWork::require_current(
  self : NativeClientValuesWork,
) -> Result[Unit, NativeClientValuesWorkIssue] {
  match
    self.start.journal.validate_prepared_run_binding(
      self.start.request,
      self.prepared,
      self.compiled,
      self.definition,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  values_original_current(
    self.original_access,
    self.start,
    self.start.journal,
    self.start.request,
    self.current,
  )
}

///|
/// The original checked Owner supplies the audit. It is never inferred from
/// success, missing material or the absence of a Source installation.
pub fn NativeClientValuesWork::normalization_evidence(
  self : NativeClientValuesWork,
) -> Result[@publication.RunEvidenceValue, NativeClientValuesWorkIssue] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let evidence = match
    @host.prepared_client_local_normalization_evidence(
      self.prepared,
      self.normalization,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Normalization(issue))
  }
  self.require_current().map(_ => evidence)
}

///|
pub fn NativeClientValuesWork::usage(
  self : NativeClientValuesWork,
) -> @resources.LedgerUsage {
  @resources.ledger_usage(@strategy.captured_dag_ledger(self.run))
}

///|
/// No authority is required to finish the original temporary cleanup. False
/// preserves the same existing execution handle for retry, without rerunning it.
pub fn NativeClientValuesWork::close(self : NativeClientValuesWork) -> Bool {
  if !values_original_cleanup_entered(self.original_access) {
    return false
  }
  if !self.execution.close() {
    return false
  }
  self.requirements = None
  true
}

///|
/// Borrow the same Plan's bridge and evidence metadata limits separately from
/// Result row workspace. This issues no Start, Read or publication authority.
pub fn NativeClientValuesWork::publication_entry_limits(
  self : NativeClientValuesWork,
) -> (Int, Int)? {
  guard self.requirements is Some(original) else { return None }
  original.publication_entry_limits(self.prepared)
}
