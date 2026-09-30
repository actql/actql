///|
/// Internal JS bridge for the physical Client request journal. A handle is never
/// serialized as a wire credential; retained fields are rechecked by MoonBit.
#export_name("clientRequestAdmitRecord")
pub fn client_request_admit_record(
  authority_scope_cid : String,
  caller_request_id : String,
  program_definition_cid : String,
  parameter_values_cid : String,
  caller_input_intent_cid : String,
  logical_request_scope_cid : String,
  intent_fingerprint_cid : String,
) -> @publication_host.ClientRequestIdentity? {
  match
    @publication_host.admit_client_request_identity_record(
      authority_scope_cid, caller_request_id, program_definition_cid, parameter_values_cid,
      caller_input_intent_cid, logical_request_scope_cid, intent_fingerprint_cid,
    ) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
#export_name("clientRequestAuthorityScopeCid")
pub fn client_request_authority_scope_cid(
  value : @publication_host.ClientRequestIdentity,
) -> String {
  @publication_host.client_request_authority_scope_cid(value)
}

///|
#export_name("clientRequestCallerId")
pub fn client_request_caller_id(
  value : @publication_host.ClientRequestIdentity,
) -> String {
  @publication_host.client_request_caller_id(value)
}

///|
#export_name("clientRequestScopeCid")
pub fn client_request_scope_cid(
  value : @publication_host.ClientRequestIdentity,
) -> String {
  @publication_host.client_request_scope_cid(value)
}

///|
#export_name("clientRequestLogicalScope")
pub fn client_request_logical_scope(
  value : @publication_host.ClientRequestIdentity,
) -> @effect.LogicalRequestScope {
  @publication_host.client_request_logical_scope(value)
}

///|
#export_name("clientProgramEffectRequestScope")
pub fn client_program_effect_request_scope(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> @effect.LogicalRequestScope? {
  match
    @publication_host.prepared_client_effect_request_scope(prepared, request) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
#export_name("clientRequestIntentCid")
pub fn client_request_intent_cid(
  value : @publication_host.ClientRequestIdentity,
) -> String {
  @publication_host.client_request_intent_cid(value)
}

///|
#export_name("clientRequestProgramCid")
pub fn client_request_program_cid(
  value : @publication_host.ClientRequestIdentity,
) -> String {
  @publication_host.client_request_program_cid(value)
}

///|
#export_name("clientRequestParametersCid")
pub fn client_request_parameters_cid(
  value : @publication_host.ClientRequestIdentity,
) -> String {
  @publication_host.client_request_parameters_cid(value)
}

///|
#export_name("clientRequestInputCid")
pub fn client_request_input_cid(
  value : @publication_host.ClientRequestIdentity,
) -> String {
  @publication_host.client_request_input_cid(value)
}

///|
/// The physical journal may branch only on this common semantic decision.
#export_name("clientRequestRelation")
pub fn client_request_relation(
  requested : @publication_host.ClientRequestIdentity,
  retained : @publication_host.ClientRequestIdentity,
) -> Int {
  match
    @publication_host.client_request_identity_relation(requested, retained) {
    DifferentRequest => 0
    SameRequest => 1
    ChangedIntent => 2
  }
}

///|
/// In-process decision for one durable Run start. The physical journal must
/// reserve dispatch atomically before opening the task; code 1 never starts
/// another Compute, including after response loss or process restart.
#export_name("clientRunStartAction")
pub fn client_run_start_action(
  requested : @publication_host.ClientRequestIdentity,
  retained : @publication_host.ClientRequestIdentity,
  run_definition : @publication.PublicationContract,
  retained_run_definition_cid : String,
  dispatch_reserved : Bool,
  current_authorization : Bool,
) -> Int {
  match
    @publication_host.prepare_client_run_start(
      requested, retained, run_definition, retained_run_definition_cid, dispatch_reserved,
      current_authorization,
    ) {
    Ok(ReserveDispatch) => 0
    Ok(ReconcileReservedDispatch) => 1
    Err(DifferentRequest) => 2
    Err(ChangedIntent) => 3
    Err(ForeignRunDefinition) => 4
    Err(AuthorizationDenied) => 5
  }
}

///|
/// Return 1 only when the shared owner permits a durable physical-start
/// claim for this exact request. Code 0 keeps an uncertain Run in reconcile.
#export_name("clientRunPhysicalStartAction")
pub fn client_run_physical_start_action(
  requested : @publication_host.ClientRequestIdentity,
  retained : @publication_host.ClientRequestIdentity,
  run_definition : @publication.PublicationContract,
  retained_run_definition_cid : String,
  dispatch_reserved : Bool,
  physically_unstarted : Bool,
  current_authorization : Bool,
) -> Int {
  match
    @publication_host.prepare_client_run_physical_start(
      requested, retained, run_definition, retained_run_definition_cid, dispatch_reserved,
      physically_unstarted, current_authorization,
    ) {
    Ok(true) => 1
    Ok(false) => 0
    Err(DifferentRequest) => 2
    Err(ChangedIntent) => 3
    Err(ForeignRunDefinition) => 4
    Err(AuthorizationDenied) => 5
  }
}

///|
/// Return 1 only when the shared owner permits a durable physical-start
/// claim for this exact request. Code 0 keeps an uncertain Run in reconcile.
#export_name("clientRunPhysicalStartWithCancellationAction")
pub fn client_run_physical_start_with_cancellation_action(
  requested : @publication_host.ClientRequestIdentity,
  retained : @publication_host.ClientRequestIdentity,
  run_definition : @publication.PublicationContract,
  retained_run_definition_cid : String,
  dispatch_reserved : Bool,
  physically_unstarted : Bool,
  current_authorization : Bool,
  cancellation_requested : Bool,
) -> Int {
  match
    @publication_host.prepare_client_run_physical_start(
      requested,
      retained,
      run_definition,
      retained_run_definition_cid,
      dispatch_reserved,
      physically_unstarted,
      current_authorization,
      cancellation_requested~,
    ) {
    Ok(true) => 1
    Ok(false) => 0
    Err(DifferentRequest) => 2
    Err(ChangedIntent) => 3
    Err(ForeignRunDefinition) => 4
    Err(AuthorizationDenied) => 5
  }
}

///|
#export_name("clientRunCancellationAction")
pub fn client_run_cancellation_action(
  run_definition : @publication.PublicationContract,
  retained_run_definition_cid : String,
  current_authorization : Bool,
  terminal_observed : Bool,
  cancellation_requested : Bool,
) -> Int {
  match
    @publication_host.prepare_client_run_cancellation(
      run_definition, retained_run_definition_cid, current_authorization, terminal_observed,
      cancellation_requested,
    ) {
    Ok(AcceptCancellation) => 0
    Ok(AlreadyRequested) => 1
    Ok(AlreadyTerminal) => 2
    Err(_) => -1
  }
}
