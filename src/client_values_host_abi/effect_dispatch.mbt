///|
/// Original caller scope only. Source permission and Effect approval remain
/// current decisions of their existing Host owners, not this identity issuer.
#export_name("clientValuesHostEffectRequestIdentity")
pub fn client_values_host_effect_request_identity(
  prepared : @host.PreparedClientEffectComputation,
  authority_scope_cid : String,
  request_id : String,
) -> Result[@host.ClientRequestIdentity, @host.ClientRequestIdentityIssue] {
  @host.prepare_client_effect_request_identity(
    prepared,
    authority_scope_cid,
    request_id,
    @host.source_free_caller_input_intent_cid(),
  )
}

///|
#export_name("clientValuesHostEffectSourceInputBinding")
pub fn client_values_host_effect_source_input_binding(
  compilation : @host.ClientEffectCompilation,
  request : @host.ClientRequestIdentity?,
) -> Result[String, @host.ClientEffectSourceDispatchIssue] {
  @host.prepare_client_effect_source_input_binding(compilation, request~).map(
    @remote.remote_input_binding_body,
  )
}

///|
#export_name("clientValuesHostPrepareEffectSourceDispatch")
pub fn client_values_host_prepare_effect_source_dispatch(
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  request : @host.ClientRequestIdentity,
  task_attempt : Int,
  dispatch_id : String,
  site_key : String,
  site_generation : Int,
  runtime_bundle_cid : String,
  connector_registration : String,
  connector_revision : String,
  strategy_revision : String,
  obligations_cid : String,
  budget_cid : String,
  evidence_issuer_capability_cid : String,
  grant_cid : String,
) -> Result[@remote.DispatchRequest, @host.ClientEffectSourceDispatchIssue] {
  @host.prepare_client_effect_source_dispatch(
    allowed,
    definition,
    request,
    task_attempt,
    dispatch_id,
    {
      site_key,
      site_generation,
      runtime_bundle_cid,
      connector_registration,
      connector_revision,
      strategy_revision,
      obligations_cid,
      budget_cid,
      evidence_issuer_capability_cid,
      grant_cid,
    },
  )
}

///|
#export_name("clientValuesHostEffectRetainedInputEdge")
pub fn client_values_host_effect_retained_input_edge(
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
) -> Result[@host.ClientRetainedInputEdge, @host.ClientEffectRetainedInputIssue] {
  @host.prepare_client_effect_retained_input_edge(allowed, definition)
}

///|
/// Reuse the ordinary replayable receiver input and current Transfer ports.
/// The original Effect owner selects its exact checked consumer, not the Host.
#export_name("clientValuesHostPrepareEffectRetainedTaskDispatch")
pub fn client_values_host_prepare_effect_retained_task_dispatch(
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  request : @host.ClientRequestIdentity,
  task_attempt : Int,
  dispatch_id : String,
  site_key : String,
  site_generation : Int,
  runtime_bundle_cid : String,
  connector_registration : String,
  connector_revision : String,
  strategy_revision : String,
  obligations_cid : String,
  budget_cid : String,
  evidence_issuer_capability_cid : String,
  grant_cid : String,
  value : ClientValuesHostRetainedTaskInput,
) -> Result[@remote.DispatchRequest, @host.ClientEffectRetainedInputIssue] {
  let input = match client_host_retained_transfer(value) {
    Ok(value) => value
    Err(issue) => return Err(@host.Input(issue))
  }
  let dispatch = match
    @host.prepare_client_effect_retained_task_dispatch(
      allowed,
      definition,
      request,
      task_attempt,
      dispatch_id,
      {
        site_key,
        site_generation,
        runtime_bundle_cid,
        connector_registration,
        connector_revision,
        strategy_revision,
        obligations_cid,
        budget_cid,
        evidence_issuer_capability_cid,
        grant_cid,
      },
      input,
      value.current,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // An authorization callback may have changed the durable destination.
  match client_host_retained_transfer(value) {
    Ok(_) => Ok(dispatch)
    Err(issue) => Err(@host.Input(issue))
  }
}
