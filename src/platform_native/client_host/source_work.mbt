///|
/// A Local connection to the existing Native acquisition/Compute owner. It
/// carries the original request guard; it is not a scheduler, Run lifecycle,
/// approval owner, or execution continuation. Configurations are Host-owned.
struct NativeClientSourceWork {
  journal : NativeClientRunJournal
  request : @host.ClientRequestIdentity
  owner : @resident.ResidentSourceCompute
  compiled : @host.ClientCompiledRun
  definition : @publication.PublicationContract
  capture_started_at : String
  capture_completed_at : String
  current_authorization : () -> Bool
  local_normalization : (
    @host.PreparedClientProgram,
    @host.ClientLocalNormalization,
  )?
}

///|
pub(all) enum NativeClientSourceWorkIssue {
  Configuration
  OriginalOperation(NativeClientValuesWorkIssue)
  RelationFile(@row_file.NativeRelationFileIssue)
  LocalExecution(@local.LocalValuesExecutionIssue)
  LocalExport(@local.LocalValuesResultExportIssue)
  CaptureIdentity(@execution_query.CapturedSourceIssue)
  AuthorizationDenied
  Normalization(@host.ClientLocalNormalizationIssue)
  NeedsOriginalReconciliation
  OriginalRunNotCurrent
  Journal(NativeClientRunJournalIssue)
  Work(@resident.ResidentSourceComputeIssue)
  Observation(@resident.ResidentSourcePublicationObservationIssue)
  Invocation(@publication.RunEvidenceValueIssue)
  Open(
    @resident.ResidentSourceComputeIssue,
    @remote_output.NativeRemoteStandardInputFailure
  )
}

///|
/// The standard Local CLI profile obtains its journal from the original
/// checked preparation before any start claim or Source I/O. Reuse the same
/// physical Source/Compute owner below; a completion outside this installed
/// profile is never permission to fabricate an empty audit.
pub fn open_native_client_local_source_work(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  configuration : @resident.ResidentSourceComputeConfiguration,
  occurrence : String,
  current_time : () -> String,
  current_authorization : () -> Bool,
  observe? : (@resident.ResidentSourceComputeEvent) -> Bool,
) -> Result[NativeClientSourceWork, NativeClientSourceWorkIssue] {
  if !current_authorization() {
    return Err(AuthorizationDenied)
  }
  match
    journal.validate_prepared_run_binding(
      request, prepared, compiled, definition,
    ) {
    Err(issue) => return Err(Journal(issue))
    Ok(_) => ()
  }
  let normalization = match
    @host.issue_prepared_client_local_normalization(prepared) {
    Ok(value) => value
    Err(issue) => return Err(Normalization(issue))
  }
  open_native_client_source_work(
    journal,
    request,
    prepared,
    compiled,
    definition,
    configuration,
    occurrence,
    current_time,
    current_authorization,
    observe?,
  ).map(work => {
    // This projection retains the same physical owner and original Run. No
    // acquisition, task, reservation or cleanup handle is duplicated.
    ..work,
    local_normalization: Some((prepared, normalization)),
  })
}

///|
fn claim_native_client_work_start(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  current_authorization : () -> Bool,
) -> Result[Unit, NativeClientSourceWorkIssue] {
  if !current_authorization() {
    return Err(AuthorizationDenied)
  }
  // bind_run checks exact intent, compiled owner and Run identity; replay may
  // retrieve the same binding but cannot select a replacement Run definition.
  match journal.bind_run(request, prepared, compiled, definition, true) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  claim_native_client_retained_work_start(
    journal, request, current_authorization,
  )
}

///|
/// The family-specific caller has checked and retained the original Run.
/// Acquisition and Effect computation share these exact reservation/start
/// facts; this helper never constructs a Run or a replacement continuation.
fn claim_native_client_retained_work_start(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  current_authorization : () -> Bool,
) -> Result[Unit, NativeClientSourceWorkIssue] {
  claim_native_client_retained_work_first_start(
    journal, request, current_authorization,
  ).map(_ => ())
}

///|
// Operational evidence retained only by the original Work. It is not a public
// body/CID, lease generation, resume claim or permission to send a request.
priv struct NativeClientWorkFirstStart {
  journal : NativeClientRunJournal
  request : @host.ClientRequestIdentity
  definition_cid : String
  observed_revision : Int64
}

///|
fn claim_native_client_retained_work_first_start(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  current_authorization : () -> Bool,
) -> Result[NativeClientWorkFirstStart, NativeClientSourceWorkIssue] {
  claim_native_client_retained_work_first_start_with_operations(
    journal, request, current_authorization,
  )
}

///|
fn claim_native_client_retained_work_first_start_with_operations(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  current_authorization : () -> Bool,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[NativeClientWorkFirstStart, NativeClientSourceWorkIssue] {
  let reads = operations.map(value => value.reads)
  // Recheck after callbacks and each durable boundary. A reservation alone
  // cannot authorize acquisition, and a false claim never opens another owner.
  if !current_authorization() {
    return Err(AuthorizationDenied)
  }
  match journal.reserve_dispatch_with_operations(request, true, operations~) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  if !current_authorization() {
    return Err(AuthorizationDenied)
  }
  match
    journal.claim_physical_start_with_operations(request, true, operations~) {
    Ok(true) => ()
    Ok(false) => return Err(NeedsOriginalReconciliation)
    Err(issue) => return Err(Journal(issue))
  }
  if !current_authorization() {
    return Err(AuthorizationDenied)
  }
  // A callback may observe or admit cancellation itself. Confirm the original
  // retained start/fence facts after that callback, before opening acquisition.
  match journal.lookup_with_reads(request, true, reads~) {
    Ok(Retained(record)) if record.physical_start_claimed &&
      !record.cancellation_requested &&
      record.checkpoint is None =>
      Ok({
        journal,
        request,
        definition_cid: @publication.publication_contract_identity(
          record.definition,
        ),
        observed_revision: record.revision,
      })
    Ok(_) => Err(NeedsOriginalReconciliation)
    Err(issue) => Err(Journal(issue))
  }
}

///|
// This observes the same original start responsibility; it never mints a
// replacement token from retained flags. A later Checkpoint owns continuation.
fn NativeClientWorkFirstStart::require_current(
  self : NativeClientWorkFirstStart,
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  current : () -> Bool,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[Unit, NativeClientSourceWorkIssue] {
  if !physical_equal(self.journal, journal) ||
    !(@host.client_request_identity_relation(self.request, request)
    is @host.SameRequest) {
    return Err(Journal(ForeignRun))
  }
  let record = match
    require_native_client_work_current_record(journal, request, current, reads~) {
    Ok(record) => record
    Err(issue) => return Err(issue)
  }
  if record.physical_start_claimed &&
    !record.cancellation_requested &&
    record.checkpoint is None &&
    record.revision >= self.observed_revision &&
    @publication.publication_contract_identity(record.definition) ==
    self.definition_cid {
    Ok(())
  } else {
    Err(NeedsOriginalReconciliation)
  }
}

///|
/// Start the original checked single-Source linear Program in this process.
/// This acquires/executes through existing Native owners, without a Coordinator
/// or transport dispatch. The caller must have adopted trusted configuration,
/// authenticated the original Submission and supplied current Run/Source
/// authority. Configuration must be the original selected mapping retained
/// with that Run, not a replacement from current Host settings; this physical
/// connection does not itself persist installation context. No path or grant
/// is extracted from the Program. Once a physical
/// claim exists, reopening this constructor is forbidden, including after an
/// acquisition failure or lost reply; the original work must be reconciled.
pub fn open_native_client_source_work(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  configuration : @resident.ResidentSourceComputeConfiguration,
  occurrence : String,
  current_time : () -> String,
  current_authorization : () -> Bool,
  observe? : (@resident.ResidentSourceComputeEvent) -> Bool,
) -> Result[NativeClientSourceWork, NativeClientSourceWorkIssue] {
  if !current_authorization() {
    return Err(AuthorizationDenied)
  }
  if !@resident.resident_source_compute_shape_supported(prepared) {
    return Err(Work(@resident.UnsupportedGraph))
  }
  // Sample before the final authority/claim guard: this callback cannot move
  // cancellation between that guard and physical acquisition.
  let capture_started_at = current_time()
  match
    claim_native_client_work_start(
      journal, request, prepared, compiled, definition, current_authorization,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let guarded_observe = native_client_work_observer(
    journal, request, current_authorization, observe,
  )
  match
    @resident.open_resident_source_compute(
      prepared,
      configuration,
      occurrence,
      observe=guarded_observe,
    ) {
    Ok(owner) =>
      Ok({
        journal,
        request,
        owner,
        compiled,
        definition,
        capture_started_at,
        capture_completed_at: current_time(),
        current_authorization,
        local_normalization: None,
      })
    Err((issue, cleanup)) => Err(Open(issue, cleanup))
  }
}

///|
fn native_client_work_observer(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  current_authorization : () -> Bool,
  observe : ((@resident.ResidentSourceComputeEvent) -> Bool)?,
) -> (@resident.ResidentSourceComputeEvent) -> Bool {
  event => {
    if observe is Some(record) && !record(event) {
      false
    } else {
      match event {
        @resident.CleanupPending | @resident.CleanupCompleted => true
        _ =>
          current_authorization() &&
          journal.lookup(request, true) is Ok(Retained(record)) &&
          record.physical_start_claimed &&
          !record.cancellation_requested
      }
    }
  }
}

///|
/// Bind the actual Source observation to the original compiled Run. Repeated
/// calls retain the acquisition interval; they do not refresh its lifetime or
/// reopen the Source. Every call rechecks current authority and cancellation.
pub fn NativeClientSourceWork::publication_invocation(
  self : NativeClientSourceWork,
  limits : @host.PublicationOutputExportLimits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (
    @publication.RunEvidenceValue,
    @publication.RunEvidenceValue,
    @publication.RunEvidenceValue,
    @publication.PublicationContract,
  ),
  NativeClientSourceWorkIssue,
] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let authority = @host.client_request_authority_scope_cid(self.request)
  let observation = match
    self.owner.source_publication_observation(
      authority,
      self.capture_completed_at,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  let (evidence, logical, source_ref, source_contract, policy) = @resident.resident_source_publication_observation_values(
    observation,
  )
  let (observations, invocation) = match
    @host.issue_client_compiled_task_invocation(
      self.compiled,
      self.definition,
      @publication.run_evidence_value_json(evidence),
      @publication.run_evidence_value_json(logical),
      source_ref,
      source_contract,
      authority,
      policy,
      self.capture_started_at,
      self.capture_completed_at,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  match self.require_current() {
    Ok(_) => Ok((evidence, logical, observations, invocation))
    Err(issue) => Err(issue)
  }
}

///|
fn NativeClientSourceWork::require_current(
  self : NativeClientSourceWork,
) -> Result[Unit, NativeClientSourceWorkIssue] {
  require_native_client_work_current(
    self.journal,
    self.request,
    self.current_authorization,
  )
}

///|
fn require_native_client_work_current(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  current_authorization : () -> Bool,
) -> Result[Unit, NativeClientSourceWorkIssue] {
  require_native_client_work_current_record(
    journal, request, current_authorization,
  ).map(_ => ())
}

///|
// One synchronous predicate uses the record returned by its own authenticated
// lookup. That lookup keeps its full custody/transaction protocol, including
// the existing owned-publication-fence join. No callback or physical operation separates
// this record from the caller's final original-start checks; nothing is cached
// across predicates or exposed as an execution permission.
fn require_native_client_work_current_record(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  current_authorization : () -> Bool,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[NativeClientRunRecord, NativeClientSourceWorkIssue] {
  if !current_authorization() {
    return Err(AuthorizationDenied)
  }
  match journal.lookup_with_reads(request, true, reads~) {
    Ok(Retained(record)) if record.physical_start_claimed &&
      !record.cancellation_requested => Ok(record)
    Ok(_) => Err(NeedsOriginalReconciliation)
    Err(issue) => Err(Journal(issue))
  }
}

///|
/// Task readiness, input correspondence, capacity and completion remain with
/// the existing strategy owner. This guard does not infer a lifecycle state.
pub fn NativeClientSourceWork::execute_task(
  self : NativeClientSourceWork,
  task : Int,
) -> Result[Unit, NativeClientSourceWorkIssue] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.owner.execute_task(task).map(_ => ()).map_err(issue => Work(issue))
}

///|
/// Obtain the checked Named Result export, not a publication receipt or a read
/// grant. The CLI still commits through the existing Native publication Store
/// and authorizes each delivery through the existing Result access service.
pub fn NativeClientSourceWork::prepare_result_export(
  self : NativeClientSourceWork,
  limits : @host.PublicationOutputExportLimits,
) -> Result[@host.PublicationOutputExport, NativeClientSourceWorkIssue] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.owner.prepare_result_export(limits).map_err(issue => Work(issue))
}

///|
pub fn NativeClientSourceWork::usage(
  self : NativeClientSourceWork,
) -> @resources.LedgerUsage {
  self.owner.usage()
}

///|
/// Cleanup may proceed after authorization loss. The same acquisition/
/// Compute owner retains failed-close responsibility and reservations. Closing
/// this physical work is neither accepting a cancellation nor proving a Run
/// terminal; a false result requires retry on this exact owner.
pub fn NativeClientSourceWork::close(self : NativeClientSourceWork) -> Bool {
  self.owner.close()
}
