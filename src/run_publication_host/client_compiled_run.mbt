///|
enum ClientRunCompilation {
  Values(ClientValuesCompilation)
  Tasks(ClientTaskCompilation)
}

///|
/// One in-process compilation and its checked owner retain issued admission
/// evidence. Serialized identity is never a replacement for this provenance.
pub struct ClientCompiledRun {
  owner : PreparedClientProgram
  compilation : ClientRunCompilation
  template : @publication.RunEvidenceValue
  plan : @publication.PublicationContract
  prepared : @publication.RunEvidenceValue
  authorization : @publication.RunEvidenceValue
  admission : @publication.RunPublicationAdmission
}

///|
pub(all) enum ClientCompiledRunIssue {
  ForeignOwner
  Policy(ClientAllowedRunEvidenceIssue)
  Admission(@publication.RunPublicationAdmissionIssue)
  Contract(@publication.PublicationContractIssue)
  ValuesBinding(ClientValuesRunBindingIssue)
  TaskBinding(ClientTaskRunBindingIssue)
}

///|
pub fn client_compiled_run_matches(
  value : ClientCompiledRun,
  owner : PreparedClientProgram,
) -> Bool {
  physical_equal(value.owner, owner)
}

///|
pub fn issue_client_values_compiled_run(
  owner : PreparedClientProgram,
  compilation : ClientValuesCompilation,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
) -> Result[ClientCompiledRun, ClientCompiledRunIssue] {
  if !physical_equal(owner, compilation.owner) {
    return Err(ForeignOwner)
  }
  issue_client_compiled_run(
    owner,
    Values(compilation),
    compilation.template,
    compilation.compiled_plan,
    execution_context_cid,
    host_policy_cid,
    expires_at,
  )
}

///|
pub fn issue_client_task_compiled_run(
  owner : PreparedClientProgram,
  compilation : ClientTaskCompilation,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
) -> Result[ClientCompiledRun, ClientCompiledRunIssue] {
  if !physical_equal(owner, compilation.owner) {
    return Err(ForeignOwner)
  }
  issue_client_compiled_run(
    owner,
    Tasks(compilation),
    compilation.template,
    compilation.compiled_plan,
    execution_context_cid,
    host_policy_cid,
    expires_at,
  )
}

///|
fn issue_client_compiled_run(
  owner : PreparedClientProgram,
  compilation : ClientRunCompilation,
  template : @publication.RunEvidenceValue,
  plan : @publication.PublicationContract,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
) -> Result[ClientCompiledRun, ClientCompiledRunIssue] {
  let (prepared, authorization) = match
    issue_client_allowed_run_evidence(
      template, plan, execution_context_cid, host_policy_cid, expires_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Policy(issue))
  }
  let admission = match
    admit_prepared_client_run_publication(
      owner, template, prepared, authorization, plan,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  Ok({ owner, compilation, template, plan, prepared, authorization, admission, })
}

///|
pub fn client_compiled_run_template(
  value : ClientCompiledRun,
) -> @publication.RunEvidenceValue {
  value.template
}

///|
pub fn client_compiled_run_plan(
  value : ClientCompiledRun,
) -> @publication.PublicationContract {
  value.plan
}

///|
pub fn client_compiled_run_prepared(
  value : ClientCompiledRun,
) -> @publication.RunEvidenceValue {
  value.prepared
}

///|
pub fn client_compiled_run_authorization(
  value : ClientCompiledRun,
) -> @publication.RunEvidenceValue {
  value.authorization
}

///|
pub fn client_compiled_run_admission(
  value : ClientCompiledRun,
) -> @publication.RunPublicationAdmission {
  value.admission
}

///|
pub fn check_client_compiled_run_definition(
  value : ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[Unit, ClientCompiledRunIssue] {
  match value.compilation {
    Values(compilation) =>
      bind_source_free_client_values_run(
        value.owner,
        compilation,
        value.admission,
        definition,
      )
      .map(_ => ())
      .map_err(issue => ValuesBinding(issue))
    Tasks(compilation) =>
      bind_client_task_run(
        value.owner,
        compilation,
        value.admission,
        definition,
      )
      .map(_ => ())
      .map_err(issue => TaskBinding(issue))
  }
}

///|
pub fn issue_client_compiled_run_definition(
  value : ClientCompiledRun,
  scope_id : String,
  run_id : String,
  created_at : String,
  valid_until : String,
) -> Result[@publication.PublicationContract, ClientCompiledRunIssue] {
  let definition = match
    @publication.issue_run_definition(
      value.admission,
      scope_id,
      run_id,
      @publication.empty_initial_input_artifact_set_cid(),
      created_at,
      valid_until,
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  check_client_compiled_run_definition(value, definition).map(_ => definition)
}

///|
/// Restoring durable bytes is a real admission boundary, unlike forwarding
/// newly issued evidence inside one runtime. Never reconstruct a new Run here.
pub fn admit_client_compiled_run_definition(
  value : ClientCompiledRun,
  wire : String,
) -> Result[@publication.PublicationContract, ClientCompiledRunIssue] {
  let definition = match
    @publication.admit_publication_contract(
      "run_definition", wire, 100000, 10000, 100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Contract(issue))
  }
  check_client_compiled_run_definition(value, definition).map(_ => definition)
}

///|
pub fn issue_client_compiled_values_invocation(
  value : ClientCompiledRun,
  definition : @publication.PublicationContract,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  if check_client_compiled_run_definition(value, definition) is Err(_) {
    return Err(@publication.RunEvidenceReferenceMismatch("values_run"))
  }
  match value.compilation {
    Values(compilation) =>
      issue_client_values_source_free_invocation(
        compilation, data_policy_cid, max_wire_bytes, max_nodes, max_depth,
      )
    Tasks(_) => Err(@publication.RunEvidenceReferenceMismatch("values_run"))
  }
}

///|
pub fn issue_client_compiled_source_free_task_invocation(
  value : ClientCompiledRun,
  definition : @publication.PublicationContract,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  if check_client_compiled_run_definition(value, definition) is Err(_) {
    return Err(@publication.RunEvidenceReferenceMismatch("task_run"))
  }
  match value.compilation {
    Tasks(compilation) =>
      issue_client_task_source_free_invocation(
        compilation, data_policy_cid, max_wire_bytes, max_nodes, max_depth,
      )
    Values(_) => Err(@publication.RunEvidenceReferenceMismatch("task_run"))
  }
}

///|
pub fn issue_client_compiled_task_invocation(
  value : ClientCompiledRun,
  definition : @publication.PublicationContract,
  source_evidence_wire : String,
  input_logical_wire : String,
  source_ref : String,
  source_contract_cid : String,
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  match value.compilation {
    Tasks(compilation) =>
      issue_client_task_invocation(
        value.owner,
        compilation,
        value.admission,
        definition,
        source_evidence_wire,
        input_logical_wire,
        source_ref,
        source_contract_cid,
        authority_scope_cid,
        data_policy_cid,
        capture_started_at,
        capture_completed_at,
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
    Values(_) => Err(@publication.RunEvidenceReferenceMismatch("task_run"))
  }
}
