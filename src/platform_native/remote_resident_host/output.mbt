///|
pub(all) enum ResidentOutputIssue {
  OutputForeign
  OutputUnavailable
  /// Only the direct route to the Site's configured destination is used.
  OutputRouteRefused
  OutputJournal(@journal.NativeRemoteJournalIssue)
  OutputRuntime(@runtime.NativeRemoteRuntimeIssue)
  OutputPlan(@output.NativeRemoteObservedOutputPlanIssue)
  OutputPayloadStore(@publication_store.NativePublicationStoreIssue)
  OutputPayload(@output.NativeRemoteStandardPayloadFailure)
  OutputTransfer(@output.NativeRemoteStandardSiteComponentIssue)
  OutputProtocol(@remote.DispatchIssue)
}

///|
/// The exact output facts, subject and completion of one retained output,
/// selected by the durable Site observation of its dispatch.
fn observed_output(
  executed : ResidentExecuted,
  journal : @journal.Journal,
  coordinator_authority : String,
  site_key : String,
  site_generation : Int,
  output : @remote.RemotePollOutput,
) -> Result[
  (
    @remote.DispatchRequest,
    @runtime.NativeRemoteRuntimeCompletion,
    @remote.RemoteManagedOutputSubject,
    @output.NativeRemoteObservedOutputPlan,
  ),
  ResidentOutputIssue,
] {
  let runtime = executed.runtime
  let request = @remote.remote_poll_output_request(output)
  let intent = @remote.remote_poll_output_intent(output)
  let selected = @remote.remote_output_intent_projection(intent)
  // The output belongs to this attempt, this Coordinator and this Result.
  if !@remote.remote_output_intent_matches_dispatch(intent, request) ||
    @remote.dispatch_request_identity(request) !=
    @remote.dispatch_request_identity(executed.request) ||
    selected.coordinator_authority != coordinator_authority ||
    selected.result_definition_cid != executed.result_definition_cid {
    return Err(OutputForeign)
  }
  let observed = match journal.observation(request) {
    Ok(value) => value
    Err(issue) => return Err(OutputJournal(issue))
  }
  guard @journal.recovered_site_dispatch_subject(observed) is Some(subject) else {
    return Err(OutputUnavailable)
  }
  let completion = match runtime.observed_completion(request) {
    Ok(value) => value
    Err(issue) => return Err(OutputRuntime(issue))
  }
  if !@remote.remote_managed_output_subject_matches_dispatch(subject, request) ||
    @remote.remote_managed_output_subject_cid(subject) != completion.subject_cid {
    return Err(OutputUnavailable)
  }
  let subject_fields = @remote.remote_managed_output_subject_projection(subject)
  if subject_fields.length() < 2 {
    return Err(OutputUnavailable)
  }
  let facts = match runtime.inspect_output_facts(request, subject_fields[1]) {
    Ok(value) => value
    Err(issue) => return Err(OutputRuntime(issue))
  }
  let plan = match
    @output.prepare_native_remote_observed_output_plan(
      site_key,
      site_generation,
      facts,
      {
        store_authority_cid: selected.store_authority_cid,
        publication_attempt_cid: selected.publication_attempt_cid,
        result_definition_cid: selected.result_definition_cid,
        ordering_evidence_cid: selected.ordering_evidence_cid,
        coordinator_authority: selected.coordinator_authority,
        transfer_attempt: selected.transfer_attempt,
        transfer_route: selected.transfer_route,
        destination_site_key: selected.destination_site_key,
        destination_site_generation: selected.destination_site_generation,
        transfer_max_bytes: selected.transfer_max_bytes,
        transfer_expires_unix_ms: selected.transfer_expires_unix_ms,
        source_grant_cid: selected.source_grant_cid,
        destination_grant_cid: selected.destination_grant_cid,
        route_capability_cid: selected.route_capability_cid,
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(OutputPlan(issue))
  }
  Ok((request, completion, subject, plan))
}

///|
/// Derive the publication and Transfer requests for a Coordinator's output
/// planning poll from the holder's retained output. No payload writer or
/// Transfer starts.
pub fn plan_resident_output(
  executed : ResidentExecuted,
  journal : @journal.Journal,
  coordinator_authority : String,
  site_key : String,
  site_generation : Int,
  output : @remote.RemotePollOutput,
) -> Result[@remote.RemoteOutputPlan, ResidentOutputIssue] {
  match
    observed_output(
      executed, journal, coordinator_authority, site_key, site_generation, output,
    ) {
    Ok((_, _, subject, plan)) =>
      @remote.prepare_remote_output_plan(
        output,
        subject,
        plan.payload,
        plan.transfer,
      ).map_err(issue => OutputProtocol(issue))
    Err(issue) => Err(issue)
  }
}

///|
/// Publish the holder's retained output for a Coordinator's output poll:
/// the payload is kept in the Site's publication Store (an existing payload
/// for the same request is reconciled, never written twice), then sent on
/// the direct route to the Site's configured destination only. The result is
/// the observation the Coordinator admits; it does not publish a Named Result
/// by itself.
pub fn deliver_resident_output(
  executed : ResidentExecuted,
  journal : @journal.Journal,
  coordinator_authority : String,
  site_key : String,
  site_generation : Int,
  output : @remote.RemotePollOutput,
  store : @publication_store.Store,
  transfer_client : @http.Client,
  transfer_journal : @transfer_journal.Journal,
  destination_origin : String,
  max_chunk_bytes : Int,
) -> Result[
  (@remote.RemoteOutputResult, @payload.PublicationPayloadRequest),
  ResidentOutputIssue,
] {
  let (request, completion, _, plan) = match
    observed_output(
      executed, journal, coordinator_authority, site_key, site_generation, output,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let selected = @remote.remote_output_intent_projection(
    @remote.remote_poll_output_intent(output),
  )
  if selected.transfer_route != @transfer.DirectStream ||
    selected.transfer_origin != destination_origin {
    return Err(OutputRouteRefused)
  }
  let payload = match store.reconcile_payload(plan.payload) {
    Ok(Some(value)) => value
    Ok(None) =>
      match
        @output.persist_native_remote_observed_output_payload(
          executed.runtime,
          journal,
          request,
          completion,
          plan.payload,
          store,
          max_chunk_bytes,
        ) {
        Ok(value) => value
        Err(issue) => return Err(OutputPayload(issue))
      }
    Err(issue) => return Err(OutputPayloadStore(issue))
  }
  let record = match
    @output.send_native_remote_observed_output_direct(
      executed.runtime,
      journal,
      transfer_client,
      transfer_journal,
      destination_origin,
      request,
      completion,
      plan.transfer,
      max_chunk_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(OutputTransfer(issue))
  }
  // The payload kept in the Site's Store is returned with the result: its
  // owner must reclaim it when the output is released.
  match
    @remote.prepare_remote_output_result(
      output,
      plan.payload,
      payload.physical_digest,
      record,
    ) {
    Ok(result) => Ok((result, plan.payload))
    Err(issue) => Err(OutputProtocol(issue))
  }
}

///|
/// Reclaim one payload this holder kept in the Site's publication Store for
/// its output. A payload already reclaimed is done; a failure leaves the
/// exact cleanup to be retried by the caller.
pub fn reclaim_resident_payload(
  store : @publication_store.Store,
  request : @payload.PublicationPayloadRequest,
) -> Result[Bool, ResidentOutputIssue] {
  let owner = match store.acquire_payload_cleanup(request) {
    Ok(value) => value
    Err(@publication_store.Database(@sqlite.NotFound)) => return Ok(true)
    Err(issue) => return Err(OutputPayloadStore(issue))
  }
  match owner.retry() {
    Ok(_) => Ok(!owner.pending())
    Err(issue) => Err(OutputPayloadStore(issue))
  }
}
