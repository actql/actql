///|
/// The Coordinator journal owns dispatch intent. It is deliberately separate
/// from the Site journal, which owns physical execution observations.
struct CoordinatorDispatchJournal {
  authority : String
  dispatches : Map[String, CoordinatorDispatchIntentRecord]
  attempts : Map[String, String]
  outputs : Map[String, CoordinatorOutputRecord]
}

///|
/// A durable Coordinator intent does not claim that the Site accepted or ran
/// the dispatch.
struct CoordinatorDispatchIntentRecord {
  request : DispatchRequest
  mut revision : Int
  mut progress : CoordinatorDispatchProgress
  mut site_revision : Int
  mut site_execution : Int
  mut site_evidence : Int
  mut site_cleanup : Int
  mut site_material_available : Bool
  mut site_quarantined_capacity : Bool
  mut accepted_evidence_cid : String
  mut accepted_subject_cid : String
  mut accepted_measurement_cid : String
}

///|
/// Transport uncertainty and authenticated Site observation are Coordinator
/// facts. They do not replace the Site-owned physical state.
pub(all) enum CoordinatorDispatchProgress {
  CoordinatorIntentDurable
  CoordinatorOutcomeUnknown
  CoordinatorSiteObserved
} derive(Eq, Debug)

///|
struct CoordinatorDispatchTransition {
  record : CoordinatorDispatchIntentRecord
  expected : Array[String]
  next : Array[String]
  next_progress : CoordinatorDispatchProgress
  next_site_revision : Int
  next_site_execution : Int
  next_site_evidence : Int
  next_site_cleanup : Int
  next_site_material_available : Bool
  next_site_quarantined_capacity : Bool
  next_accepted_evidence_cid : String
  next_accepted_subject_cid : String
  next_accepted_measurement_cid : String
  mut consumed : Bool
}

///|
/// Prepared intent has no authority to send a request until the environment
/// adapter durably installs or reconciles its exact canonical body.
struct CoordinatorDispatchIntentAdmission {
  journal : CoordinatorDispatchJournal
  request : DispatchRequest
  acceptance : DispatchAcceptance
  mut consumed : Bool
}

///|
pub fn create_coordinator_dispatch_journal(
  authority : String,
) -> Result[CoordinatorDispatchJournal, DispatchIssue] {
  if authority.is_empty() {
    return Err(InvalidJournal)
  }
  Ok({ authority, dispatches: Map([]), attempts: Map([]), outputs: Map([]), })
}

///|
pub fn prepare_coordinator_dispatch_intent(
  journal : CoordinatorDispatchJournal,
  request : DispatchRequest,
) -> Result[CoordinatorDispatchIntentAdmission, DispatchIssue] {
  if !valid_request(request) {
    return Err(InvalidDispatch)
  }
  if request.coordinator_authority != journal.authority {
    return Err(ForeignCoordinator)
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
pub fn coordinator_dispatch_intent_kind(
  admission : CoordinatorDispatchIntentAdmission,
) -> DispatchAcceptance {
  admission.acceptance
}

///|
pub fn coordinator_dispatch_intent_json(
  admission : CoordinatorDispatchIntentAdmission,
) -> Result[String, DispatchIssue] {
  dispatch_request_json(admission.request)
}

///|
pub fn commit_coordinator_dispatch_intent(
  admission : CoordinatorDispatchIntentAdmission,
  durable : Bool,
) -> Result[
  (DispatchAcceptance, CoordinatorDispatchIntentRecord),
  DispatchIssue,
] {
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
        revision: 0,
        progress: CoordinatorIntentDurable,
        site_revision: -1,
        site_execution: -1,
        site_evidence: -1,
        site_cleanup: -1,
        site_material_available: false,
        site_quarantined_capacity: false,
        accepted_evidence_cid: "",
        accepted_subject_cid: "",
        accepted_measurement_cid: "",
      }
      journal.dispatches[key] = record
      journal.attempts[occurrence] = key
      admission.consumed = true
      Ok((NewDispatch, record))
    }
  }
}

///|
/// Restore one exact durable intent after a Coordinator process restart. This
/// neither sends the request nor establishes any Site observation.
pub fn restore_coordinator_dispatch_intent(
  journal : CoordinatorDispatchJournal,
  request : DispatchRequest,
) -> Result[CoordinatorDispatchIntentRecord, DispatchIssue] {
  let admission = match prepare_coordinator_dispatch_intent(journal, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match commit_coordinator_dispatch_intent(admission, true) {
    Ok((_, record)) => Ok(record)
    Err(issue) => Err(issue)
  }
}

///|
pub fn coordinator_dispatch_intent_matches_request(
  record : CoordinatorDispatchIntentRecord,
  request : DispatchRequest,
) -> Bool {
  record.request.dispatch_request_cid == request.dispatch_request_cid
}

///|
fn coordinator_progress_code(progress : CoordinatorDispatchProgress) -> Int {
  match progress {
    CoordinatorIntentDurable => 0
    CoordinatorOutcomeUnknown => 1
    CoordinatorSiteObserved => 2
  }
}

///|
fn coordinator_progress_from_code(
  code : Int,
) -> Result[CoordinatorDispatchProgress, DispatchIssue] {
  match code {
    0 => Ok(CoordinatorIntentDurable)
    1 => Ok(CoordinatorOutcomeUnknown)
    2 => Ok(CoordinatorSiteObserved)
    _ => Err(InvalidJournal)
  }
}

///|
fn coordinator_record_projection(
  record : CoordinatorDispatchIntentRecord,
) -> Array[String] {
  [
    record.revision.to_string(),
    coordinator_progress_code(record.progress).to_string(),
    record.site_revision.to_string(),
    record.site_execution.to_string(),
    record.site_evidence.to_string(),
    record.site_cleanup.to_string(),
    bool_code(record.site_material_available),
    bool_code(record.site_quarantined_capacity),
    record.accepted_evidence_cid,
    record.accepted_subject_cid,
    record.accepted_measurement_cid,
  ]
}

///|
fn coordinator_prepare_transition(
  record : CoordinatorDispatchIntentRecord,
  progress : CoordinatorDispatchProgress,
  site_revision : Int,
  site_execution : Int,
  site_evidence : Int,
  site_cleanup : Int,
  site_material_available : Bool,
  site_quarantined_capacity : Bool,
  accepted_evidence_cid : String,
  accepted_subject_cid : String,
  accepted_measurement_cid : String,
) -> CoordinatorDispatchTransition {
  let expected = coordinator_record_projection(record)
  let next = [
    (record.revision + 1).to_string(),
    coordinator_progress_code(progress).to_string(),
    site_revision.to_string(),
    site_execution.to_string(),
    site_evidence.to_string(),
    site_cleanup.to_string(),
    bool_code(site_material_available),
    bool_code(site_quarantined_capacity),
    accepted_evidence_cid,
    accepted_subject_cid,
    accepted_measurement_cid,
  ]
  {
    record,
    expected,
    next,
    next_progress: progress,
    next_site_revision: site_revision,
    next_site_execution: site_execution,
    next_site_evidence: site_evidence,
    next_site_cleanup: site_cleanup,
    next_site_material_available: site_material_available,
    next_site_quarantined_capacity: site_quarantined_capacity,
    next_accepted_evidence_cid: accepted_evidence_cid,
    next_accepted_subject_cid: accepted_subject_cid,
    next_accepted_measurement_cid: accepted_measurement_cid,
    consumed: false,
  }
}

///|
pub fn prepare_coordinator_outcome_unknown(
  record : CoordinatorDispatchIntentRecord,
) -> Result[CoordinatorDispatchTransition, DispatchIssue] {
  Ok(
    coordinator_prepare_transition(
      record,
      CoordinatorOutcomeUnknown,
      record.site_revision,
      record.site_execution,
      record.site_evidence,
      record.site_cleanup,
      record.site_material_available,
      record.site_quarantined_capacity,
      record.accepted_evidence_cid,
      record.accepted_subject_cid,
      record.accepted_measurement_cid,
    ),
  )
}

///|
fn valid_site_observation(
  execution : Int,
  evidence : Int,
  cleanup : Int,
  material_available : Bool,
  quarantined_capacity : Bool,
) -> Bool {
  if execution < 0 ||
    execution > 6 ||
    evidence < 0 ||
    evidence > 3 ||
    cleanup < 0 ||
    cleanup > 5 {
    return false
  }
  if (evidence == 1 || evidence == 2) && execution != 3 {
    return false
  }
  if material_available &&
    (
      execution != 3 ||
      (evidence != 1 && evidence != 2) ||
      cleanup == 2 ||
      cleanup == 4 ||
      cleanup == 5
    ) {
    return false
  }
  if cleanup == 4 && !quarantined_capacity {
    return false
  }
  if quarantined_capacity && cleanup != 4 {
    return false
  }
  true
}

///|
/// Accepted evidence identities are historical Coordinator facts. A later
/// observation may fill a fact that was not delivered with the first status
/// response, but it cannot replace an already accepted identity for the same
/// dispatch.
fn merge_coordinator_evidence_identity(
  current : String,
  observed : String,
) -> Result[String, DispatchIssue] {
  if current.is_empty() {
    return Ok(observed)
  }
  if observed.is_empty() || observed == current {
    return Ok(current)
  }
  Err(StateCollision)
}

///|
pub fn prepare_coordinator_observation(
  record : CoordinatorDispatchIntentRecord,
  site_revision : Int,
  site_execution : Int,
  site_evidence : Int,
  site_cleanup : Int,
  site_material_available : Bool,
  site_quarantined_capacity : Bool,
  evidence : RemoteExecutionEvidence?,
  subject : RemoteManagedOutputSubject?,
  measurement : RemoteManagedOutputMeasurement?,
) -> Result[CoordinatorDispatchTransition, DispatchIssue] {
  match (evidence, subject, measurement) {
    (None, None, None) | (Some(_), None, None) | (Some(_), Some(_), Some(_)) =>
      ()
    _ => return Err(InvalidDispatch)
  }
  if site_revision < 0 ||
    !valid_site_observation(
      site_execution, site_evidence, site_cleanup, site_material_available, site_quarantined_capacity,
    ) {
    return Err(InvalidDispatch)
  }
  if record.site_revision > site_revision {
    return Err(StateCollision)
  }
  if record.site_revision == site_revision &&
    record.site_revision >= 0 &&
    (
      record.site_execution != site_execution ||
      record.site_evidence != site_evidence ||
      record.site_cleanup != site_cleanup ||
      record.site_material_available != site_material_available ||
      record.site_quarantined_capacity != site_quarantined_capacity
    ) {
    return Err(StateCollision)
  }
  let accepted_evidence_cid = match evidence {
    Some(value) => {
      if site_evidence != 2 ||
        !remote_execution_evidence_matches_dispatch(value, record.request) {
        return Err(InvalidDispatch)
      }
      match
        merge_coordinator_evidence_identity(
          record.accepted_evidence_cid,
          remote_execution_evidence_cid(value),
        ) {
        Ok(cid) => cid
        Err(issue) => return Err(issue)
      }
    }
    None => record.accepted_evidence_cid
  }
  let accepted_subject_cid = match subject {
    Some(value) => {
      let admitted_evidence = match evidence {
        Some(current) => current
        None => return Err(InvalidDispatch)
      }
      if site_evidence != 2 ||
        !remote_managed_output_subject_matches_evidence(
          value,
          admitted_evidence,
          record.request,
        ) {
        return Err(InvalidDispatch)
      }
      match
        merge_coordinator_evidence_identity(
          record.accepted_subject_cid,
          remote_managed_output_subject_cid(value),
        ) {
        Ok(cid) => cid
        Err(issue) => return Err(issue)
      }
    }
    None => record.accepted_subject_cid
  }
  let accepted_measurement_cid = match measurement {
    Some(value) => {
      let admitted_subject = match subject {
        Some(current) => current
        None => return Err(InvalidDispatch)
      }
      if site_evidence != 2 ||
        !remote_managed_output_subject_matches_measurement(
          admitted_subject, value,
        ) {
        return Err(InvalidDispatch)
      }
      match
        merge_coordinator_evidence_identity(
          record.accepted_measurement_cid,
          remote_managed_output_measurement_cid(value),
        ) {
        Ok(cid) => cid
        Err(issue) => return Err(issue)
      }
    }
    None => record.accepted_measurement_cid
  }
  Ok(
    coordinator_prepare_transition(
      record,
      CoordinatorSiteObserved,
      site_revision,
      site_execution,
      site_evidence,
      site_cleanup,
      site_material_available,
      site_quarantined_capacity,
      accepted_evidence_cid,
      accepted_subject_cid,
      accepted_measurement_cid,
    ),
  )
}

///|
/// Admit a generic Site observation. Even durable generic evidence cannot
/// authorize managed completion because it lacks the canonical output subject.
pub fn prepare_coordinator_site_observation(
  record : CoordinatorDispatchIntentRecord,
  site_revision : Int,
  site_execution : Int,
  site_evidence : Int,
  site_cleanup : Int,
  site_material_available : Bool,
  site_quarantined_capacity : Bool,
  evidence : RemoteExecutionEvidence?,
) -> Result[CoordinatorDispatchTransition, DispatchIssue] {
  prepare_coordinator_observation(
    record,
    site_revision,
    site_execution,
    site_evidence,
    site_cleanup,
    site_material_available,
    site_quarantined_capacity,
    evidence,
    None,
    None,
  )
}

///|
/// Admit exact managed-output evidence as one pair. Neither the evidence nor
/// its subject can independently authorize common completion.
pub fn prepare_coordinator_managed_output_observation(
  record : CoordinatorDispatchIntentRecord,
  site_revision : Int,
  site_execution : Int,
  site_evidence : Int,
  site_cleanup : Int,
  site_material_available : Bool,
  site_quarantined_capacity : Bool,
  evidence : RemoteExecutionEvidence,
  subject : RemoteManagedOutputSubject,
  measurement : RemoteManagedOutputMeasurement,
) -> Result[CoordinatorDispatchTransition, DispatchIssue] {
  prepare_coordinator_observation(
    record,
    site_revision,
    site_execution,
    site_evidence,
    site_cleanup,
    site_material_available,
    site_quarantined_capacity,
    Some(evidence),
    Some(subject),
    Some(measurement),
  )
}

///|
pub fn coordinator_dispatch_transition_projection(
  transition : CoordinatorDispatchTransition,
) -> Array[String] {
  transition.expected + transition.next
}

///|
pub fn coordinator_dispatch_transition_journal_key(
  transition : CoordinatorDispatchTransition,
) -> Array[String] {
  dispatch_request_journal_key(transition.record.request)
}

///|
pub fn commit_coordinator_dispatch_transition(
  transition : CoordinatorDispatchTransition,
  durable : Bool,
) -> Result[Unit, DispatchIssue] {
  if transition.consumed {
    return Err(InvalidTransition)
  }
  if !durable {
    return Err(DurabilityUnconfirmed)
  }
  if coordinator_record_projection(transition.record) != transition.expected {
    return Err(StateCollision)
  }
  transition.record.revision += 1
  transition.record.progress = transition.next_progress
  transition.record.site_revision = transition.next_site_revision
  transition.record.site_execution = transition.next_site_execution
  transition.record.site_evidence = transition.next_site_evidence
  transition.record.site_cleanup = transition.next_site_cleanup
  transition.record.site_material_available = transition.next_site_material_available
  transition.record.site_quarantined_capacity = transition.next_site_quarantined_capacity
  transition.record.accepted_evidence_cid = transition.next_accepted_evidence_cid
  transition.record.accepted_subject_cid = transition.next_accepted_subject_cid
  transition.record.accepted_measurement_cid = transition.next_accepted_measurement_cid
  transition.consumed = true
  Ok(())
}

///|
pub fn coordinator_completion_evidence_available(
  record : CoordinatorDispatchIntentRecord,
) -> Bool {
  record.progress == CoordinatorSiteObserved &&
  record.site_execution == 3 &&
  record.site_evidence == 2 &&
  record.site_material_available &&
  record.site_cleanup != 2 &&
  record.site_cleanup != 4 &&
  record.site_cleanup != 5 &&
  valid_cid(record.accepted_evidence_cid) &&
  valid_cid(record.accepted_subject_cid) &&
  valid_cid(record.accepted_measurement_cid)
}

///|
/// Check that one complete managed-output observation is the exact durable
/// fact accepted by this Coordinator intent. Site evidence remains necessary,
/// but cannot reach common completion until the Coordinator has committed the
/// corresponding observation for the same dispatch.
pub fn coordinator_managed_output_matches(
  record : CoordinatorDispatchIntentRecord,
  request : DispatchRequest,
  evidence : RemoteExecutionEvidence,
  subject : RemoteManagedOutputSubject,
  measurement : RemoteManagedOutputMeasurement,
) -> Bool {
  coordinator_dispatch_intent_matches_request(record, request) &&
  coordinator_completion_evidence_available(record) &&
  record.accepted_evidence_cid == remote_execution_evidence_cid(evidence) &&
  record.accepted_subject_cid == remote_managed_output_subject_cid(subject) &&
  record.accepted_measurement_cid ==
  remote_managed_output_measurement_cid(measurement) &&
  remote_execution_evidence_matches_dispatch(evidence, request) &&
  remote_managed_output_subject_matches_evidence(subject, evidence, request) &&
  remote_managed_output_subject_matches_measurement(subject, measurement)
}

///|
pub fn coordinator_dispatch_record_state_codes(
  record : CoordinatorDispatchIntentRecord,
) -> Array[String] {
  coordinator_record_projection(record)
}

///|
pub fn coordinator_dispatch_record_revision(
  record : CoordinatorDispatchIntentRecord,
) -> Int {
  record.revision
}

///|
pub fn restore_coordinator_dispatch_record(
  record : CoordinatorDispatchIntentRecord,
  revision : Int,
  progress_code : Int,
  site_revision : Int,
  site_execution : Int,
  site_evidence : Int,
  site_cleanup : Int,
  site_material_available : Bool,
  site_quarantined_capacity : Bool,
  accepted_evidence_cid : String,
  accepted_subject_cid : String,
  accepted_measurement_cid : String,
) -> Result[Unit, DispatchIssue] {
  if record.revision != 0 ||
    record.progress != CoordinatorIntentDurable ||
    record.site_revision != -1 ||
    revision < 0 {
    return Err(InvalidTransition)
  }
  let progress = match coordinator_progress_from_code(progress_code) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if site_revision == -1 {
    if progress == CoordinatorSiteObserved ||
      site_execution != -1 ||
      site_evidence != -1 ||
      site_cleanup != -1 ||
      site_material_available ||
      site_quarantined_capacity ||
      !accepted_evidence_cid.is_empty() ||
      !accepted_subject_cid.is_empty() {
      return Err(InvalidJournal)
    }
    if !accepted_measurement_cid.is_empty() {
      return Err(InvalidJournal)
    }
  } else if site_revision < 0 ||
    !valid_site_observation(
      site_execution, site_evidence, site_cleanup, site_material_available, site_quarantined_capacity,
    ) ||
    (
      !accepted_evidence_cid.is_empty() &&
      (site_evidence != 2 || !valid_cid(accepted_evidence_cid))
    ) ||
    (
      !accepted_subject_cid.is_empty() &&
      (site_evidence != 2 || !valid_cid(accepted_subject_cid))
    ) ||
    (
      !accepted_measurement_cid.is_empty() &&
      (site_evidence != 2 || !valid_cid(accepted_measurement_cid))
    ) {
    return Err(InvalidJournal)
  }
  record.revision = revision
  record.progress = progress
  record.site_revision = site_revision
  record.site_execution = site_execution
  record.site_evidence = site_evidence
  record.site_cleanup = site_cleanup
  record.site_material_available = site_material_available
  record.site_quarantined_capacity = site_quarantined_capacity
  record.accepted_evidence_cid = accepted_evidence_cid
  record.accepted_subject_cid = accepted_subject_cid
  record.accepted_measurement_cid = accepted_measurement_cid
  Ok(())
}
