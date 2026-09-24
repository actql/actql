///|
/// Coordinator-owned progress for one exact retained-output operation. The
/// Site still owns the physical publication and Transfer observations.
pub(all) enum CoordinatorOutputProgress {
  CoordinatorOutputIntentDurable
  CoordinatorOutputUnknown
  CoordinatorOutputSucceeded
} derive(Eq, Debug)

///|
struct CoordinatorOutputRecord {
  output : RemotePollOutput
  payload_request : @payload.PublicationPayloadRequest
  transfer_request : @transfer.RemoteTransferRequest
  mut revision : Int
  mut progress : CoordinatorOutputProgress
  mut result : RemoteOutputResult?
}

///|
struct CoordinatorOutputAdmission {
  journal : CoordinatorDispatchJournal
  output : RemotePollOutput
  payload_request : @payload.PublicationPayloadRequest
  transfer_request : @transfer.RemoteTransferRequest
  acceptance : DispatchAcceptance
  mut consumed : Bool
}

///|
struct CoordinatorOutputTransition {
  record : CoordinatorOutputRecord
  expected : Array[String]
  next : Array[String]
  next_progress : CoordinatorOutputProgress
  next_result : RemoteOutputResult?
  mut consumed : Bool
}

///|
fn coordinator_output_occurrence_key(output : RemotePollOutput) -> String {
  let projection = remote_output_intent_projection(output.intent)
  keyed(dispatch_request_identity(output.request)) +
  keyed(projection.result_definition_cid)
}

///|
fn coordinator_output_progress_code(
  progress : CoordinatorOutputProgress,
) -> Int {
  match progress {
    CoordinatorOutputIntentDurable => 0
    CoordinatorOutputUnknown => 1
    CoordinatorOutputSucceeded => 2
  }
}

///|
fn coordinator_output_progress_from_code(
  code : Int,
) -> Result[CoordinatorOutputProgress, DispatchIssue] {
  match code {
    0 => Ok(CoordinatorOutputIntentDurable)
    1 => Ok(CoordinatorOutputUnknown)
    2 => Ok(CoordinatorOutputSucceeded)
    _ => Err(InvalidJournal)
  }
}

///|
fn coordinator_output_result_identity_or_empty(
  result : RemoteOutputResult?,
) -> String {
  match result {
    Some(value) => remote_output_result_identity(value)
    None => ""
  }
}

///|
fn coordinator_output_record_projection(
  record : CoordinatorOutputRecord,
) -> Array[String] {
  [
    record.revision.to_string(),
    coordinator_output_progress_code(record.progress).to_string(),
    coordinator_output_result_identity_or_empty(record.result),
  ]
}

///|
fn coordinator_output_matches(
  record : CoordinatorOutputRecord,
  output : RemotePollOutput,
  payload_request : @payload.PublicationPayloadRequest,
  transfer_request : @transfer.RemoteTransferRequest,
) -> Bool {
  remote_output_intent_identity(record.output.intent) ==
  remote_output_intent_identity(output.intent) &&
  dispatch_request_identity(record.output.request) ==
  dispatch_request_identity(output.request) &&
  @payload.publication_payload_request_identity(record.payload_request) ==
  @payload.publication_payload_request_identity(payload_request) &&
  @transfer.request_cid(record.transfer_request) ==
  @transfer.request_cid(transfer_request)
}

///|
pub fn prepare_coordinator_output_intent(
  journal : CoordinatorDispatchJournal,
  output : RemotePollOutput,
  payload_request : @payload.PublicationPayloadRequest,
  transfer_request : @transfer.RemoteTransferRequest,
) -> Result[CoordinatorOutputAdmission, DispatchIssue] {
  if !output_expected_inputs_valid(output, payload_request, transfer_request) {
    return Err(InvalidDispatch)
  }
  let request = output.request
  if request.coordinator_authority != journal.authority {
    return Err(ForeignCoordinator)
  }
  match journal.dispatches.get(dispatch_key(request)) {
    Some(dispatch_record) if dispatch_record.request.dispatch_request_cid ==
      request.dispatch_request_cid => ()
    _ => return Err(InvalidJournal)
  }
  let occurrence = coordinator_output_occurrence_key(output)
  match journal.outputs.get(occurrence) {
    Some(record) =>
      if coordinator_output_matches(
          record, output, payload_request, transfer_request,
        ) {
        Ok({
          journal,
          output,
          payload_request,
          transfer_request,
          acceptance: ExistingDispatch,
          consumed: false,
        })
      } else {
        Err(DispatchCollision)
      }
    None =>
      Ok({
        journal,
        output,
        payload_request,
        transfer_request,
        acceptance: NewDispatch,
        consumed: false,
      })
  }
}

///|
pub fn coordinator_output_intent_kind(
  admission : CoordinatorOutputAdmission,
) -> DispatchAcceptance {
  admission.acceptance
}

///|
pub fn commit_coordinator_output_intent(
  admission : CoordinatorOutputAdmission,
  durable : Bool,
) -> Result[(DispatchAcceptance, CoordinatorOutputRecord), DispatchIssue] {
  if admission.consumed {
    return Err(InvalidTransition)
  }
  if !durable {
    return Err(DurabilityUnconfirmed)
  }
  let occurrence = coordinator_output_occurrence_key(admission.output)
  match admission.journal.outputs.get(occurrence) {
    Some(record) => {
      if !coordinator_output_matches(
          record,
          admission.output,
          admission.payload_request,
          admission.transfer_request,
        ) {
        return Err(DispatchCollision)
      }
      admission.consumed = true
      Ok((ExistingDispatch, record))
    }
    None => {
      if admission.acceptance == ExistingDispatch {
        return Err(InvalidTransition)
      }
      let record = {
        output: admission.output,
        payload_request: admission.payload_request,
        transfer_request: admission.transfer_request,
        revision: 0,
        progress: CoordinatorOutputIntentDurable,
        result: None,
      }
      admission.journal.outputs[occurrence] = record
      admission.consumed = true
      Ok((NewDispatch, record))
    }
  }
}

///|
pub fn coordinator_output_admission_key(
  admission : CoordinatorOutputAdmission,
) -> Array[String] {
  coordinator_output_key(admission.output)
}

///|
pub fn coordinator_output_admission_json(
  admission : CoordinatorOutputAdmission,
) -> Result[String, DispatchIssue] {
  remote_poll_output_json(admission.output.request, admission.output.intent)
}

///|
fn coordinator_output_key(output : RemotePollOutput) -> Array[String] {
  let request = output.request
  let projection = remote_output_intent_projection(output.intent)
  [
    request.coordinator_authority,
    request.site_key,
    request.site_generation.to_string(),
    request.dispatch_id,
    request.dispatch_request_cid,
    projection.result_definition_cid,
    remote_output_intent_identity(output.intent),
  ]
}

///|
pub fn coordinator_output_record_key(
  record : CoordinatorOutputRecord,
) -> Array[String] {
  coordinator_output_key(record.output)
}

///|
pub fn coordinator_output_record_revision(
  record : CoordinatorOutputRecord,
) -> Int {
  record.revision
}

///|
pub fn coordinator_output_record_status(
  record : CoordinatorOutputRecord,
) -> Array[String] {
  coordinator_output_record_projection(record)
}

///|
pub fn coordinator_output_record_result_json(
  record : CoordinatorOutputRecord,
) -> Result[String, DispatchIssue] {
  match record.result {
    Some(result) => remote_output_result_json(result)
    None => Ok("")
  }
}

///|
pub fn coordinator_output_record_result_projection(
  record : CoordinatorOutputRecord,
) -> Result[Array[String], DispatchIssue] {
  match record.result {
    Some(result) =>
      remote_output_result_projection(result, record.transfer_request)
    None => Err(InvalidTransition)
  }
}

///|
fn prepare_coordinator_output_transition(
  record : CoordinatorOutputRecord,
  progress : CoordinatorOutputProgress,
  result : RemoteOutputResult?,
) -> CoordinatorOutputTransition {
  let expected = coordinator_output_record_projection(record)
  let next = [
    (record.revision + 1).to_string(),
    coordinator_output_progress_code(progress).to_string(),
    coordinator_output_result_identity_or_empty(result),
  ]
  {
    record,
    expected,
    next,
    next_progress: progress,
    next_result: result,
    consumed: false,
  }
}

///|
pub fn prepare_coordinator_output_unknown(
  record : CoordinatorOutputRecord,
) -> Result[CoordinatorOutputTransition, DispatchIssue] {
  if record.progress == CoordinatorOutputSucceeded {
    return Err(InvalidTransition)
  }
  Ok(
    prepare_coordinator_output_transition(
      record,
      CoordinatorOutputUnknown,
      None,
    ),
  )
}

///|
pub fn prepare_coordinator_output_success(
  record : CoordinatorOutputRecord,
  result : RemoteOutputResult,
) -> Result[CoordinatorOutputTransition, DispatchIssue] {
  if record.progress == CoordinatorOutputSucceeded ||
    !output_expected_inputs_valid(
      record.output,
      record.payload_request,
      record.transfer_request,
    ) {
    return Err(InvalidTransition)
  }
  let body = match remote_output_result_json(result) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    admit_remote_output_result_json(
      body,
      record.output,
      record.payload_request,
      record.transfer_request,
    ) {
    Ok(_) =>
      Ok(
        prepare_coordinator_output_transition(
          record,
          CoordinatorOutputSucceeded,
          Some(result),
        ),
      )
    Err(issue) => Err(issue)
  }
}

///|
pub fn coordinator_output_transition_key(
  transition : CoordinatorOutputTransition,
) -> Array[String] {
  coordinator_output_record_key(transition.record)
}

///|
pub fn coordinator_output_transition_projection(
  transition : CoordinatorOutputTransition,
) -> Array[String] {
  transition.expected + transition.next
}

///|
pub fn commit_coordinator_output_transition(
  transition : CoordinatorOutputTransition,
  durable : Bool,
) -> Result[CoordinatorOutputRecord, DispatchIssue] {
  if transition.consumed {
    return Err(InvalidTransition)
  }
  if !durable {
    return Err(DurabilityUnconfirmed)
  }
  if coordinator_output_record_projection(transition.record) !=
    transition.expected {
    return Err(StateCollision)
  }
  transition.record.revision = transition.record.revision + 1
  transition.record.progress = transition.next_progress
  transition.record.result = transition.next_result
  transition.consumed = true
  Ok(transition.record)
}

///|
pub fn restore_coordinator_output_record(
  record : CoordinatorOutputRecord,
  revision : Int,
  progress_code : Int,
  result_json : String,
) -> Result[CoordinatorOutputRecord, DispatchIssue] {
  if revision < 0 ||
    record.revision != 0 ||
    record.progress != CoordinatorOutputIntentDurable ||
    record.result is Some(_) {
    return Err(InvalidJournal)
  }
  let progress = match coordinator_output_progress_from_code(progress_code) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if (revision == 0) != (progress == CoordinatorOutputIntentDurable) {
    return Err(InvalidJournal)
  }
  let result = match progress {
    CoordinatorOutputSucceeded =>
      if result_json.is_empty() {
        return Err(InvalidJournal)
      } else {
        match
          admit_remote_output_result_json(
            result_json,
            record.output,
            record.payload_request,
            record.transfer_request,
          ) {
          Ok(value) => Some(value)
          Err(_) => return Err(InvalidJournal)
        }
      }
    CoordinatorOutputIntentDurable | CoordinatorOutputUnknown =>
      if result_json.is_empty() {
        None
      } else {
        return Err(InvalidJournal)
      }
  }
  record.revision = revision
  record.progress = progress
  record.result = result
  Ok(record)
}
