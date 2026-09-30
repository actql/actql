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
  /// The payload request names another publication Store than the Site's.
  OutputStoreRefused
  /// The output intent could not be kept durably; nothing touched the Store.
  OutputIntent(@journal.NativeRemoteJournalIssue)
  /// A kept output intent does not admit as one.
  OutputIntentInvalid
}

///|
/// Kill points for acceptance tests of output cleanup. `checkpoint` is
/// called with one of these names; production callers pass a no-op.
pub fn resident_output_checkpoints() -> Array[String] {
  ["before-intent", "after-intent", "payload-written", "sealed"]
}

///|
fn output_intent_body(
  attempt : String,
  dispatch_request_cid : String,
  payload_json : String,
) -> String {
  let fields : Map[String, Json] = {
    "attempt": Json::string(attempt),
    "dispatch_request_cid": Json::string(dispatch_request_cid),
    "payload_request": Json::string(payload_json),
    "version": Json::string("actql-resident-output-intent/0.1"),
  }
  Json::object(fields).stringify()
}

///|
/// The exact payload request an output intent names, admitted against its
/// key (the request identity).
fn output_intent_request(
  key : String,
  body : String,
) -> @payload.PublicationPayloadRequest? {
  let parsed = @json.parse(body) catch { _ => return None }
  guard parsed is Object(fields) &&
    fields.length() == 4 &&
    fields.get("version") is Some(String("actql-resident-output-intent/0.1")) &&
    fields.get("attempt") is Some(String(_)) &&
    fields.get("dispatch_request_cid") is Some(String(_)) &&
    fields.get("payload_request") is Some(String(payload_json)) else {
    return None
  }
  @payload.admit_publication_payload_request_json(payload_json, key).to_option()
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
/// The outcome of one output poll. `payload` is the exact publication request
/// whose payload may now exist in the Site's Store: it is set as soon as the
/// Store can hold anything for this output, and stays set whatever happened
/// afterwards, so the holder keeps the cleanup even when persisting, sending
/// or reporting failed.
pub(all) struct ResidentDelivery {
  payload : @payload.PublicationPayloadRequest?
  result : Result[@remote.RemoteOutputResult, ResidentOutputIssue]
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
  store_authority : String,
  max_chunk_bytes : Int,
  checkpoint : (String) -> Unit,
) -> ResidentDelivery {
  let (request, completion, _, plan) = match
    observed_output(
      executed, journal, coordinator_authority, site_key, site_generation, output,
    ) {
    Ok(value) => value
    Err(issue) => return { payload: None, result: Err(issue), }
  }
  let selected = @remote.remote_output_intent_projection(
    @remote.remote_poll_output_intent(output),
  )
  if selected.transfer_route != @transfer.DirectStream ||
    selected.transfer_origin != destination_origin {
    return { payload: None, result: Err(OutputRouteRefused), }
  }
  if @payload.publication_payload_request_store_authority(plan.payload) !=
    store_authority {
    return { payload: None, result: Err(OutputStoreRefused), }
  }
  // The exact payload request is kept durably, bound to its attempt, before
  // the Store can hold anything for it. Without a confirmed intent the Store
  // is not touched, so a holder that dies later still leaves its cleanup
  // findable.
  checkpoint("before-intent")
  let payload_json = match
    @payload.publication_payload_request_json(plan.payload) {
    Ok(value) => value
    Err(_) => return { payload: None, result: Err(OutputIntentInvalid), }
  }
  let attempt = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(issue) => return { payload: None, result: Err(OutputProtocol(issue)), }
  }
  match
    journal.retain_output_intent(
      @payload.publication_payload_request_identity(plan.payload),
      output_intent_body(
        attempt,
        @remote.dispatch_request_identity(request),
        payload_json,
      ),
    ) {
    Ok(_) => ()
    Err(issue) => return { payload: None, result: Err(OutputIntent(issue)), }
  }
  checkpoint("after-intent")
  // From here the Store may hold a payload for this exact request.
  let owned = Some(plan.payload)
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
          after_append=fn() { checkpoint("payload-written") },
        ) {
        Ok(value) => {
          checkpoint("sealed")
          value
        }
        Err(issue) =>
          return { payload: owned, result: Err(OutputPayload(issue)), }
      }
    Err(issue) =>
      return { payload: owned, result: Err(OutputPayloadStore(issue)), }
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
    Err(issue) => return { payload: owned, result: Err(OutputTransfer(issue)), }
  }
  {
    payload: owned,
    result: @remote.prepare_remote_output_result(
      output,
      plan.payload,
      payload.physical_digest,
      record,
    ).map_err(issue => OutputProtocol(issue)),
  }
}

///|
/// Whether a failed output still owns physical cleanup: an open payload
/// reader or writer, a Store recovery, or an unstopped Transfer source.
pub fn resident_output_cleanup_pending(issue : ResidentOutputIssue) -> Bool {
  match issue {
    OutputPayload(failure) =>
      @output.native_remote_standard_payload_failure_cleanup_pending(failure)
    OutputTransfer(@output.TransferSend(failure)) =>
      @transfer_client.transfer_send_failure_cleanup_pending(failure)
    _ => false
  }
}

///|
/// Retry only the physical cleanup a failed output retained. This never
/// repeats payload creation, Transfer, or execution. It is done when nothing
/// is left pending.
pub fn retry_resident_output_cleanup(issue : ResidentOutputIssue) -> Bool {
  match issue {
    OutputPayload(failure) =>
      ignore(
        @output.retry_native_remote_standard_payload_failure_cleanup(failure),
      )
    OutputTransfer(@output.TransferSend(failure)) =>
      ignore(@transfer_client.retry_transfer_send_failure_cleanup(failure))
    _ => ()
  }
  !resident_output_cleanup_pending(issue)
}

///|
/// Record that the cleanup of `request` is confirmed. Call only after
/// `reclaim_resident_payload` returned `Ok(true)` for it.
pub fn complete_resident_output_intent(
  journal : @journal.Journal,
  request : @payload.PublicationPayloadRequest,
) -> Result[Unit, ResidentOutputIssue] {
  journal
  .complete_output_intent(
    @payload.publication_payload_request_identity(request),
  )
  .map_err(issue => OutputIntent(issue))
}

///|
/// Reclaim the payloads of output intents whose holder is gone. The caller
/// must hold the Site's executor slot, which proves that no holder can still
/// write them. Each exact request is reclaimed through the existing Store
/// owner, and its intent is completed only after the Store confirmed it.
/// Returns how many intents are still pending; a failure leaves them pending
/// for a later call and never re-runs anything.
pub fn reclaim_resident_output_intents(
  journal : @journal.Journal,
  store : @publication_store.Store,
) -> Result[Int, ResidentOutputIssue] {
  let pending = match journal.pending_output_intents() {
    Ok(value) => value
    Err(issue) => return Err(OutputIntent(issue))
  }
  let mut remaining = 0
  let mut failure : ResidentOutputIssue? = None
  for intent in pending {
    let (key, body) = intent
    guard output_intent_request(key, body) is Some(request) else {
      // Kept, never dropped: an intent that cannot be read stays pending.
      remaining += 1
      if failure is None {
        failure = Some(OutputIntentInvalid)
      }
      continue
    }
    let done = match reclaim_resident_payload(store, request) {
      Ok(true) =>
        complete_resident_output_intent(journal, request).map(_ => true)
      Ok(false) => Ok(false)
      Err(issue) => Err(issue)
    }
    match done {
      Ok(true) => ()
      Ok(false) => remaining += 1
      Err(issue) => {
        remaining += 1
        if failure is None {
          failure = Some(issue)
        }
      }
    }
  }
  match failure {
    Some(issue) => Err(issue)
    None => Ok(remaining)
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
