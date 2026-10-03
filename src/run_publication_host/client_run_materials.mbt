///|
/// The original Run and its ordinary checked compilation, rebuilt once from
/// the bounded materials codec. Selection adds no authority and never changes
/// the original Run or compiled-plan identity.
pub(all) struct ClientRunMaterials {
  prepared : PreparedClientProgram
  compilation : ClientRunCompilation
  admission : @publication.RunPublicationAdmission
  run_definition : @publication.PublicationContract
}

///|
pub(all) enum ClientRunMaterialsIssue {
  Values(ClientValuesRunMaterialsIssue)
  Tasks(ClientTaskRunMaterialsIssue)
}

///|
/// Use the existing Values compiler for a source-free Values Run and the
/// checked task compiler for an acquired Run. Both are re-admitted against
/// the exact original evidence; there is no fallback, CID alias or reissue.
pub fn admit_client_run_materials(
  materials : String,
  expected_run_definition_cid : String,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  manifests : ClientCompilationManifests,
  limits : ClientValuesRunMaterialsLimits,
) -> Result[ClientRunMaterials, ClientRunMaterialsIssue] {
  let input = match
    read_client_run_materials_input(materials, expressions, operations, limits) {
    Ok(value) => value
    Err(issue) => return Err(Values(issue))
  }
  if prepared_client_acquisition_count(input.prepared) == 0 {
    let values = match
      admit_client_values_run_materials_input(
        input, expected_run_definition_cid, manifests, limits,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Values(issue))
    }
    Ok({
      prepared: values.prepared,
      compilation: Values(values.compilation),
      admission: values.admission,
      run_definition: values.run_definition,
    })
  } else {
    let tasks = match
      admit_client_task_run_materials_input(
        input, expected_run_definition_cid, manifests, limits,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Tasks(issue))
    }
    Ok({
      prepared: tasks.prepared,
      compilation: Tasks(tasks.compilation),
      admission: tasks.admission,
      run_definition: tasks.run_definition,
    })
  }
}
