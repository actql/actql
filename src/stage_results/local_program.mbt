///|
pub(all) struct LocalProgramLimits {
  max_stages : Int
  max_steps : Int
  max_results : Int
  max_work : Int
  max_nodes : Int
  max_tokens : Int
  max_text_bytes : Int
  max_depth : Int
} derive(Eq, Debug)

///|
pub(all) struct LocalProgramUsage {
  work : Int
  nodes : Int
  tokens : Int
  text_bytes : Int
  steps : Int
  results : Int
} derive(Eq, Debug)

///|
pub enum LocalProgramIssue {
  InvalidLimits
  CheckOnlyPrefix
  BudgetExceeded
  ForeignEnvironmentSource
  ForeignModelEnvironment
  SourceViewStageCount
  MissingSourceViewRegistrations(Int)
  InvalidSourceViewRegistration(Int, String)
  UnsupportedReceipt(Int, String)
  LocalInput(Int, @local.Issue)
  Import(Int, ImportIssue)
  Pipeline(Int, @pipeline.Issue)
  Collection(Int, @parameters.Issue)
  Results(Int, @results.Issue)
  Order(Int, @results.OrderCheckIssue)
  Ports(Int, @results.PortIssue)
  TableInputs(Int, @results.Issue)
  Wiring(WiringIssue)
}

///|
/// Construct local-input and Result-import pipelines from one retained source.
/// This orchestrates topology and publication preparation, not full static
/// closure, input-value admission, Parameter binding or execution permission.
/// Parsing and declaration admission precede this call and are not billed here.
pub fn prepare_local_program(
  source : @parameters.Source,
  limits : LocalProgramLimits,
  environment? : @local.ProgramEnvironmentInputs? = None,
  sourceview_registrations? : Array[Array[(String, @pipeline.InputContract)]]? = None,
  calendar_profile? : @calendar_profile.Profile? = None,
  model_tasks? : @environment.ModelTasks? = None,
) -> Result[(ResultWiring, LocalProgramUsage), LocalProgramIssue] {
  match
    prepare_program_internal(
      source,
      limits,
      environment~,
      sourceview_registrations~,
      calendar_profile~,
      model_tasks~,
      check_only=false,
    ) {
    Ok((Publication(wiring), usage)) => Ok((wiring, usage))
    Ok(_) => abort("mixed preparation modes")
    Err(e) => Err(e)
  }
}

///|
/// Check complete topology before demand selection. This does not resolve
/// publication orders, admit runtime values or issue execution permission.
/// Operation-required input order is still checked by the ordinary pipeline.
pub fn check_local_program(
  source : @parameters.Source,
  limits : LocalProgramLimits,
  environment? : @local.ProgramEnvironmentInputs? = None,
  sourceview_registrations? : Array[Array[(String, @pipeline.InputContract)]]? = None,
  calendar_profile? : @calendar_profile.Profile? = None,
  model_tasks? : @environment.ModelTasks? = None,
) -> Result[(CheckedTopology, LocalProgramUsage), LocalProgramIssue] {
  match
    prepare_program_internal(
      source,
      limits,
      environment~,
      sourceview_registrations~,
      calendar_profile~,
      model_tasks~,
      check_only=true,
    ) {
    Ok((Topology(topology), usage)) => Ok((topology, usage))
    Ok(_) => abort("mixed preparation modes")
    Err(e) => Err(e)
  }
}

///|
fn prepare_program_internal(
  source : @parameters.Source,
  limits : LocalProgramLimits,
  environment? : @local.ProgramEnvironmentInputs? = None,
  sourceview_registrations? : Array[Array[(String, @pipeline.InputContract)]]? = None,
  calendar_profile? : @calendar_profile.Profile? = None,
  model_tasks? : @environment.ModelTasks? = None,
  check_only~ : Bool,
) -> Result[(LocalProgramPreparation, LocalProgramUsage), LocalProgramIssue] {
  let original = match
    begin_local_program_read_owned(
      source,
      limits,
      environment~,
      sourceview_registrations~,
      calendar_profile~,
      model_tasks~,
      check_only~,
    ) {
    Err(issue) => return Err(issue)
    Ok(original) => original
  }
  while original.state is Reading(_) {
    advance_local_program_read(original) |> ignore
  }
  take_local_program_read(original).unwrap()
}
