///|
/// The Coordinator journal owns dispatch intent. It is deliberately separate
/// from the Site journal, which owns physical execution observations.
struct CoordinatorDispatchJournal {
  authority : String
  dispatches : Map[String, CoordinatorDispatchIntentRecord]
  attempts : Map[String, String]
}

///|
/// A durable Coordinator intent does not claim that the Site accepted or ran
/// the dispatch.
struct CoordinatorDispatchIntentRecord {
  request : DispatchRequest
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
  Ok({ authority, dispatches: Map([]), attempts: Map([]), })
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
      let record = { request, }
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
