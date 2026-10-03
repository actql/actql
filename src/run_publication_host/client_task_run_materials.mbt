///|
/// The checked task Run rebuilt from the same bounded materials codec used
/// by Values. Physical Source bindings, delegation and start claims remain
/// Site-owned and are never decoded from Program or materials as authority.
pub(all) struct ClientTaskRunMaterials {
  prepared : PreparedClientProgram
  compilation : ClientTaskCompilation
  admission : @publication.RunPublicationAdmission
  run_definition : @publication.PublicationContract
}

///|
pub(all) enum ClientTaskRunMaterialsIssue {
  Input(ClientValuesRunMaterialsIssue)
  Compilation(ClientTaskCompilationIssue)
  Admission(@publication.RunPublicationAdmissionIssue)
  Definition(@publication.RunPublicationAdmissionIssue)
  RunMismatch
  Binding(ClientTaskRunBindingIssue)
}

///|
/// Project the original admitted task Run, including its original authority,
/// identity and lifetime. This reuses the shared materials encoder; it cannot
/// issue a replacement Run or refresh authorization for a remote Site.
pub fn issue_client_task_run_materials(
  prepared : PreparedClientProgram,
  compilation : ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  environment : @checked.CheckEnvironment,
  environment_wire : String,
  program : String,
  parameters_wire : String?,
) -> Result[String, ClientTaskRunMaterialsIssue] {
  match bind_client_task_run(prepared, compilation, admission, definition) {
    Ok(_) => ()
    Err(issue) => return Err(Binding(issue))
  }
  issue_client_run_materials_input(
    prepared, admission, definition, environment, environment_wire, program, parameters_wire,
  ).map_err(issue => Input(issue))
}

///|
/// Recompute the ordinary checked task compilation and re-admit the original
/// evidence. Source acquisition is not performed here. A full Run CID match
/// is mandatory before the reconstructed Run can enter Site admission.
pub fn admit_client_task_run_materials(
  materials : String,
  expected_run_definition_cid : String,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  manifests : ClientCompilationManifests,
  limits : ClientValuesRunMaterialsLimits,
) -> Result[ClientTaskRunMaterials, ClientTaskRunMaterialsIssue] {
  let input = match
    read_client_run_materials_input(materials, expressions, operations, limits) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  admit_client_task_run_materials_input(
    input, expected_run_definition_cid, manifests, limits,
  )
}

///|
fn admit_client_task_run_materials_input(
  input : ClientRunMaterialsInput,
  expected_run_definition_cid : String,
  manifests : ClientCompilationManifests,
  limits : ClientValuesRunMaterialsLimits,
) -> Result[ClientTaskRunMaterials, ClientTaskRunMaterialsIssue] {
  let compilation = match
    issue_prepared_client_task_compilation(
      input.prepared,
      manifests,
      limits.sequence,
      limits.max_sequence_steps,
      limits.max_sequence_work,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Compilation(issue))
  }
  let evidence = fn(name : String, wire : String) {
    @publication.admit_run_evidence_value(
      name,
      wire,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    ).map_err(_ => ClientTaskRunMaterialsIssue::Input(MaterialsEvidence(name)))
  }
  let prepared_invocation = match
    evidence("prepared_invocation", input.prepared_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let authorization = match
    evidence("run_authorization", input.authorization_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let admission = match
    admit_prepared_client_run_publication(
      input.prepared,
      client_task_compilation_template(compilation),
      prepared_invocation,
      authorization,
      client_task_compilation_compiled_plan(compilation),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  let run_definition = match
    @publication.issue_run_definition(
      admission,
      input.scope_id,
      input.run_id,
      @publication.empty_initial_input_artifact_set_cid(),
      input.created_at,
      input.valid_until,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Definition(issue))
  }
  if @publication.publication_contract_identity(run_definition) !=
    expected_run_definition_cid {
    return Err(RunMismatch)
  }
  match
    bind_client_task_run(input.prepared, compilation, admission, run_definition) {
    Ok(_) =>
      Ok({ prepared: input.prepared, compilation, admission, run_definition, })
    Err(issue) => Err(Binding(issue))
  }
}
