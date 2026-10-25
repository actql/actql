///|
/// An installed Host view of existing Account/Publication decisions. This is
/// not a new permission owner, raw disclosure grant, capacity reservation or
/// saved receipt. The installing Node adapter retains actual policy/clock and
/// Store custody behind selection_available; Program input cannot install it.
pub struct ClientModelRawCaptureRegistration {
  priv dispatch : ClientInferDispatchAdmission
  priv scope : @publication.BoundModelInvocationScope
  priv policy : @publication.BoundModelRawCapturePolicy
  priv authorization : @authorization.DispatchAuthorization
  priv selected_at : String
  priv available_until : String
  priv selection_available : () -> Bool
  priv current : () -> Result[
    (@authorization.AdmittedAccountConfiguration, String),
    ClientModelRawCaptureIssue,
  ]
}

///|
pub(all) enum ClientModelRawCaptureIssue {
  ForeignRun
  ForeignPolicy
  ForeignProfile
  UnavailableSelection
  Expired
  Authorization(@authorization.DispatchBindingIssue)
  Evidence(@publication.RunEvidenceValueIssue)
} derive(Eq, Debug)

///|
/// Project installed selection facts into the registered policy body. The
/// original Run/scope/task/data identities come from existing owners, never
/// Host-built evidence JSON. This issues no permission or persistence fact.
pub fn issue_client_model_raw_capture_policy(
  dispatch : ClientInferDispatchAdmission,
  scope : @publication.BoundModelInvocationScope,
  profile : @environment.ModelResponseProfile,
  installation : @environment.ModelResponseProfileInstallation,
  probability : @environment.DecisionProbabilityProfile?,
  store_authority_cid : String,
  retention : @publication.CapturedEffectDependencyBody,
  metadata : @publication.CapturedEffectDependencyBody,
  clock : @publication.CapturedEffectDependencyBody,
  data : @publication.CapturedEffectDependencyBody,
  selected_at : String,
  available_until : String,
  delete_by : String,
  extension_ceiling_at : String,
  metadata_delete_by : String,
) -> Result[@publication.BoundModelRawCapturePolicy, ClientModelRawCaptureIssue] {
  let boundary = @publication.model_invocation_scope_boundary(scope)
  let scope_cid = @publication.model_invocation_scope_cid(scope)
  let (_, run_cid, _) = @publication.model_invocation_scope_run(scope)
  let task = @environment.model_execution_task(dispatch.plan.execution)
  let task_cid = @environment.model_task_identity(task).2
  if run_cid != @publication.publication_contract_identity(dispatch.definition) ||
    dispatch.subject_cid != scope_cid ||
    dispatch.activation_context_cid != boundary.context_cid ||
    @publication.model_invocation_scope_prepared_cid(scope) !=
    @publication.run_evidence_value_identity(dispatch.compiled.prepared) ||
    !client_compiled_run_has_infer(dispatch.compiled, dispatch.plan) ||
    dispatch.plan.task.to_int64() != boundary.task_index ||
    dispatch.plan.barrier_cid != boundary.inference_barrier_cid ||
    boundary.resource != task_cid ||
    boundary.connection != @environment.model_task_connector(task) {
    return Err(ForeignRun)
  }
  if @environment.check_model_response_profile_binding(
      profile, task, installation, probability,
    )
    is Err(_) {
    return Err(ForeignProfile)
  }
  guard client_compiled_run_infer_observation_policy(dispatch.compiled)
    is Some(data_cid) &&
    @publication.captured_effect_dependency_body_cid(data) == data_cid else {
    return Err(ForeignPolicy)
  }
  let body = try {
    let writer = @encode.writer(8192, 128, 8)
    @encode.begin_object(writer)
    for
      (field, text) in [
        ("version", "actql-model-raw-capture-policy/0.1"),
        ("purpose", "model_raw_capture"),
        ("run_definition_cid", run_cid),
        ("scope_cid", scope_cid),
        ("model_task_cid", task_cid),
        (
          "response_profile_cid",
          @environment.model_response_profile_identity(profile),
        ),
        ("store_authority_cid", store_authority_cid),
        ("effective_data_policy_cid", data_cid),
        (
          "retention_contract_cid",
          @publication.captured_effect_dependency_body_cid(retention),
        ),
        (
          "metadata_retention_policy_cid",
          @publication.captured_effect_dependency_body_cid(metadata),
        ),
        (
          "clock_contract_cid",
          @publication.captured_effect_dependency_body_cid(clock),
        ),
        ("selected_at", selected_at),
        ("available_until", available_until),
        ("delete_by", delete_by),
        ("extension_ceiling_at", extension_ceiling_at),
        ("metadata_delete_by", metadata_delete_by),
      ] {
      @encode.key(writer, field)
      @encode.string_value(writer, text)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Evidence(@publication.RunEvidenceEncoding))
  }
  let policy = match
    @publication.seal_run_evidence_value(
      "model_raw_capture_policy", body, 8192, 128, 8,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  @publication.bind_model_raw_capture_policy(
    policy, retention, metadata, clock, data,
  ).map_err(issue => Evidence(issue))
}

///|
/// Bind a distinct capture tuple to the original scope and activation. The
/// four actual policy originals have already been integrity-admitted by the
/// Publication owner; selection_available attests their installed applicability,
/// trusted clock and original Store availability, not plausible CID strings.
pub fn register_client_model_raw_capture(
  dispatch : ClientInferDispatchAdmission,
  scope : @publication.BoundModelInvocationScope,
  policy : @publication.BoundModelRawCapturePolicy,
  profile : @environment.ModelResponseProfile,
  installation : @environment.ModelResponseProfileInstallation,
  probability : @environment.DecisionProbabilityProfile?,
  current : @authorization.AdmittedAccountConfiguration,
  at : String,
  store_authority_cid : String,
  selection_available : () -> Bool,
  observe_current : () -> Result[
    (@authorization.AdmittedAccountConfiguration, String),
    ClientModelRawCaptureIssue,
  ],
  delegated_action? : @authorization.RuntimeAction? = None,
) -> Result[ClientModelRawCaptureRegistration, ClientModelRawCaptureIssue] {
  let compiled = dispatch.compiled
  let boundary = @publication.model_invocation_scope_boundary(scope)
  let scope_cid = @publication.model_invocation_scope_cid(scope)
  let (_, run_cid, _) = @publication.model_invocation_scope_run(scope)
  if run_cid != @publication.publication_contract_identity(dispatch.definition) ||
    dispatch.subject_cid != scope_cid ||
    dispatch.activation_context_cid != boundary.context_cid ||
    @publication.model_invocation_scope_prepared_cid(scope) !=
    @publication.run_evidence_value_identity(compiled.prepared) ||
    !client_compiled_run_has_infer(compiled, dispatch.plan) ||
    dispatch.plan.task.to_int64() != boundary.task_index ||
    dispatch.plan.barrier_cid != boundary.inference_barrier_cid ||
    boundary.account_id != current.account_id() ||
    boundary.configuration_cid != current.configuration_cid() {
    return Err(ForeignRun)
  }
  let task = @environment.model_execution_task(dispatch.plan.execution)
  if @environment.check_model_response_profile_binding(
      profile, task, installation, probability,
    )
    is Err(_) {
    return Err(ForeignProfile)
  }
  let original = @publication.model_raw_capture_policy_value(policy)
  guard parse_plan_identity_value(
      @publication.run_evidence_value_json(original),
      8192,
      128,
      8,
    )
    is Some(body) &&
    infer_scope_string(body, "selected_at") is Some(selected_at) &&
    infer_scope_string(body, "available_until") is Some(available_until) &&
    client_compiled_run_infer_observation_policy(compiled) is Some(data_policy) else {
    return Err(ForeignPolicy)
  }
  let connector = @environment.model_task_connector(task)
  let task_cid = @environment.model_task_identity(task).2
  if boundary.connection != connector || boundary.resource != task_cid {
    return Err(ForeignRun)
  }
  for
    (field, expected) in [
      ("run_definition_cid", run_cid),
      ("scope_cid", scope_cid),
      ("model_task_cid", task_cid),
      (
        "response_profile_cid",
        @environment.model_response_profile_identity(profile),
      ),
      ("effective_data_policy_cid", data_policy),
      ("store_authority_cid", store_authority_cid),
    ] {
    if infer_scope_string(body, field) != Some(expected) {
      return Err(ForeignPolicy)
    }
  }
  let authorization = match
    @authorization.bind_dispatch_authorization(
      current,
      {
        principal: boundary.principal,
        connection: connector,
        resource: task_cid,
        operation: "model_raw_capture",
      },
      @authorization.Activation,
      scope_cid,
      boundary.context_cid,
      delegated_action~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Authorization(issue))
  }
  let registration : ClientModelRawCaptureRegistration = {
    dispatch,
    scope,
    policy,
    authorization,
    selected_at,
    available_until,
    selection_available,
    current: observe_current,
  }
  // Re-read the actual current observation. The at argument is an original
  // Host observation, not permission to reset any fixed retention deadline.
  if !@publication.trusted_clock_not_before(Some(selected_at), at) ||
    at >= available_until {
    return Err(Expired)
  }
  check_client_model_raw_capture_current(registration).map(_ => registration)
}

///|
/// Call outside indivisible commit boundaries before saving and before receipt
/// adoption. A failure after persistence retains custody/unknown for existing
/// reconciliation; it never means absent raw bytes or permits another send.
pub fn check_client_model_raw_capture_current(
  value : ClientModelRawCaptureRegistration,
) -> Result[Unit, ClientModelRawCaptureIssue] {
  let (current, at) = match (value.current)() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !@publication.trusted_clock_not_before(Some(value.selected_at), at) ||
    at >= value.available_until ||
    !@publication.run_publication_start_current(
      value.dispatch.compiled.admission,
      value.dispatch.definition,
      at,
    ) {
    return Err(Expired)
  }
  let boundary = @publication.model_invocation_scope_boundary(value.scope)
  if !@authorization.dispatch_authorization_matches(
      value.authorization,
      current,
      @authorization.dispatch_authorization_tuple(value.authorization),
      @authorization.Activation,
      @publication.model_invocation_scope_cid(value.scope),
      boundary.context_cid,
    ) {
    return Err(Authorization(@authorization.ForeignDecision))
  }
  if !(value.selection_available)() {
    return Err(UnavailableSelection)
  }
  Ok(())
}

///|
/// Only the original Model caller may adopt this view. Equal CID strings from
/// another compiled owner are not installation provenance or a capture grant.
pub fn client_model_raw_capture_matches(
  value : ClientModelRawCaptureRegistration,
  dispatch : ClientInferDispatchAdmission,
  scope : @publication.BoundModelInvocationScope,
) -> Bool {
  physical_equal(value.dispatch, dispatch) && physical_equal(value.scope, scope)
}

///|
/// Exact originals for the installed Store port's bounded readback check.
/// This projection grants no read or disclosure permission.
pub fn client_model_raw_capture_policy(
  value : ClientModelRawCaptureRegistration,
) -> @publication.BoundModelRawCapturePolicy {
  value.policy
}

///|
/// Only binds already observed raw facts to the selected original scope. No
/// transport, persistence, completion or disclosure fact is issued here.
pub fn bind_client_model_raw_response(
  value : ClientModelRawCaptureRegistration,
  response : @publication.RunEvidenceValue,
  ordinal : Int,
  attempt : @publication.RunEvidenceValue,
  authority : @publication.RunEvidenceValue,
) -> Result[@publication.BoundModelRawResponse, ClientModelRawCaptureIssue] {
  match check_client_model_raw_capture_current(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  @publication.bind_model_raw_response(
    value.policy,
    response,
    value.scope,
    ordinal,
    attempt,
    authority,
  ).map_err(issue => Evidence(issue))
}
