///|
/// References an existing checked Run and account decision. This does not
/// authorize media, regions or classification that the Host has not admitted.
pub struct ClientInferDispatchAdmission {
  compiled : ClientCompiledRun
  definition : @publication.PublicationContract
  authorization : @authorization.DispatchAuthorization
  evidence : @publication.RunEvidenceValue
  subject_cid : String
  activation_context_cid : String
  plan : ClientInferPlanGraph
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
  model_scope? : @publication.BoundModelInvocationScope? = None,
  evidence_bytes? : Int = 16384,
  evidence_nodes? : Int = 256,
  evidence_depth? : Int = 8,
  observe_current~ : () -> Result[
    (@authorization.AdmittedAccountConfiguration, String),
    ClientInferDispatchIssue,
  ],
) -> Result[ClientInferDispatchAdmission, ClientInferDispatchIssue] {
  if evidence_bytes > 16384 || evidence_nodes > 256 || evidence_depth > 8 {
    return Err(Encoding)
  }
  let selected = match model_scope {
    None => client_compiled_run_infer(compiled)
    Some(scope) => {
      let boundary = @publication.model_invocation_scope_boundary(scope)
      let candidates = client_compiled_run_infers(compiled).filter(plan => {
        plan.task.to_int64() == boundary.task_index &&
        plan.barrier_cid == boundary.inference_barrier_cid
      })
      if candidates.length() == 1 {
        candidates.get(0)
      } else {
        None
      }
    }
  }
  guard selected is Some(plan) &&
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
  let subject_cid = match model_scope {
    None => plan.request_cid
    Some(scope) => {
      let (_, run_cid, _) = @publication.model_invocation_scope_run(scope)
      if run_cid != @publication.publication_contract_identity(definition) ||
        @publication.model_invocation_scope_prepared_cid(scope) !=
        @publication.run_evidence_value_identity(
          @publication.run_publication_prepared(compiled.admission),
        ) {
        return Err(ForeignRun)
      }
      @publication.model_invocation_scope_cid(scope)
    }
  }
  let task = @environment.model_execution_task(plan.execution)
  let context_cid = @publication.run_publication_execution_context(
    compiled.admission,
  )
  let activation_context_cid = match model_scope {
    Some(scope) =>
      @publication.model_invocation_scope_boundary(scope).context_cid
    None => context_cid
  }
  let policy_cid = @publication.run_publication_host_policy(compiled.admission)
  let tuple : @authorization.AccessTuple = {
    principal,
    connection: @environment.model_task_connector(task),
    resource: @environment.model_task_identity(task).2,
    operation: "infer",
  }
  let authorization = match
    @authorization.bind_dispatch_authorization(
      current,
      tuple,
      @authorization.Activation,
      subject_cid,
      activation_context_cid,
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
  try {
    let writer = @encode.writer(evidence_bytes, evidence_nodes, evidence_depth)
    emit_client_infer_dispatch_authority_body(
      writer,
      compiled,
      definition,
      plan,
      current.configuration_cid(),
      context_cid,
      policy_cid,
      principal,
      tuple.connection,
      tuple.resource,
      entry,
      kind,
      authority,
      claims,
      match model_scope {
        Some(scope) => @publication.model_invocation_scope_cid(scope)
        None => ""
      },
    )
    let evidence = match
      @publication.seal_run_evidence_value(
        "model_dispatch_authority",
        @encode.finish(writer),
        evidence_bytes,
        evidence_nodes,
        evidence_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Evidence(issue))
    }
    Ok({
      compiled,
      definition,
      authorization,
      evidence,
      subject_cid,
      activation_context_cid,
      plan,
      current: observe_current,
    })
  } catch {
    _ => Err(Encoding)
  }
}

///|
fn emit_client_infer_dispatch_authority_body(
  writer : @encode.Writer,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  account_cid : String,
  context_cid : String,
  policy_cid : String,
  principal : String,
  connection : String,
  resource : String,
  entry : String,
  kind : String,
  authority : String?,
  claims : Array[String],
  scope_cid : String,
) -> Unit raise @encode.EncodeFailure {
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
      ("account_configuration_cid", account_cid),
      ("model_task_cid", resource),
      ("fixed_request_cid", plan.request_cid),
      ("execution_context_cid", context_cid),
      ("host_policy_cid", policy_cid),
      ("principal", principal),
      ("connection", connection),
      ("resource", resource),
      ("operation", "infer"),
      ("entry_id", entry),
      ("basis", kind),
    ] {
    @encode.key(writer, name)
    @encode.string_value(writer, value)
  }
  if !scope_cid.is_empty() {
    @encode.key(writer, "model_invocation_scope_cid")
    @encode.string_value(writer, scope_cid)
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
}

///|
/// Measure the AccountAllow authority for a future original Model Scope.
/// The completed Scope CID has the fixed canonical width used here. Nothing
/// is signed or admitted during this text-free measurement.
pub fn measure_client_infer_account_dispatch_authority(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  account : @authorization.AdmittedAccountConfiguration,
  principal : String,
  connection : String,
  resource : String,
  entry : String,
) -> (Int, Int, Int)? {
  try {
    let writer = @encode.measuring_writer(16384, 256, 8)
    emit_client_infer_dispatch_authority_body(
      writer,
      compiled,
      definition,
      plan,
      account.configuration_cid(),
      @publication.run_publication_execution_context(compiled.admission),
      @publication.run_publication_host_policy(compiled.admission),
      principal,
      connection,
      resource,
      entry,
      "account_allow",
      None,
      [],
      "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    )
    let (bytes, nodes, depth) = @encode.finish_measurement_usage(writer)
    // One comma plus the quoted name, colon and canonical quoted CID.
    if bytes <= 16384 - 85 && nodes < 256 {
      Some((bytes + 85, nodes + 1, depth))
    } else {
      None
    }
  } catch {
    _ => None
  }
}

///|
/// The physical provider boundary re-reads environment observations after
/// bounded input preparation. Changed account policy cannot reuse a permit.
pub fn check_client_infer_dispatch_current(
  value : ClientInferDispatchAdmission,
  observed_at? : Ref[String]? = None,
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
  if !client_compiled_run_has_infer(value.compiled, value.plan) {
    return Err(ForeignRun)
  }
  if !@authorization.dispatch_authorization_matches(
      value.authorization,
      configuration,
      @authorization.dispatch_authorization_tuple(value.authorization),
      @authorization.Activation,
      value.subject_cid,
      value.activation_context_cid,
    ) {
    return Err(Authorization(@authorization.ForeignDecision))
  }
  if observed_at is Some(output) {
    output.val = at
  }
  Ok(())
}

///|
pub fn client_infer_dispatch_matches_scope(
  value : ClientInferDispatchAdmission,
  scope : ClientInferCallScope,
) -> Bool {
  physical_equal(value.compiled.owner, scope.owner) &&
  client_compiled_run_has_infer(value.compiled, scope.plan) &&
  physical_equal(value.plan, scope.plan)
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
pub fn client_infer_dispatch_subject(
  value : ClientInferDispatchAdmission,
) -> String {
  value.subject_cid
}
