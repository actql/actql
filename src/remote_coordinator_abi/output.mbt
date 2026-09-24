///|
/// In-process proof that one Site plan matches the retained dispatch output
/// and the checked Run's Result Definition. No CID grants publication access.
struct CoordinatorCheckedOutputPlan {
  output : @remote.RemotePollOutput
  plan : @remote.RemoteOutputPlan
}

///|
#export_name("coordinatorAdmitCheckedOutputPlan")
pub fn coordinator_admit_checked_output_plan(
  durable : @remote.DurableCoordinatorDispatchRecord,
  poll_body : String,
  plan_body : String,
  expected_result_definition_cid : String,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[CoordinatorCheckedOutputPlan, @remote.DispatchIssue] {
  let output = match @remote.admit_remote_poll_output_plan_json(poll_body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let request = @remote.remote_poll_output_request(output)
  let retained = @remote.durable_coordinator_dispatch_record_request(durable)
  if @remote.dispatch_request_identity(request) !=
    @remote.dispatch_request_identity(retained) ||
    @remote.remote_output_intent_projection(
      @remote.remote_poll_output_intent(output),
    ).result_definition_cid != expected_result_definition_cid {
    return Err(@remote.DispatchIdentityMismatch)
  }
  match coordinator_accepted_site_output(durable) {
    Ok(Some(_)) => ()
    _ => return Err(@remote.InvalidJournal)
  }
  guard @remote.durable_coordinator_dispatch_record_subject(durable)
    is Some(subject) else {
    return Err(@remote.InvalidJournal)
  }
  let plan = match
    @remote.admit_remote_output_plan_json(
      plan_body,
      output,
      subject,
      max_chunks,
      max_manifest_bytes,
      max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ output, plan, })
}

///|
#export_name("coordinatorCheckedOutputPlanCid")
pub fn coordinator_checked_output_plan_cid(
  checked : CoordinatorCheckedOutputPlan,
) -> String {
  @remote.remote_output_plan_identity(checked.plan)
}

///|
#export_name("coordinatorCheckedOutputIntentCid")
pub fn coordinator_checked_output_intent_cid(
  checked : CoordinatorCheckedOutputPlan,
) -> String {
  @remote.remote_output_intent_identity(
    @remote.remote_poll_output_intent(checked.output),
  )
}

///|
/// The common owner checks that the same dispatch and Result occurrence was
/// already admitted before preparing an output intent for durable storage.
#export_name("coordinatorPrepareOutputIntent")
pub fn coordinator_prepare_output_intent(
  journal : @remote.CoordinatorDispatchJournal,
  checked : CoordinatorCheckedOutputPlan,
) -> Result[@remote.CoordinatorOutputAdmission, @remote.DispatchIssue] {
  @remote.prepare_coordinator_output_intent(
    journal,
    checked.output,
    @remote.remote_output_plan_payload_request(checked.plan),
    @remote.remote_output_plan_transfer_request(checked.plan),
  )
}

///|
#export_name("coordinatorOutputIntentIsNew")
pub fn coordinator_output_intent_is_new(
  admission : @remote.CoordinatorOutputAdmission,
) -> Bool {
  @remote.coordinator_output_intent_kind(admission) == @remote.NewDispatch
}

///|
#export_name("coordinatorCommitOutputIntent")
pub fn coordinator_commit_output_intent(
  admission : @remote.CoordinatorOutputAdmission,
) -> Result[@remote.CoordinatorOutputRecord, @remote.DispatchIssue] {
  match @remote.commit_coordinator_output_intent(admission, true) {
    Ok((_, record)) => Ok(record)
    Err(issue) => Err(issue)
  }
}

///|
#export_name("coordinatorOutputRecordStatus")
pub fn coordinator_output_record_status(
  record : @remote.CoordinatorOutputRecord,
) -> Array[String] {
  @remote.coordinator_output_record_status(record)
}
