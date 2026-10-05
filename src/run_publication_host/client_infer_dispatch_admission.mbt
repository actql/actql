///|
/// References an existing checked Run and account decision. This does not
/// authorize media, regions or classification that the Host has not admitted.
pub struct ClientInferDispatchAdmission {
  compiled : ClientCompiledRun
  definition : @publication.PublicationContract
  authorization : @authorization.DispatchAuthorization
  invocation_scope : @publication.BoundModelInvocationScope?
  evidence : @publication.RunEvidenceValue
  current : () -> Result[
    (@authorization.AdmittedAccountConfiguration, String),
    ClientInferDispatchIssue,
  ]
}

///|
pub(all) enum ClientInferDispatchIssue {
  ForeignRun
  Expired
  Authorization(@authorization.DispatchBindingIssue)
  Evidence(@publication.RunEvidenceValueIssue)
  Encoding
} derive(Eq, Debug)

///|
pub fn issue_client_infer_dispatch_admission(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  current : @authorization.AdmittedAccountConfiguration,
  principal : String,
  at : String,
  delegated_action? : @authorization.RuntimeAction? = None,
  invocation_scope? : @publication.BoundModelInvocationScope? = None,
  observe_current~ : () -> Result[
    (@authorization.AdmittedAccountConfiguration, String),
    ClientInferDispatchIssue,
  ],
) -> Result[ClientInferDispatchAdmission, ClientInferDispatchIssue] {
  guard client_compiled_run_infer(compiled) is Some(plan) &&
    check_client_compiled_run_definition(compiled, definition) is Ok(_) else {
    return Err(ForeignRun)
  }
  if !@publication.run_publication_start_current(
      compiled.admission,
      definition,
      at,
    ) {
    return Err(Expired)
  }
  let task = @environment.model_execution_task(plan.execution)
  let context_cid = @publication.run_publication_execution_context(
    compiled.admission,
  )
  let policy_cid = @publication.run_publication_host_policy(compiled.admission)
  let tuple : @authorization.AccessTuple = {
    principal,
    connection: @environment.model_task_connector(task),
    resource: @environment.model_task_identity(task).2,
    operation: "infer",
  }
  let subject_cid = match invocation_scope {
    None => plan.request_cid
    Some(scope) => {
      let (_, run_cid, _) = @publication.model_invocation_scope_run(scope)
      let expected = @publication.model_invocation_scope_boundary(scope)
      if run_cid != @publication.publication_contract_identity(definition) ||
        @publication.model_invocation_scope_prepared_cid(scope) !=
        @publication.run_evidence_value_identity(compiled.prepared) ||
        expected.task_index != plan.task.to_int64() ||
        expected.inference_barrier_cid != plan.barrier_cid ||
        expected.account_id != current.account_id() ||
        expected.configuration_cid != current.configuration_cid() ||
        expected.principal != principal ||
        expected.connection != tuple.connection ||
        expected.resource != tuple.resource ||
        expected.context_cid != context_cid {
        return Err(ForeignRun)
      }
      for index in 0..<@publication.model_invocation_scope_slots(scope).length() {
        guard @publication.model_invocation_scope_slot(scope, index)
          is Some((_, task_cid, request_cid)) &&
          task_cid == tuple.resource &&
          request_cid == plan.request_cid else {
          return Err(ForeignRun)
        }
      }
      @publication.model_invocation_scope_cid(scope)
    }
  }
  let authorization = match
    @authorization.bind_dispatch_authorization(
      current,
      tuple,
      @authorization.Activation,
      subject_cid,
      context_cid,
      delegated_action~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Authorization(issue))
  }
  let basis = @authorization.dispatch_authorization_basis(authorization)
  let (entry, kind, authority, claims) = match basis {
    @authorization.AccountAllow(entry) => (entry, "account_allow", None, [])
    @authorization.HostPermit(subject, authority, claims) =>
      (subject.entry_id, "host_permit", Some(authority), claims)
  }
  if invocation_scope is Some(scope) &&
    (
      @publication.model_invocation_scope_boundary(scope).entry_id != entry ||
      (kind == "host_permit" && !claims.contains("invocation_scope_approved"))
    ) {
    return Err(ForeignRun)
  }
  try {
    let writer = @encode.writer(16384, 256, 8)
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("version", "actql-model-dispatch-authority/0.1"),
        (
          "program_definition_cid",
          prepared_client_identity(compiled.owner).program_definition_cid,
        ),
        (
          "run_definition_cid",
          @publication.publication_contract_identity(definition),
        ),
        (
          "run_authorization_cid",
          @publication.run_evidence_value_identity(compiled.authorization),
        ),
        ("account_configuration_cid", current.configuration_cid()),
        ("model_task_cid", tuple.resource),
        ("fixed_request_cid", plan.request_cid),
        ("execution_context_cid", context_cid),
        ("host_policy_cid", policy_cid),
        ("principal", principal),
        ("connection", tuple.connection),
        ("resource", tuple.resource),
        ("operation", "infer"),
        ("entry_id", entry),
        ("basis", kind),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    // Preserve ordinary unscoped originals. A scoped send names its actual
    // typed scope; the fixed request remains a different identity field.
    if invocation_scope is Some(scope) {
      @encode.key(writer, "model_invocation_scope_cid")
      @encode.string_value(
        writer,
        @publication.model_invocation_scope_cid(scope),
      )
    }
    @encode.key(writer, "answering_authority")
    match authority {
      Some(value) => @encode.string_value(writer, value)
      None => @encode.null_value(writer)
    }
    @encode.key(writer, "satisfied_claims")
    @encode.begin_array(writer)
    for claim in claims {
      @encode.string_value(writer, claim)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    let evidence = match
      @publication.seal_run_evidence_value(
        "model_dispatch_authority",
        @encode.finish(writer),
        16384,
        256,
        8,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Evidence(issue))
    }
    Ok({
      compiled,
      definition,
      authorization,
      invocation_scope,
      evidence,
      current: observe_current,
    })
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// The physical provider boundary re-reads environment observations after
/// bounded input preparation. Changed account policy cannot reuse a permit.
pub fn check_client_infer_dispatch_current(
  value : ClientInferDispatchAdmission,
) -> Result[Unit, ClientInferDispatchIssue] {
  let (configuration, at) = match (value.current)() {
    Ok(observation) => observation
    Err(issue) => return Err(issue)
  }
  if !@publication.run_publication_start_current(
      value.compiled.admission,
      value.definition,
      at,
    ) {
    return Err(Expired)
  }
  guard client_compiled_run_infer(value.compiled) is Some(plan) else {
    return Err(ForeignRun)
  }
  if !@authorization.dispatch_authorization_matches(
      value.authorization,
      configuration,
      @authorization.dispatch_authorization_tuple(value.authorization),
      @authorization.Activation,
      value.invocation_scope
      .map(@publication.model_invocation_scope_cid)
      .unwrap_or(plan.request_cid),
      @publication.run_publication_execution_context(value.compiled.admission),
    ) {
    return Err(Authorization(@authorization.ForeignDecision))
  }
  Ok(())
}

///|
pub fn client_infer_dispatch_matches_scope(
  value : ClientInferDispatchAdmission,
  scope : ClientInferCallScope,
) -> Bool {
  physical_equal(value.compiled.owner, scope.owner) &&
  client_compiled_run_infer(value.compiled) is Some(plan) &&
  physical_equal(plan, scope.plan) &&
  value.invocation_scope
  .map(bound => {
    @publication.model_invocation_scope_input_cid(bound) ==
    @publication.run_evidence_value_identity(scope.artifact)
  })
  .unwrap_or(true)
}

///|
/// An ordinary account allow is not a delegated approval. It can continue a
/// prepared call set without manufacturing a Checkpoint or reviewer claim.
pub fn client_infer_dispatch_account_allow(
  value : ClientInferDispatchAdmission,
) -> Bool {
  @authorization.dispatch_authorization_basis(value.authorization)
  is @authorization.AccountAllow(_)
}

///|
pub fn client_infer_dispatch_matches_run(
  value : ClientInferDispatchAdmission,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Bool {
  physical_equal(value.compiled, compiled) &&
  @publication.publication_contract_identity(value.definition) ==
  @publication.publication_contract_identity(definition)
}

///|
pub fn client_infer_dispatch_authority(
  value : ClientInferDispatchAdmission,
) -> @publication.RunEvidenceValue {
  value.evidence
}

///|
pub fn client_infer_dispatch_run_cid(
  value : ClientInferDispatchAdmission,
) -> String {
  @publication.publication_contract_identity(value.definition)
}

///|
pub fn client_infer_dispatch_invocation_scope_cid(
  value : ClientInferDispatchAdmission,
) -> String? {
  value.invocation_scope.map(@publication.model_invocation_scope_cid)
}
