///|
/// The existing retained Local dispatcher and journal FirstStart on the same
/// admitted Effect Run. No Source/Resident scope, Run, Ledger, approval or
/// execution authority is constructed here. The supplied Run's original
/// physical funding/custody remains with its caller.
struct NativeClientEffectValuesWork {
  start : NativeClientWorkFirstStart
  materials : @host.ClientEffectRunMaterials
  captured : @strategy.CapturedEffectRunDAG
  execution : @local.LocalValuesExecution
  current_time : () -> String
  current : () -> Bool
  mut closed : Bool
}

///|
pub(all) enum NativeClientEffectValuesWorkIssue {
  AuthorizationDenied
  ForeignMaterials
  Configuration
  OriginalRunNotCurrent
  Unavailable
  Journal(NativeClientRunJournalIssue)
  Start(NativeClientSourceWorkIssue)
  Normalization(@host.ClientEffectNormalizationIssue)
  Execution(@local.LocalValuesExecutionIssue)
}

///|
/// Retry cleanup only; a claimed or unknown original is never executed again.
/// This closes only work acquired here, not the caller's original funding.
struct NativeClientEffectValuesWorkFailure {
  issue : NativeClientEffectValuesWorkIssue
  cleanup : () -> Bool
  mut cleaned : Bool
}

///|
pub fn native_client_effect_values_work_failure_issue(
  failure : NativeClientEffectValuesWorkFailure,
) -> NativeClientEffectValuesWorkIssue {
  failure.issue
}

///|
pub fn NativeClientEffectValuesWorkFailure::close(
  self : NativeClientEffectValuesWorkFailure,
) -> Bool {
  if !self.cleaned {
    self.cleaned = (self.cleanup)()
  }
  self.cleaned
}

///|
fn effect_values_work_failure(
  issue : NativeClientEffectValuesWorkIssue,
  cleanup? : () -> Bool = () => true,
) -> NativeClientEffectValuesWorkFailure {
  { issue, cleanup, cleaned: false, }
}

///|
fn open_native_client_effect_values_work(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  materials : @host.ClientEffectRunMaterials,
  bound : @host.PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  installed_contracts : @local.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  finalization_quantum : Int,
  max_finalization_rounds : Int,
  current_time : () -> String,
  current : () -> Bool,
) -> Result[NativeClientEffectValuesWork, NativeClientEffectValuesWorkFailure] {
  if !current() {
    return Err(effect_values_work_failure(AuthorizationDenied))
  }
  if materials.request != Some(request) {
    return Err(effect_values_work_failure(ForeignMaterials))
  }
  let normalization = @host.restore_client_effect_run_normalization(materials)
  if normalization is Err(issue) {
    return Err(effect_values_work_failure(Normalization(issue)))
  }
  // The first opaque Run binding is a nominal original. Rebinding the same
  // bytes makes a different Owner and cannot replace the captured binding.
  let owner = @strategy.checked_effect_run_owner(
    @host.prepared_client_effect_run_graph(bound),
  )
  if !physical_equal(
      @host.prepared_client_effect_run_computation(bound),
      materials.prepared,
    ) ||
    !physical_equal(owner, @strategy.captured_effect_run_owner(captured)) ||
    !physical_equal(
      @effect_binding.effect_program_run_admission(owner),
      @host.client_effect_allowed_run_admission(materials.allowed),
    ) ||
    @publication.publication_contract_json(
      @effect_binding.effect_program_run_definition(owner),
    ) !=
    @publication.publication_contract_json(materials.run_definition) {
    return Err(effect_values_work_failure(ForeignMaterials))
  }
  if finalization_quantum <= 0 || max_finalization_rounds <= 0 {
    return Err(effect_values_work_failure(Execution(InvalidLimits)))
  }
  if @host.prepared_client_effect_request_scope(materials.prepared, request)
    is Err(_) {
    return Err(effect_values_work_failure(Journal(ChangedIntent)))
  }
  // Retained acceptance precedes configuration. Missing, cancelled, claimed or
  // Checkpoint-owned work cannot be repaired or restarted by this constructor.
  match journal.lookup(request, true) {
    Ok(Retained(record)) => {
      if @publication.publication_contract_identity(record.definition) !=
        @publication.publication_contract_identity(materials.run_definition) {
        return Err(effect_values_work_failure(Journal(ForeignRun)))
      }
      if record.physical_start_claimed ||
        record.cancellation_requested ||
        record.checkpoint is Some(_) {
        return Err(
          effect_values_work_failure(Start(NeedsOriginalReconciliation)),
        )
      }
    }
    Ok(UnresolvedHistory) =>
      return Err(effect_values_work_failure(Start(NeedsOriginalReconciliation)))
    Err(issue) => return Err(effect_values_work_failure(Journal(issue)))
  }
  let now = current_time()
  if !current() {
    return Err(effect_values_work_failure(AuthorizationDenied))
  }
  if !@host.client_effect_run_start_current(
      materials.allowed,
      materials.run_definition,
      now,
    ) {
    return Err(effect_values_work_failure(OriginalRunNotCurrent))
  }
  guard @local.configure_source_free_effect_local_retained_host(
      bound, captured, installed_contracts, values_body, fragment_body, ordered_body,
    )
    is Some(setup) else {
    return Err(effect_values_work_failure(Configuration))
  }
  let run = @strategy.captured_effect_run_dag(captured)
  let start = match
    claim_native_client_retained_work_first_start(journal, request, current) {
    Ok(value) => value
    Err(issue) => {
      stop_unstarted_values_setup(run)
      return Err(effect_values_work_failure(Start(issue)))
    }
  }
  let execution = match
    @local.execute_source_free_values_guarded(
      setup,
      finalization_quantum,
      max_finalization_rounds,
      () => {
        let observed_at = current_time()
        @host.client_effect_run_start_current(
          materials.allowed,
          materials.run_definition,
          observed_at,
        ) &&
        start.require_current(journal, request, current) is Ok(_)
      },
    ) {
    Ok(value) => value
    Err(failure) =>
      return Err(
        effect_values_work_failure(
          Execution(@local.local_values_execution_failure_issue(failure)),
          cleanup=() => {
            @local.retry_local_values_execution_failure_cleanup(failure)
          },
        ),
      )
  }
  let work : NativeClientEffectValuesWork = {
    start,
    materials,
    captured,
    execution,
    current_time,
    current,
    closed: false,
  }
  match work.require_current() {
    Ok(_) => Ok(work)
    Err(issue) =>
      Err(effect_values_work_failure(issue, cleanup=() => work.close()))
  }
}

///|
/// Current Submit belongs to the adopted Host/Account, not to a caller Bool,
/// prior Allow or Provider key. No Source read permission is borrowed. The
/// original opaque Run and physical funding must already exist; this entry
/// neither obtains replacement backing nor installs a normal numeric profile.
pub fn NativeLocalHostConnection::open_effect_values_work(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  materials : @host.ClientEffectRunMaterials,
  bound : @host.PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  installed_contracts : @local.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  finalization_quantum : Int,
  max_finalization_rounds : Int,
  current_time : () -> String,
) -> Result[NativeClientEffectValuesWork, NativeClientEffectValuesWorkFailure] {
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
    Err(issue) => return Err(effect_values_work_failure(Journal(issue)))
  }
  open_native_client_effect_values_work(
    self.journal,
    request,
    materials,
    bound,
    captured,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    finalization_quantum,
    max_finalization_rounds,
    current_time,
    () => authority.current_for(self.journal, request),
  )
}

///|
fn NativeClientEffectValuesWork::require_current(
  self : NativeClientEffectValuesWork,
) -> Result[Unit, NativeClientEffectValuesWorkIssue] {
  if self.closed {
    return Err(Unavailable)
  }
  if !(self.current)() {
    return Err(AuthorizationDenied)
  }
  let now = (self.current_time)()
  // Clock callbacks cannot bypass the original current/claim/cancellation fence.
  match
    self.start.require_current(
      self.start.journal,
      self.start.request,
      self.current,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Start(issue))
  }
  if !@host.client_effect_run_start_current(
      self.materials.allowed,
      self.materials.run_definition,
      now,
    ) {
    return Err(OriginalRunNotCurrent)
  }
  if self.closed || self.execution.material() is None {
    return Err(Unavailable)
  }
  Ok(())
}

///|
/// Borrow only this original Run for existing pin/Invocation/Preview Owners.
/// This is not evidence disclosure, durable Checkpoint, approval or a permit;
/// those boundaries must independently check current RunRead and their custody.
pub fn NativeClientEffectValuesWork::run_for_capture(
  self : NativeClientEffectValuesWork,
) -> Result[@strategy.CapturedEffectRunDAG, NativeClientEffectValuesWorkIssue] {
  self.require_current().map(_ => self.captured)
}

///|
pub fn NativeClientEffectValuesWork::usage(
  self : NativeClientEffectValuesWork,
) -> @resources.LedgerUsage {
  @resources.ledger_usage(
    @strategy.captured_dag_ledger(
      @strategy.captured_effect_run_dag(self.captured),
    ),
  )
}

///|
/// Cleanup requires no renewed authority and never reclaims or reruns Compute.
pub fn NativeClientEffectValuesWork::close(
  self : NativeClientEffectValuesWork,
) -> Bool {
  self.closed = true
  self.execution.close()
}
