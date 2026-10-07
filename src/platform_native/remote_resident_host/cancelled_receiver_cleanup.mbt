///|
/// Recover the exact receiver committed before an undelivered consumer was
/// cancelled. The caller supplies the original checked edge and saved plan;
/// no replacement dispatch, borrow, Source acquisition or execution is issued.
/// The actual exclusive slot remains responsible for physical stop, and the
/// existing receiver Owner retains reservations until cleanup is confirmed.
pub fn prepare_resident_cancelled_receiver_cleanup(
  journal : @journal.Journal,
  site : @site.ExecutionSite,
  delegation : @resident.ResidentSiteDelegation,
  recorded : @host.ClientRecordedSourceCleanup,
  original_consumer : @remote.DispatchRequest,
  intent : @remote.RemoteRetainedInputIntent,
  plan : @remote.RemoteRetainedInputPlan,
  receiver_journal : @transfer_journal.Journal,
  receiver_root : @filesystem.Root,
  limits : @output.NativeRemoteStandardTransferBindingLimits,
  exclusive_current : () -> Bool,
) -> Result[
  () -> Result[Unit, ResidentStoppedRetainedCleanupIssue],
  ResidentStoppedRetainedCleanupIssue,
] {
  let producer = @remote.remote_retained_input_intent_request(intent)
  let current = () => {
    if !exclusive_current() {
      return false
    }
    for request in [producer, original_consumer] {
      let scope = @remote.dispatch_request_execution_scope(request)
      if scope[0] != @site.site_key(site) ||
        scope[1] != @site.site_generation(site).to_string() ||
        !@site.site_binding_current(site, @site.site_generation(site), scope[2]) ||
        @resident.check_resident_dispatch_delegation(
          delegation,
          request,
          @site.site_generation(site),
        )
        is Err(_) {
        return false
      }
    }
    true
  }
  if !current() {
    return Err(NotCurrent)
  }
  // This durable marker and the start claim share the journal transaction
  // boundary. A caller's AbortSignal or absent process is insufficient.
  match journal.cancellation_requested(original_consumer) {
    Ok(true) => ()
    Ok(false) => return Err(NotCurrent)
    Err(issue) => return Err(Host(Journal(issue)))
  }
  let cancelled = match journal.require(original_consumer) {
    Ok(value) => value
    Err(issue) => return Err(Host(Journal(issue)))
  }
  let observation = match journal.observation(producer) {
    Ok(value) => value
    Err(issue) => return Err(Host(Journal(issue)))
  }
  guard @journal.recovered_site_dispatch_evidence(observation) is Some(evidence) &&
    @journal.recovered_site_dispatch_subject(observation) is Some(subject) &&
    @journal.recovered_site_dispatch_measurement(observation)
    is Some(measurement) else {
    return Err(Host(Runtime(@runtime.CompletedRestorationPending)))
  }
  let request = @remote.remote_retained_input_plan_transfer(plan)
  let record = match receiver_journal.require(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let receipt = match receiver_journal.inspect_destination_receipt(request) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Transfer(@transfer_client.ReconciliationRequired))
    Err(issue) => return Err(Journal(issue))
  }
  let result = match
    @remote.prepare_remote_retained_input_result(plan, record, receipt) {
    Ok(value) => value
    Err(issue) => return Err(Host(Protocol(issue)))
  }
  let cleanup = match
    @host.prepare_recorded_client_retained_receiver_cleanup_from_plan(
      recorded,
      @journal.recovered_site_dispatch_record(observation),
      evidence,
      subject,
      measurement,
      intent,
      result,
      original_consumer,
      cancelled,
      limits.max_binding_bytes,
      limits.max_chunks,
      limits.max_manifest_bytes,
      limits.max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  if !current() {
    return Err(NotCurrent)
  }
  prepare_resident_retained_input_cleanup_retry(
    cleanup,
    receiver_journal,
    receiver_root,
    current,
    allow_unborrowed=true,
  )
}
