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
  match
    @remote.admit_coordinator_output_plan(
      durable, poll_body, plan_body, expected_result_definition_cid, max_chunks,
      max_manifest_bytes, max_referenced_bytes,
    ) {
    Ok((output, plan)) => Ok({ output, plan, })
    Err(issue) => Err(issue)
  }
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

///|
/// Physical storage must persist these exact bytes before committing the
/// prepared output intent in the in-process owner.
#export_name("coordinatorOutputAdmissionDurableJson")
pub fn coordinator_output_admission_durable_json(
  checked : CoordinatorCheckedOutputPlan,
) -> Result[String, @remote.DispatchIssue] {
  @remote.coordinator_output_admission_durable_json(
    checked.output,
    checked.plan,
  )
}

///|
#export_name("coordinatorAdmitDurableOutputJson")
pub fn coordinator_admit_durable_output_json(
  body : String,
  dispatch : @remote.DurableCoordinatorDispatchRecord,
  expected_result_definition_cid : String,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[@remote.DurableCoordinatorOutputRecord, @remote.DispatchIssue] {
  @remote.admit_durable_coordinator_output_record(
    @utf8.encode(body),
    dispatch,
    expected_result_definition_cid,
    max_chunks,
    max_manifest_bytes,
    max_referenced_bytes,
  )
}

///|
#export_name("coordinatorRestoreDurableOutput")
pub fn coordinator_restore_durable_output(
  journal : @remote.CoordinatorDispatchJournal,
  durable : @remote.DurableCoordinatorOutputRecord,
) -> Result[@remote.CoordinatorOutputRecord, @remote.DispatchIssue] {
  @remote.restore_durable_coordinator_output_record(journal, durable)
}

///|
#export_name("coordinatorDurableOutputRevision")
pub fn coordinator_durable_output_revision(
  durable : @remote.DurableCoordinatorOutputRecord,
) -> Int {
  @remote.durable_coordinator_output_record_revision(durable)
}

///|
#export_name("coordinatorDurableOutputJson")
pub fn coordinator_durable_output_json(
  durable : @remote.DurableCoordinatorOutputRecord,
) -> String {
  @remote.durable_coordinator_output_record_json(durable)
}
