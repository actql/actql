///|
/// Admit only the producer's saved materials and original publication evidence
/// before selecting its outgoing cleanup responsibility. An expired execution
/// lifetime does not create new use authority or block cleanup-only admission.
pub fn prepare_resident_saved_cancelled_receiver_cleanup(
  journal : @journal.Journal,
  admission : ResidentRunAdmission,
  original_publication : @publication.RecordedRunPublication,
  site : @site.ExecutionSite,
  delegation : @resident.ResidentSiteDelegation,
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
  if !exclusive_current() {
    return Err(NotCurrent)
  }
  let producer = @remote.remote_retained_input_intent_request(intent)
  guard @remote.dispatch_request_attempt_identity(producer) is Ok(attempt) else {
    return Err(Host(EnvelopeMissing))
  }
  let wire = match journal.dispatch_envelope(attempt) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Host(EnvelopeMissing))
    Err(issue) => return Err(Host(Journal(issue)))
  }
  guard @remote.admit_remote_poll_dispatch_json(wire) is Ok(dispatch) &&
    @remote.dispatch_request_identity(
      @remote.remote_poll_dispatch_request(dispatch),
    ) ==
    @remote.dispatch_request_identity(producer) &&
    @remote.remote_poll_dispatch_run_materials(dispatch) is Some(materials) &&
    admission.source is Some((source_ref, source_contract)) else {
    return Err(Host(EnvelopeMissing))
  }
  let graph = match
    @host.admit_recorded_client_source_cleanup_graph(
      materials,
      @remote.dispatch_request_task_scope(producer).0,
      original_publication,
      admission.expressions,
      admission.operations,
      admission.limits,
      source_ref,
      source_contract,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  if !@host.recorded_client_source_cleanup_matches_producer(
      graph,
      producer,
      @remote.remote_poll_dispatch_input_binding(dispatch),
      source_ref,
      source_contract,
    ) {
    return Err(Host(Refused(@resident.ForeignSource)))
  }
  prepare_resident_cancelled_receiver_cleanup(
    journal, site, delegation, graph, original_consumer, intent, plan, receiver_journal,
    receiver_root, limits, exclusive_current,
  )
}
