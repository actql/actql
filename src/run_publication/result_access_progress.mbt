///|
pub(all) enum ResultAccessProgressIssue {
  ResultAccessInvalidState
} derive(Eq, Debug)

///|
pub(all) enum ResultAccessProgressAction {
  ResultAccessAuthorizeRequest
  ResultAccessResolveCommittedResult
  ResultAccessCheckInitialAvailability
  ResultAccessAdmitRead
  ResultAccessIssueGrant
  ResultAccessStartDelivery
  ResultAccessReject
} derive(Eq, Debug)

///|
priv enum ResultAccessProgressState {
  WaitingForRequestAuthorization
  WaitingForCommittedResult
  WaitingForInitialAvailability
  WaitingForReadAdmission
  WaitingForGrant
  ReadyForDelivery
  AccessRejected
}

///|
struct ResultAccessProgress {
  mut state : ResultAccessProgressState
}

///|
pub fn begin_result_access_progress() -> ResultAccessProgress {
  { state: WaitingForRequestAuthorization, }
}

///|
pub fn result_access_progress_action(
  progress : ResultAccessProgress,
) -> ResultAccessProgressAction {
  match progress.state {
    WaitingForRequestAuthorization => ResultAccessAuthorizeRequest
    WaitingForCommittedResult => ResultAccessResolveCommittedResult
    WaitingForInitialAvailability => ResultAccessCheckInitialAvailability
    WaitingForReadAdmission => ResultAccessAdmitRead
    WaitingForGrant => ResultAccessIssueGrant
    ReadyForDelivery => ResultAccessStartDelivery
    AccessRejected => ResultAccessReject
  }
}

///|
pub fn result_access_progress_action_code(
  progress : ResultAccessProgress,
) -> Int {
  match result_access_progress_action(progress) {
    ResultAccessAuthorizeRequest => 0
    ResultAccessResolveCommittedResult => 1
    ResultAccessCheckInitialAvailability => 2
    ResultAccessAdmitRead => 3
    ResultAccessIssueGrant => 4
    ResultAccessStartDelivery => 5
    ResultAccessReject => 6
  }
}

///|
pub fn record_result_access_request_authorization(
  progress : ResultAccessProgress,
  authorized : Bool,
) -> Result[Unit, ResultAccessProgressIssue] {
  if !(progress.state is WaitingForRequestAuthorization) {
    return Err(ResultAccessInvalidState)
  }
  progress.state = if authorized {
    WaitingForCommittedResult
  } else {
    AccessRejected
  }
  Ok(())
}

///|
pub fn record_result_access_resolution(
  progress : ResultAccessProgress,
  resolved : Bool,
) -> Result[Unit, ResultAccessProgressIssue] {
  if !(progress.state is WaitingForCommittedResult) {
    return Err(ResultAccessInvalidState)
  }
  progress.state = if resolved {
    WaitingForInitialAvailability
  } else {
    AccessRejected
  }
  Ok(())
}

///|
pub fn record_result_access_initial_availability(
  progress : ResultAccessProgress,
  available : Bool,
) -> Result[Unit, ResultAccessProgressIssue] {
  if !(progress.state is WaitingForInitialAvailability) {
    return Err(ResultAccessInvalidState)
  }
  progress.state = if available {
    WaitingForReadAdmission
  } else {
    AccessRejected
  }
  Ok(())
}

///|
pub fn record_result_access_read_admission(
  progress : ResultAccessProgress,
  admitted : Bool,
) -> Result[Unit, ResultAccessProgressIssue] {
  if !(progress.state is WaitingForReadAdmission) {
    return Err(ResultAccessInvalidState)
  }
  progress.state = if admitted { WaitingForGrant } else { AccessRejected }
  Ok(())
}

///|
pub fn record_result_access_grant(
  progress : ResultAccessProgress,
  issued : Bool,
) -> Result[Unit, ResultAccessProgressIssue] {
  if !(progress.state is WaitingForGrant) {
    return Err(ResultAccessInvalidState)
  }
  progress.state = if issued { ReadyForDelivery } else { AccessRejected }
  Ok(())
}
