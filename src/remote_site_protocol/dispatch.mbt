///|
/// Identity-bearing request admitted before a remote Site may start work.
/// Transport nonces and future execution results are deliberately absent.
struct DispatchRequest {
  coordinator_authority : String
  run_definition_cid : String
  task_key : String
  task_attempt : Int
  dispatch_id : String
  dispatch_request_cid : String
  site_key : String
  site_generation : Int
  runtime_bundle_cid : String
  connector_registration : String
  connector_revision : String
  strategy_revision : String
  input_binding_cid : String
  obligations_cid : String
  budget_cid : String
  grant_cid : String
}

///|
/// Physical execution observations and common completion are different facts.
pub(all) enum RemoteExecutionState {
  Accepted
  Provisioning
  Running
  NativeSettled
  ExecutionFailed
  ExecutionCancelled
  ExecutionUnknown
} derive(Eq, Debug)

///|
/// Evidence progression is independent from physical execution progression.
pub(all) enum RemoteEvidenceState {
  NoEvidence
  OutputRetained(String, String)
  EvidenceDurable(String, String, String)
  EvidenceRejected
} derive(Eq, Debug)

///|
/// Holdings and cleanup remain independent from execution and evidence.
pub(all) enum RemoteCleanupState {
  CleanupActive
  CleanupReleasing
  CleanupReleased
  CleanupUnknown
  CleanupForceLost
  CleanupRecoveredAfterLoss
} derive(Eq, Debug)

///|
pub(all) enum DispatchAcceptance {
  NewDispatch
  ExistingDispatch
} derive(Eq, Debug)

///|
pub(all) enum DispatchIssue {
  InvalidJournal
  InvalidDispatch
  ForeignSite
  StaleSiteGeneration
  DispatchCollision
  AttemptAlreadyDispatched
  InvalidTransition
  MaterialUnavailable
  UnauthorizedForceLoss
  DispatchIdentityMismatch
  DurabilityUnconfirmed
} derive(Eq, Debug)

///|
/// A journal record keeps historical facts while current availability changes.
struct DispatchRecord {
  request : DispatchRequest
  mut execution : RemoteExecutionState
  mut evidence : RemoteEvidenceState
  mut cleanup : RemoteCleanupState
  mut material_available : Bool
  mut quarantined_capacity : Bool
}

///|
/// Prepared admission contains no authority to start physical work. A journal
/// adapter must durably install or reconcile the exact request before commit.
struct DispatchAdmission {
  journal : SiteDispatchJournal
  request : DispatchRequest
  acceptance : DispatchAcceptance
  mut consumed : Bool
}

///|
/// The portable journal owns application transitions, not database mechanics.
struct SiteDispatchJournal {
  mut site : @site.ExecutionSite
  protocol_version : String
  dispatches : Map[String, DispatchRecord]
  attempts : Map[String, String]
}

///|
fn nonempty(value : String) -> Bool {
  !value.is_empty()
}

///|
fn valid_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < 71; index = index + 1 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn keyed(value : String) -> String {
  value.length().to_string() + ":" + value
}

///|
fn dispatch_key(request : DispatchRequest) -> String {
  keyed(request.coordinator_authority) +
  keyed(request.site_key) +
  request.site_generation.to_string() +
  ":" +
  keyed(request.dispatch_id)
}

///|
fn attempt_key(request : DispatchRequest) -> String {
  keyed(request.coordinator_authority) +
  keyed(request.run_definition_cid) +
  keyed(request.task_key) +
  request.task_attempt.to_string()
}

///|
fn valid_request_fields(request : DispatchRequest) -> Bool {
  nonempty(request.coordinator_authority) &&
  valid_cid(request.run_definition_cid) &&
  nonempty(request.task_key) &&
  request.task_attempt > 0 &&
  nonempty(request.dispatch_id) &&
  nonempty(request.site_key) &&
  request.site_generation >= 0 &&
  valid_cid(request.runtime_bundle_cid) &&
  nonempty(request.connector_registration) &&
  nonempty(request.connector_revision) &&
  nonempty(request.strategy_revision) &&
  valid_cid(request.input_binding_cid) &&
  valid_cid(request.obligations_cid) &&
  valid_cid(request.budget_cid) &&
  valid_cid(request.grant_cid)
}

///|
fn valid_request(request : DispatchRequest) -> Bool {
  if !valid_request_fields(request) || !valid_cid(request.dispatch_request_cid) {
    return false
  }
  match request_identity(request) {
    Ok(identity) => identity == request.dispatch_request_cid
    Err(_) => false
  }
}

///|
fn emit_dispatch_request_body(
  request : DispatchRequest,
) -> Result[String, DispatchIssue] {
  let writer = @encode.writer(65536, 32, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "budget_cid")
    @encode.string_value(writer, request.budget_cid)
    @encode.key(writer, "connector_registration")
    @encode.string_value(writer, request.connector_registration)
    @encode.key(writer, "connector_revision")
    @encode.string_value(writer, request.connector_revision)
    @encode.key(writer, "coordinator_authority")
    @encode.string_value(writer, request.coordinator_authority)
    @encode.key(writer, "dispatch_id")
    @encode.string_value(writer, request.dispatch_id)
    @encode.key(writer, "grant_cid")
    @encode.string_value(writer, request.grant_cid)
    @encode.key(writer, "input_binding_cid")
    @encode.string_value(writer, request.input_binding_cid)
    @encode.key(writer, "obligations_cid")
    @encode.string_value(writer, request.obligations_cid)
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(writer, request.run_definition_cid)
    @encode.key(writer, "runtime_bundle_cid")
    @encode.string_value(writer, request.runtime_bundle_cid)
    @encode.key(writer, "site_generation")
    @encode.number_value(writer, request.site_generation.to_double())
    @encode.key(writer, "site_key")
    @encode.string_value(writer, request.site_key)
    @encode.key(writer, "strategy_revision")
    @encode.string_value(writer, request.strategy_revision)
    @encode.key(writer, "task_attempt")
    @encode.number_value(writer, request.task_attempt.to_double())
    @encode.key(writer, "task_key")
    @encode.string_value(writer, request.task_key)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-dispatch-request/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  let body = @encode.finish(writer) catch { _ => return Err(InvalidDispatch) }
  Ok(body)
}

///|
fn request_identity(request : DispatchRequest) -> Result[String, DispatchIssue] {
  let body = match emit_dispatch_request_body(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @sha.text_hex(body) {
    Ok(value) => Ok("sha256:" + value)
    Err(_) => Err(InvalidDispatch)
  }
}

///|
pub fn dispatch_request_json(
  request : DispatchRequest,
) -> Result[String, DispatchIssue] {
  if !valid_request(request) {
    return Err(InvalidDispatch)
  }
  emit_dispatch_request_body(request)
}

///|
pub fn prepare_dispatch_request(
  coordinator_authority : String,
  run_definition_cid : String,
  task_key : String,
  task_attempt : Int,
  dispatch_id : String,
  site_key : String,
  site_generation : Int,
  runtime_bundle_cid : String,
  connector_registration : String,
  connector_revision : String,
  strategy_revision : String,
  input_binding_cid : String,
  obligations_cid : String,
  budget_cid : String,
  grant_cid : String,
) -> Result[DispatchRequest, DispatchIssue] {
  let pending : DispatchRequest = {
    coordinator_authority,
    run_definition_cid,
    task_key,
    task_attempt,
    dispatch_id,
    dispatch_request_cid: "pending",
    site_key,
    site_generation,
    runtime_bundle_cid,
    connector_registration,
    connector_revision,
    strategy_revision,
    input_binding_cid,
    obligations_cid,
    budget_cid,
    grant_cid,
  }
  if !valid_request_fields(pending) {
    return Err(InvalidDispatch)
  }
  let identity = match request_identity(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..pending, dispatch_request_cid: identity, })
}

///|
/// Admit decoded transport fields by recomputing their application identity.
pub fn admit_dispatch_request(
  coordinator_authority : String,
  run_definition_cid : String,
  task_key : String,
  task_attempt : Int,
  dispatch_id : String,
  claimed_request_cid : String,
  site_key : String,
  site_generation : Int,
  runtime_bundle_cid : String,
  connector_registration : String,
  connector_revision : String,
  strategy_revision : String,
  input_binding_cid : String,
  obligations_cid : String,
  budget_cid : String,
  grant_cid : String,
) -> Result[DispatchRequest, DispatchIssue] {
  let request = match
    prepare_dispatch_request(
      coordinator_authority, run_definition_cid, task_key, task_attempt, dispatch_id,
      site_key, site_generation, runtime_bundle_cid, connector_registration, connector_revision,
      strategy_revision, input_binding_cid, obligations_cid, budget_cid, grant_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if request.dispatch_request_cid != claimed_request_cid {
    Err(DispatchIdentityMismatch)
  } else {
    Ok(request)
  }
}

///|
pub fn create_site_dispatch_journal(
  site : @site.ExecutionSite,
  protocol_version : String,
) -> Result[SiteDispatchJournal, DispatchIssue] {
  if !valid_cid(@site.site_runtime_revision(site)) ||
    protocol_version != "actql-remote-site/0.1" {
    return Err(InvalidJournal)
  }
  Ok({ site, protocol_version, dispatches: Map([]), attempts: Map([]), })
}

///|
/// Prepare an exact admission without mutating the in-memory journal. The
/// returned request body is the durable CAS input for a journal adapter.
pub fn prepare_dispatch_acceptance(
  journal : SiteDispatchJournal,
  request : DispatchRequest,
) -> Result[DispatchAdmission, DispatchIssue] {
  if !valid_request(request) {
    return Err(InvalidDispatch)
  }
  if request.site_key != @site.site_key(journal.site) {
    return Err(ForeignSite)
  }
  if !@site.site_binding_current(
      journal.site,
      request.site_generation,
      request.runtime_bundle_cid,
    ) {
    return Err(StaleSiteGeneration)
  }
  let key = dispatch_key(request)
  match journal.dispatches.get(key) {
    Some(record) =>
      if record.request.dispatch_request_cid == request.dispatch_request_cid {
        Ok({ journal, request, acceptance: ExistingDispatch, consumed: false, })
      } else {
        Err(DispatchCollision)
      }
    None => {
      let occurrence = attempt_key(request)
      if journal.attempts.contains(occurrence) {
        return Err(AttemptAlreadyDispatched)
      }
      Ok({ journal, request, acceptance: NewDispatch, consumed: false, })
    }
  }
}

///|
/// Commit admission only after the adapter confirms the accepted request is
/// durable. The recheck prevents two prepared admissions from creating two
/// physical executions for one task attempt.
pub fn commit_dispatch_acceptance(
  admission : DispatchAdmission,
  durable : Bool,
) -> Result[(DispatchAcceptance, DispatchRecord), DispatchIssue] {
  if admission.consumed {
    return Err(InvalidTransition)
  }
  if !durable {
    return Err(DurabilityUnconfirmed)
  }
  let journal = admission.journal
  let request = admission.request
  let key = dispatch_key(request)
  match journal.dispatches.get(key) {
    Some(record) => {
      if record.request.dispatch_request_cid != request.dispatch_request_cid {
        return Err(DispatchCollision)
      }
      admission.consumed = true
      Ok((ExistingDispatch, record))
    }
    None => {
      if admission.acceptance == ExistingDispatch {
        return Err(InvalidTransition)
      }
      let occurrence = attempt_key(request)
      if journal.attempts.contains(occurrence) {
        return Err(AttemptAlreadyDispatched)
      }
      let record = {
        request,
        execution: Accepted,
        evidence: NoEvidence,
        cleanup: CleanupActive,
        material_available: false,
        quarantined_capacity: false,
      }
      journal.dispatches[key] = record
      journal.attempts[occurrence] = key
      admission.consumed = true
      Ok((NewDispatch, record))
    }
  }
}

///|
pub fn dispatch_admission_kind(
  admission : DispatchAdmission,
) -> DispatchAcceptance {
  admission.acceptance
}

///|
pub fn dispatch_admission_request_json(
  admission : DispatchAdmission,
) -> Result[String, DispatchIssue] {
  dispatch_request_json(admission.request)
}

///|
pub fn begin_provisioning(
  record : DispatchRecord,
) -> Result[Unit, DispatchIssue] {
  match record.execution {
    Accepted => {
      record.execution = Provisioning
      Ok(())
    }
    _ => Err(InvalidTransition)
  }
}

///|
pub fn begin_remote_execution(
  record : DispatchRecord,
) -> Result[Unit, DispatchIssue] {
  match record.execution {
    Provisioning => {
      record.execution = Running
      Ok(())
    }
    _ => Err(InvalidTransition)
  }
}

///|
pub fn confirm_native_settled(
  record : DispatchRecord,
) -> Result[Unit, DispatchIssue] {
  match record.execution {
    Running => {
      record.execution = NativeSettled
      Ok(())
    }
    _ => Err(InvalidTransition)
  }
}

///|
pub fn confirm_execution_failed(
  record : DispatchRecord,
) -> Result[Unit, DispatchIssue] {
  match record.execution {
    Provisioning | Running => {
      record.execution = ExecutionFailed
      Ok(())
    }
    ExecutionFailed => Ok(())
    _ => Err(InvalidTransition)
  }
}

///|
pub fn confirm_execution_cancelled(
  record : DispatchRecord,
) -> Result[Unit, DispatchIssue] {
  match record.execution {
    Accepted | Provisioning | Running => {
      record.execution = ExecutionCancelled
      Ok(())
    }
    ExecutionCancelled => Ok(())
    _ => Err(InvalidTransition)
  }
}

///|
pub fn retain_remote_output(
  record : DispatchRecord,
  material_generation : String,
  holding_evidence_cid : String,
) -> Result[Unit, DispatchIssue] {
  if material_generation.is_empty() || !valid_cid(holding_evidence_cid) {
    return Err(InvalidDispatch)
  }
  match (record.execution, record.evidence, record.cleanup) {
    (NativeSettled, NoEvidence, CleanupActive) => {
      record.evidence = OutputRetained(
        material_generation, holding_evidence_cid,
      )
      record.material_available = true
      Ok(())
    }
    _ => Err(InvalidTransition)
  }
}

///|
pub fn record_durable_execution_evidence(
  record : DispatchRecord,
  evidence_cid : String,
) -> Result[Unit, DispatchIssue] {
  if !valid_cid(evidence_cid) {
    return Err(InvalidDispatch)
  }
  match record.evidence {
    OutputRetained(material_generation, holding_evidence_cid) => {
      if !record.material_available {
        return Err(MaterialUnavailable)
      }
      record.evidence = EvidenceDurable(
        material_generation, holding_evidence_cid, evidence_cid,
      )
      Ok(())
    }
    EvidenceDurable(_, _, prior) if prior == evidence_cid => Ok(())
    _ => Err(InvalidTransition)
  }
}

///|
pub fn reject_execution_evidence(
  record : DispatchRecord,
) -> Result[Unit, DispatchIssue] {
  match record.evidence {
    NoEvidence | OutputRetained(_, _) => {
      record.evidence = EvidenceRejected
      record.material_available = false
      Ok(())
    }
    EvidenceRejected => Ok(())
    EvidenceDurable(_, _, _) => Err(InvalidTransition)
  }
}

///|
pub fn mark_execution_unknown(record : DispatchRecord) -> Unit {
  match record.execution {
    Accepted | Provisioning | Running => record.execution = ExecutionUnknown
    _ => ()
  }
  if record.cleanup != CleanupReleased &&
    record.cleanup != CleanupRecoveredAfterLoss {
    record.cleanup = CleanupUnknown
  }
}

///|
pub fn begin_remote_release(
  record : DispatchRecord,
) -> Result[Unit, DispatchIssue] {
  match record.cleanup {
    CleanupActive | CleanupUnknown => {
      record.cleanup = CleanupReleasing
      Ok(())
    }
    _ => Err(InvalidTransition)
  }
}

///|
pub fn confirm_remote_release(
  record : DispatchRecord,
) -> Result[Unit, DispatchIssue] {
  match record.cleanup {
    CleanupReleasing => {
      record.cleanup = CleanupReleased
      record.material_available = false
      Ok(())
    }
    _ => Err(InvalidTransition)
  }
}

///|
/// Force loss terminates management without claiming physical reclamation.
pub fn force_loss(
  journal : SiteDispatchJournal,
  record : DispatchRecord,
  authorized : Bool,
) -> Result[Unit, DispatchIssue] {
  if !authorized {
    return Err(UnauthorizedForceLoss)
  }
  if record.request.site_key != @site.site_key(journal.site) {
    return Err(ForeignSite)
  }
  @site.revoke_site(journal.site)
  record.execution = ExecutionUnknown
  record.cleanup = CleanupForceLost
  record.material_available = false
  record.quarantined_capacity = true
  Ok(())
}

///|
/// Late exact cleanup evidence may discharge quarantined physical capacity. It
/// never restores execution success, material availability, or completion.
pub fn reconcile_cleanup_after_loss(
  record : DispatchRecord,
) -> Result[Unit, DispatchIssue] {
  match record.cleanup {
    CleanupForceLost => {
      record.cleanup = CleanupRecoveredAfterLoss
      record.quarantined_capacity = false
      Ok(())
    }
    _ => Err(InvalidTransition)
  }
}

///|
/// Starting a new Agent generation invalidates old execution authority. Old
/// terminal facts remain queryable, while current material availability must
/// be established again through a separate physical check.
pub fn restart_site_generation(
  journal : SiteDispatchJournal,
  replacement : @site.ExecutionSite,
) -> Result[Int, DispatchIssue] {
  if @site.site_key(replacement) != @site.site_key(journal.site) ||
    @site.site_generation(replacement) <= @site.site_generation(journal.site) ||
    !valid_cid(@site.site_runtime_revision(replacement)) {
    return Err(InvalidJournal)
  }
  let mut affected = 0
  journal.dispatches.each((_, record) => {
    if record.cleanup != CleanupReleased &&
      record.cleanup != CleanupRecoveredAfterLoss {
      match record.execution {
        Accepted | Provisioning | Running => record.execution = ExecutionUnknown
        _ => ()
      }
      record.cleanup = CleanupUnknown
      record.material_available = false
      affected += 1
    }
  })
  journal.site = replacement
  Ok(affected)
}

///|
pub fn stop_site_admission(journal : SiteDispatchJournal) -> Unit {
  @site.begin_site_teardown(journal.site)
}

///|
pub fn remote_completion_evidence_available(record : DispatchRecord) -> Bool {
  record.execution == NativeSettled &&
  record.material_available &&
  record.evidence is EvidenceDurable(_, _, _) &&
  record.cleanup != CleanupForceLost &&
  record.cleanup != CleanupRecoveredAfterLoss &&
  record.cleanup != CleanupReleased
}

///|
pub fn dispatch_record_state(
  record : DispatchRecord,
) -> (RemoteExecutionState, RemoteEvidenceState, RemoteCleanupState, Bool, Bool) {
  (
    record.execution,
    record.evidence,
    record.cleanup,
    record.material_available,
    record.quarantined_capacity,
  )
}

///|
pub fn site_dispatch_generation(journal : SiteDispatchJournal) -> Int {
  @site.site_generation(journal.site)
}

///|
pub fn site_dispatch_protocol_version(journal : SiteDispatchJournal) -> String {
  journal.protocol_version
}

///|
pub fn dispatch_request_identity(request : DispatchRequest) -> String {
  request.dispatch_request_cid
}
