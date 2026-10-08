///|
/// Select an original completed attempt for the existing accepted queue.
/// This is not permission to execute or use its output: the holder must acquire
/// the exclusive slot and re-admit the saved materials and current authority
/// through prepare_resident_completed_attempt before accessing custody.
fn queue_completed_output_holder(
  journal : @journal.Journal,
  delegation : @resident.ResidentSiteDelegation,
  generation : Int,
  queue : @resident.ResidentAcceptedQueue,
  request : @remote.DispatchRequest,
) -> Bool {
  if @resident.check_resident_dispatch_delegation(
      delegation, request, generation,
    )
    is Err(_) ||
    !(journal.cancellation_requested(request) is Ok(false)) {
    return false
  }
  let record = match journal.require(request) {
    Ok(value) => value
    Err(_) => return false
  }
  let codes = @remote.dispatch_record_state_codes(record)
  // A pending cleanup must resume its cleanup Owner, not a new output holder.
  if codes[0] != 3 ||
    codes[2] != 0 ||
    !(journal.start_claimant(request) is Ok(Some(_))) {
    return false
  }
  let attempt = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(_) => return false
  }
  guard journal.dispatch_envelope(attempt) is Ok(Some(envelope)) &&
    @remote.admit_remote_poll_dispatch_json(envelope) is Ok(dispatch) &&
    @remote.dispatch_request_identity(
      @remote.remote_poll_dispatch_request(dispatch),
    ) ==
    @remote.dispatch_request_identity(request) &&
    @remote.remote_poll_dispatch_run_materials(dispatch) is Some(_) else {
    return false
  }
  let saved = match journal.observation(request) {
    Ok(value) => value
    Err(_) => return false
  }
  guard @journal.recovered_site_dispatch_evidence(saved) is Some(evidence) &&
    @journal.recovered_site_dispatch_subject(saved) is Some(subject) &&
    @journal.recovered_site_dispatch_measurement(saved) is Some(measurement) &&
    @journal.recovered_site_dispatch_file_custody(saved) is Some(_) else {
    return false
  }
  if @remote.restore_remote_runtime_completed_custody(
      record, evidence, subject, measurement,
    )
    is Err(_) {
    return false
  }
  if queue.length() > 0 && !queue.contains(attempt) {
    return false
  }
  queue.reserve(attempt) is Ok(_)
}
