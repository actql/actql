///|
/// The checked task Run rebuilt from the same bounded materials codec used
/// by Values. Physical Source bindings, delegation and start claims remain
/// Site-owned and are never decoded from Program or materials as authority.
pub(all) struct ClientTaskRunMaterials {
  prepared : PreparedClientProgram
  compilation : ClientTaskCompilation
  admission : @publication.RunPublicationAdmission
  run_definition : @publication.PublicationContract
  retained_input : ClientTaskRunMaterialsRetainedInput
}

///|
/// Exact checked codec input. Private fields prevent a caller from attaching
/// independently prepared input or a replacement wire to an admitted task.
pub struct ClientTaskRunMaterialsRetainedInput {
  prepared : PreparedClientProgram
  materials_wire : String
  program : String
  environment_wire : String
  parameters_wire : String?
}

///|
pub fn client_task_run_materials_retained_input(
  materials : ClientTaskRunMaterials,
) -> ClientTaskRunMaterialsRetainedInput {
  materials.retained_input
}

///|
pub fn client_task_run_materials_retained_program(
  input : ClientTaskRunMaterialsRetainedInput,
) -> PreparedClientProgram {
  input.prepared
}

///|
pub fn client_task_run_materials_retained_document(
  input : ClientTaskRunMaterialsRetainedInput,
) -> String {
  input.program
}

///|
pub fn client_task_run_materials_retained_environment(
  input : ClientTaskRunMaterialsRetainedInput,
) -> String {
  input.environment_wire
}

///|
pub fn client_task_run_materials_retained_parameters(
  input : ClientTaskRunMaterialsRetainedInput,
) -> String? {
  input.parameters_wire
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
  admit_client_task_run_materials_compilation(
    input, compilation, expected_run_definition_cid, limits,
  )
}

///|
// Both task compilers must re-admit the same saved invocation, authorization
// and complete Run identity. A reconstructed INFER graph is not authority.
fn admit_client_task_run_materials_compilation(
  input : ClientRunMaterialsInput,
  compilation : ClientTaskCompilation,
  expected_run_definition_cid : String,
  limits : ClientValuesRunMaterialsLimits,
) -> Result[ClientTaskRunMaterials, ClientTaskRunMaterialsIssue] {
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
      Ok({
        prepared: input.prepared,
        compilation,
        admission,
        run_definition,
        retained_input: {
          prepared: input.prepared,
          materials_wire: input.materials_wire,
          program: input.program,
          environment_wire: input.environment_wire,
          parameters_wire: input.parameters_wire,
        },
      })
    Err(issue) => Err(Binding(issue))
  }
}

///|
/// Rewrap only the exact codec-admitted task compilation and its original
/// admission evidence. This issues no authorization, Run or replacement CID.
/// Result policy originals still require their separate Host journal custody.
pub fn client_task_run_materials_compiled_original(
  materials : ClientTaskRunMaterials,
) -> Result[ClientCompiledRun, ClientCompiledRunIssue] {
  if !physical_equal(materials.prepared, materials.retained_input.prepared) {
    return Err(ForeignOwner)
  }
  let value : ClientCompiledRun = {
    owner: materials.prepared,
    compilation: Tasks(materials.compilation),
    template: client_task_compilation_template(materials.compilation),
    plan: client_task_compilation_compiled_plan(materials.compilation),
    prepared: @publication.run_publication_prepared(materials.admission),
    authorization: @publication.run_publication_authorization(
      materials.admission,
    ),
    admission: materials.admission,
    source_free_result_policy: None,
    definition_binding: None,
  }
  check_client_compiled_run_definition(value, materials.run_definition).map(fn(
    _,
  ) {
    value
  })
}

///|
pub(all) enum ClientSavedTaskMaterialsIssue {
  MissingOriginal
  CustodyLost
  Compilation(ClientCompiledRunIssue)
  Binding(ClientRunBindingIssue)
}

///|
/// The same saved Submission and its exact checked original task input.
/// This carrier proves no current authority, physical start or Store ACK.
pub struct ClientSavedTaskMaterials {
  snapshot : ClientSavedSubmissionSnapshot
  input : ClientTaskRunMaterialsRetainedInput
}

///|
pub fn bind_client_saved_submission_task_materials(
  snapshot : ClientSavedSubmissionSnapshot,
  materials : ClientTaskRunMaterials,
) -> Result[ClientSavedTaskMaterials, ClientSavedTaskMaterialsIssue] {
  guard snapshot.task_materials is Some(wire) else {
    return Err(MissingOriginal)
  }
  if wire != materials.retained_input.materials_wire {
    return Err(CustodyLost)
  }
  guard snapshot.record.run_admission is Some(admission) &&
    snapshot.run is Some(row) &&
    snapshot.inspection is Some(run) else {
    return Err(CustodyLost)
  }
  if @publication.publication_contract_identity(materials.run_definition) !=
    @publication.publication_contract_identity(run.definition) ||
    validate_client_submitted_retained_run(
      snapshot.record.reference,
      admission,
      run.request,
      run.definition,
      row.revision,
    )
    is Err(_) {
    return Err(CustodyLost)
  }
  let compiled = match client_task_run_materials_compiled_original(materials) {
    Ok(value) => value
    Err(issue) => return Err(Compilation(issue))
  }
  match
    validate_client_run_binding(
      run.request,
      materials.retained_input.prepared,
      compiled,
      run.definition,
    ) {
    Ok(_) => Ok({ snapshot, input: materials.retained_input, })
    Err(issue) => Err(Binding(issue))
  }
}

///|
pub fn client_saved_task_materials_snapshot(
  value : ClientSavedTaskMaterials,
) -> ClientSavedSubmissionSnapshot {
  value.snapshot
}

///|
pub fn client_saved_task_materials_intent(
  value : ClientSavedTaskMaterials,
) -> ClientSubmittedIntent {
  value.snapshot.record.intent
}

///|
pub fn client_saved_task_materials_input(
  value : ClientSavedTaskMaterials,
) -> ClientTaskRunMaterialsRetainedInput {
  value.input
}
