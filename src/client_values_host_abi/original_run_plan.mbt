///|
pub(all) enum ClientValuesHostOriginalPlanIssue {
  ValuesBinding(@host.ClientValuesRunBindingIssue)
  TaskBinding(@host.ClientTaskRunBindingIssue)
  Plan(@host.ClientInteractivePlanIssue)
}

///|
fn original_plan_fields(
  prepared : @host.PreparedClientProgram,
  admission : @publication.RunPublicationAdmission,
  plan : @publication.PublicationContract,
  view : String,
) -> Array[String] {
  [
    @publication.publication_contract_json(plan),
    view,
    @host.prepared_client_identity(prepared).program_definition_cid,
    @publication.run_evidence_value_json(
      @publication.run_publication_prepared(admission),
    ),
    @publication.run_evidence_value_json(
      @publication.run_publication_authorization(admission),
    ),
  ]
}

///|
/// First capture requires the original checked compilation and admitted Run.
/// These immutable metadata fields confer no execution or read authority.
#export_name("clientValuesHostCaptureOriginalValuesRunPlan")
pub fn client_values_host_capture_original_values_run_plan(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientValuesCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[String], ClientValuesHostOriginalPlanIssue] {
  match
    @host.bind_source_free_client_values_run(
      prepared, compilation, admission, definition,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(ValuesBinding(issue))
  }
  let view = match
    @host.client_values_static_plan_view(
      prepared, compilation, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Plan(issue))
  }
  Ok(
    original_plan_fields(
      prepared,
      admission,
      @host.client_values_compilation_compiled_plan(compilation),
      view,
    ),
  )
}

///|
#export_name("clientValuesHostCaptureOriginalTaskRunPlan")
pub fn client_values_host_capture_original_task_run_plan(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[String], ClientValuesHostOriginalPlanIssue] {
  match
    @host.bind_client_task_run(prepared, compilation, admission, definition) {
    Ok(_) => ()
    Err(issue) => return Err(TaskBinding(issue))
  }
  let view = match
    @host.client_task_static_plan_view(
      prepared, compilation, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Plan(issue))
  }
  Ok(
    original_plan_fields(
      prepared,
      admission,
      @host.client_task_compilation_compiled_plan(compilation),
      view,
    ),
  )
}

///|
#export_name("clientValuesHostCheckStoredPlanView")
pub fn client_values_host_check_stored_plan_view(
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, @publication.PublicationContractIssue] {
  @publication.parse_interactive_run_control_shape(
    "plan_view", wire, max_bytes, max_nodes, max_depth,
  ).map(_ => ())
}

///|
#export_name("clientValuesHostCheckLogicalMapBinding")
pub fn client_values_host_check_logical_map_binding(
  map : @publication.RunEvidenceValue,
  plan : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, @publication.RunEvidenceValueIssue] {
  @publication.check_interactive_logical_map_binding(
    map, plan, max_bytes, max_nodes, max_depth,
  )
}
