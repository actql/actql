///|
/// Derive an internal producer's exact Transfer request from the Runtime's
/// admitted manifest. Planning opens no reader, reserves no capacity and grants
/// no execution. The Coordinator must save the admitted plan before handoff.
pub fn plan_resident_retained_input_transfer(
  runtime : @runtime.NativeRemoteRuntime,
  producer : @host.ClientRetainedInputProducer,
  intent : @remote.RemoteRetainedInputIntent,
  current : @host.ClientRetainedInputCurrent,
  site : @site.ExecutionSite,
) -> Result[@remote.RemoteRetainedInputPlan, ResidentRetainedTransferIssue] {
  match @host.validate_client_retained_input_intent(producer, intent) {
    Ok(_) => ()
    Err(issue) => return Err(Input(issue))
  }
  let dispatch = @host.client_retained_input_producer_dispatch(producer)
  let completion = match runtime.observed_completion(dispatch) {
    Ok(value) => value
    Err(issue) => return Err(Output(issue))
  }
  let evidence = @host.client_retained_input_producer_evidence(producer)
  if completion.evidence_cid != @remote.remote_execution_evidence_cid(evidence) {
    return Err(ForeignProducer)
  }
  let subject = @host.client_retained_input_producer_subject(producer)
  let projection = @remote.remote_managed_output_subject_projection(subject)
  let facts = match runtime.inspect_output_facts(dispatch, projection[1]) {
    Ok(value) => value
    Err(issue) => return Err(Output(issue))
  }
  let selected = @remote.remote_retained_input_intent_projection(intent)
  let scope = @remote.dispatch_request_execution_scope(dispatch)
  let generation = @site.site_generation(site)
  if scope[0] != @site.site_key(site) ||
    scope[1] != generation.to_string() ||
    !@site.site_binding_current(site, generation, scope[2]) {
    return Err(ForeignProducer)
  }
  let request = match
    @transfer.prepare_request(
      @remote.dispatch_request_journal_key(dispatch)[0],
      selected.transfer_attempt,
      @transfer.DirectStream,
      scope[0],
      generation,
      scope[0],
      generation,
      facts.material_generation,
      facts.physical_manifest,
      selected.transfer_max_bytes,
      selected.transfer_expires_unix_ms,
      selected.source_grant_cid,
      selected.destination_grant_cid,
      selected.route_capability_cid,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignProducer)
  }
  match
    @host.validate_client_retained_input_transfer_current(
      producer, request, current,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Input(issue))
  }
  match @host.validate_client_retained_input_intent(producer, intent) {
    Ok(_) => ()
    Err(issue) => return Err(Input(issue))
  }
  match
    @remote.prepare_remote_retained_input_plan(
      intent, subject, evidence, request,
    ) {
    Ok(value) => Ok(value)
    Err(_) => Err(ForeignProducer)
  }
}
