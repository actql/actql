///|
/// In-process JS ABI for the common durable Coordinator dispatch owner.
/// Durable bytes cross the adapter boundary; opaque handles remain local.
#export_name("coordinatorCreateJournal")
pub fn coordinator_create_journal(
  authority : String,
) -> Result[@remote.CoordinatorDispatchJournal, @remote.DispatchIssue] {
  @remote.create_coordinator_dispatch_journal(authority)
}

///|
/// A Host must supply the exact already-authorized Run, Site and budget CIDs.
/// This operation only creates the shared dispatch identity.
#export_name("coordinatorPrepareDispatch")
pub fn coordinator_prepare_dispatch(
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
  evidence_issuer_capability_cid : String,
  grant_cid : String,
) -> Result[@remote.DispatchRequest, @remote.DispatchIssue] {
  @remote.prepare_dispatch_request(
    coordinator_authority, run_definition_cid, task_key, task_attempt, dispatch_id,
    site_key, site_generation, runtime_bundle_cid, connector_registration, connector_revision,
    strategy_revision, input_binding_cid, obligations_cid, budget_cid, evidence_issuer_capability_cid,
    grant_cid,
  )
}

///|
#export_name("coordinatorDispatchCid")
pub fn coordinator_dispatch_cid(request : @remote.DispatchRequest) -> String {
  @remote.dispatch_request_identity(request)
}

///|
#export_name("coordinatorDispatchJson")
pub fn coordinator_dispatch_json(
  request : @remote.DispatchRequest,
) -> Result[String, @remote.DispatchIssue] {
  @remote.dispatch_request_json(request)
}

///|
/// Re-admit a checked Host-issued dispatch wire at the durable Coordinator
/// boundary. The CID proves byte identity, not Site grant authority.
#export_name("coordinatorAdmitDispatchJson")
pub fn coordinator_admit_dispatch_json(
  body : String,
  claimed_cid : String,
) -> Result[@remote.DispatchRequest, @remote.DispatchIssue] {
  @remote.admit_dispatch_request_json(body, claimed_cid)
}

///|
#export_name("coordinatorDispatchRoute")
pub fn coordinator_dispatch_route(
  request : @remote.DispatchRequest,
) -> Array[String] {
  @remote.dispatch_request_journal_key(request)
}

///|
/// The Connector binding body is checked against the dispatch identity before
/// any bytes are offered to the Site transport.
#export_name("coordinatorPollDispatchJson")
pub fn coordinator_poll_dispatch_json(
  request : @remote.DispatchRequest,
  input_binding_body : String,
  max_binding_bytes : Int,
) -> Result[String, @remote.DispatchIssue] {
  let binding = match
    @remote.prepare_remote_input_binding(input_binding_body, max_binding_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @remote.remote_poll_dispatch_json(request, binding)
}

///|
/// A dispatch that also offers typed run materials to a Site that did not
/// install the Run. The Site rebuilds and admits them; they grant nothing.
#export_name("coordinatorPollDispatchMaterialsJson")
pub fn coordinator_poll_dispatch_materials_json(
  request : @remote.DispatchRequest,
  input_binding_body : String,
  max_binding_bytes : Int,
  run_materials : String,
) -> Result[String, @remote.DispatchIssue] {
  let binding = match
    @remote.prepare_remote_input_binding(input_binding_body, max_binding_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @remote.remote_poll_dispatch_materials_json(request, binding, run_materials)
}

///|
#export_name("coordinatorPollQueryJson")
pub fn coordinator_poll_query_json(
  request : @remote.DispatchRequest,
) -> Result[String, @remote.DispatchIssue] {
  @remote.remote_poll_query_json(request)
}

///|
/// The common release request for the exact retained dispatch output.
#export_name("coordinatorPollReleaseJson")
pub fn coordinator_poll_release_json(
  request : @remote.DispatchRequest,
) -> Result[String, @remote.DispatchIssue] {
  @remote.remote_poll_release_json(request)
}

///|
/// Admits a Site's not-seen answer for exactly this dispatch request.
#export_name("coordinatorAdmitPollNotSeen")
pub fn coordinator_admit_poll_not_seen(
  body : String,
  request : @remote.DispatchRequest,
) -> Result[Bool, @remote.DispatchIssue] {
  match @remote.admit_remote_poll_not_seen_json(body, request) {
    Ok(_) => Ok(true)
    Err(issue) => Err(issue)
  }
}

///|
#export_name("coordinatorPrepareIntent")
pub fn coordinator_prepare_intent(
  journal : @remote.CoordinatorDispatchJournal,
  request : @remote.DispatchRequest,
) -> Result[@remote.CoordinatorDispatchIntentAdmission, @remote.DispatchIssue] {
  @remote.prepare_coordinator_dispatch_intent(journal, request)
}

///|
/// Only a newly admitted durable intent can authorize an initial Site send.
#export_name("coordinatorIntentIsNew")
pub fn coordinator_intent_is_new(
  admission : @remote.CoordinatorDispatchIntentAdmission,
) -> Bool {
  @remote.coordinator_dispatch_intent_kind(admission) == @remote.NewDispatch
}

///|
#export_name("coordinatorAdmissionDurableJson")
pub fn coordinator_admission_durable_json(
  admission : @remote.CoordinatorDispatchIntentAdmission,
) -> Result[String, @remote.DispatchIssue] {
  @remote.coordinator_dispatch_admission_durable_json(admission)
}

///|
/// Commit the in-process owner only after physical compare-and-swap succeeds.
#export_name("coordinatorCommitIntent")
pub fn coordinator_commit_intent(
  admission : @remote.CoordinatorDispatchIntentAdmission,
) -> Result[@remote.CoordinatorDispatchIntentRecord, @remote.DispatchIssue] {
  match @remote.commit_coordinator_dispatch_intent(admission, true) {
    Ok((_, record)) => Ok(record)
    Err(issue) => Err(issue)
  }
}

///|
#export_name("coordinatorAdmitDurableJson")
pub fn coordinator_admit_durable_json(
  body : String,
) -> Result[@remote.DurableCoordinatorDispatchRecord, @remote.DispatchIssue] {
  @remote.admit_durable_coordinator_dispatch_record(@utf8.encode(body))
}

///|
#export_name("coordinatorRestoreDurable")
pub fn coordinator_restore_durable(
  journal : @remote.CoordinatorDispatchJournal,
  durable : @remote.DurableCoordinatorDispatchRecord,
) -> Result[@remote.CoordinatorDispatchIntentRecord, @remote.DispatchIssue] {
  @remote.restore_durable_coordinator_dispatch_record(journal, durable)
}

///|
#export_name("coordinatorDurableRevision")
pub fn coordinator_durable_revision(
  durable : @remote.DurableCoordinatorDispatchRecord,
) -> Int {
  @remote.durable_coordinator_dispatch_record_revision(durable)
}

///|
#export_name("coordinatorDurableDispatchCid")
pub fn coordinator_durable_dispatch_cid(
  durable : @remote.DurableCoordinatorDispatchRecord,
) -> String {
  @remote.durable_coordinator_dispatch_record_request_identity(durable)
}

///|
#export_name("coordinatorDurableRequest")
pub fn coordinator_durable_request(
  durable : @remote.DurableCoordinatorDispatchRecord,
) -> @remote.DispatchRequest {
  @remote.durable_coordinator_dispatch_record_request(durable)
}

///|
/// Project only the complete output triple admitted in the durable common
/// Coordinator record. This is physical evidence, not Result publication or
/// a read capability.
#export_name("coordinatorAcceptedSiteOutput")
pub fn coordinator_accepted_site_output(
  durable : @remote.DurableCoordinatorDispatchRecord,
) -> Result[Array[String]?, @remote.DispatchIssue] {
  match
    (
      @remote.durable_coordinator_dispatch_record_evidence(durable),
      @remote.durable_coordinator_dispatch_record_subject(durable),
      @remote.durable_coordinator_dispatch_record_measurement(durable),
    ) {
    (None, None, None) => Ok(None)
    (Some(evidence), Some(subject), Some(measurement)) => {
      let request = @remote.durable_coordinator_dispatch_record_request(durable)
      if !@remote.remote_managed_output_subject_matches_evidence(
          subject, evidence, request,
        ) ||
        !@remote.remote_managed_output_subject_matches_measurement(
          subject, measurement,
        ) {
        return Err(@remote.InvalidJournal)
      }
      let fields = [
        @remote.remote_execution_evidence_cid(evidence),
        @remote.remote_managed_output_measurement_cid(measurement),
      ]
      for field in @remote.remote_managed_output_subject_projection(subject) {
        fields.push(field)
      }
      Ok(Some(fields))
    }
    _ => Err(@remote.InvalidJournal)
  }
}

///|
/// A lost transport response is unknown, not failed or safe to resubmit
/// under a different dispatch identity.
#export_name("coordinatorPrepareUnknown")
pub fn coordinator_prepare_unknown(
  record : @remote.CoordinatorDispatchIntentRecord,
) -> Result[@remote.CoordinatorDispatchTransition, @remote.DispatchIssue] {
  @remote.prepare_coordinator_outcome_unknown(record)
}

///|
/// Site replies are admitted against the exact dispatch and reply operation.
#export_name("coordinatorAdmitResponseJson")
pub fn coordinator_admit_response_json(
  body : String,
  request : @remote.DispatchRequest,
  status_reply : Bool,
) -> Result[@remote.RemoteDispatchResponse, @remote.DispatchIssue] {
  @remote.admit_remote_dispatch_response_json(
    body,
    request,
    if status_reply {
      @remote.StatusReply
    } else {
      @remote.DispatchReply
    },
  )
}

///|
#export_name("coordinatorPrepareResponseObservation")
pub fn coordinator_prepare_response_observation(
  record : @remote.CoordinatorDispatchIntentRecord,
  response : @remote.RemoteDispatchResponse,
) -> Result[@remote.CoordinatorDispatchTransition, @remote.DispatchIssue] {
  @remote.prepare_coordinator_response_observation(record, response)
}

///|
#export_name("coordinatorTransitionExpectedRevision")
pub fn coordinator_transition_expected_revision(
  transition : @remote.CoordinatorDispatchTransition,
) -> Int {
  @remote.coordinator_dispatch_transition_expected_revision(transition)
}

///|
#export_name("coordinatorTransitionDurableJson")
pub fn coordinator_transition_durable_json(
  durable : @remote.DurableCoordinatorDispatchRecord,
  transition : @remote.CoordinatorDispatchTransition,
) -> Result[String, @remote.DispatchIssue] {
  @remote.coordinator_dispatch_transition_durable_json(durable, transition)
}

///|
/// Include the typed Site evidence accepted by the common protocol owner.
#export_name("coordinatorResponseDurableJson")
pub fn coordinator_response_durable_json(
  durable : @remote.DurableCoordinatorDispatchRecord,
  transition : @remote.CoordinatorDispatchTransition,
  response : @remote.RemoteDispatchResponse,
) -> Result[String, @remote.DispatchIssue] {
  @remote.coordinator_dispatch_transition_durable_json(
    durable,
    transition,
    evidence=@remote.remote_dispatch_response_evidence(response),
    subject=@remote.remote_dispatch_response_subject(response),
    measurement=@remote.remote_dispatch_response_measurement(response),
  )
}

///|
/// Called only after the next durable body was atomically persisted.
#export_name("coordinatorCommitTransition")
pub fn coordinator_commit_transition(
  transition : @remote.CoordinatorDispatchTransition,
) -> Result[Unit, @remote.DispatchIssue] {
  match @remote.commit_coordinator_dispatch_transition(transition, true) {
    Ok(_) => Ok(())
    Err(issue) => Err(issue)
  }
}

///|
#export_name("coordinatorRecordStateCodes")
pub fn coordinator_record_state_codes(
  record : @remote.CoordinatorDispatchIntentRecord,
) -> Array[String] {
  @remote.coordinator_dispatch_record_state_codes(record)
}

///|
/// Check the common owner's exact-send recovery condition. The environment
/// adapter must first query the authenticated Site and retain any uncertainty.
#export_name("coordinatorExactRetransmissionEligible")
pub fn coordinator_exact_retransmission_eligible(
  record : @remote.CoordinatorDispatchIntentRecord,
  request : @remote.DispatchRequest,
) -> Bool {
  @remote.coordinator_exact_retransmission_eligible(record, request)
}
