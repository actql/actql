///|
// The existing fixed Model profile is selected by an original compiler and
// its one retained occurrence, never by a caller mode or an equal CID.
fn installed_mock_model_compilation_matches(
  prepared : @publication_host.PreparedClientProgram,
  compilation : @publication_host.ClientTaskCompilation,
) -> Bool {
  physical_equal(compilation.owner, prepared) &&
  compilation.infers.length() == 1 &&
  physical_equal(compilation.infers[0].owner, prepared) &&
  installed_managed_run_shape_supported(prepared, true)
}

///|
/// Retain the original Model compilation in the existing source-free module
/// holder before its Run. The caller backs compilation and factory coexistence
/// on the SAME Request first. No compilation, Scope or admission occurs here.
pub fn prepare_installed_mock_model_source_free_with_contracts(
  prepared : @publication_host.PreparedClientProgram,
  compilation : @publication_host.ClientTaskCompilation,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  retained_output~ : Bool,
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
) -> Result[
  ClientInstalledManagedSourceFreePreparation,
  ClientInstalledManagedRunIssue,
] {
  if !installed_mock_model_compilation_matches(prepared, compilation) {
    return Err(ForeignOriginal)
  }
  let original = match
    source_free_installed_managed_preparation_owned(
      Pure(prepared),
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      true,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let selected = match
    configure_installed_source_free_preparation(
      prepared, original, retained_output, provider_factory,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  selected.compilation = Some(
    @publication_host.ClientRunCompilation::Tasks(compilation),
  )
  Ok(selected)
}

///|
/// The actual two-Source Model profile retains the SAME supplied acquisition
/// inventory, module and compilation. Its ordinary sibling still excludes
/// Model, and neither entry widens the serialization/physical provider profile.
pub fn prepare_installed_mock_model_capture_plan(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  compilation : @publication_host.ClientTaskCompilation,
  captures : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  retained_output~ : Bool,
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
  query_time? : @publication_host.ClientQueryTimePreparation? = None,
) -> Result[ClientInstalledManagedCapturePlan, ClientInstalledManagedRunIssue] {
  if !installed_mock_model_compilation_matches(prepared, compilation) {
    return Err(ForeignOriginal)
  }
  let selected = match
    prepare_installed_managed_capture_plan_owned(
      prepared,
      request,
      captures,
      transport_bytes,
      transport_execution_bytes,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      true,
      retained_output~,
      provider_factory~,
      query_time~,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  selected.compilation = Some(
    @publication_host.ClientRunCompilation::Tasks(compilation),
  )
  Ok(selected)
}

///|
// Pure binding facts only. The Scope and Resource owner keep their separate
// current/physical fences; a different compilation of the same Plan is foreign.
fn installed_request_model_compilation_matches(
  prepared : @publication_host.PreparedClientProgram,
  compilation : @publication_host.ClientRunCompilation?,
  compiled : @publication_host.ClientCompiledRun,
  graph : @publication_host.ClientInferPlanGraph,
) -> Bool {
  guard compilation is Some(@publication_host.Tasks(original)) else {
    return false
  }
  installed_mock_model_compilation_matches(prepared, original) &&
  physical_equal(original.infers[0], graph) &&
  @publication_host.client_compiled_run_matches_tasks(
    compiled, prepared, original,
  )
}

///|
/// Immutable selected module/Model demand, not another Ledger or cleanup
/// owner. The actual existing module holders retain their original compiler.
struct ClientInstalledManagedModelPlan {
  prepared : @publication_host.PreparedClientProgram
  request : @publication_host.ClientRequestIdentity
  compiled : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
  graph : @publication_host.ClientInferPlanGraph
  _occurrence : @publication_host.ClientInferOccurrence
  source_free : ClientInstalledManagedSourceFreePreparation?
  captured : ClientInstalledManagedCapturePlan?
  limits : @resources.LedgerLimits
  max_reservations : Int
  max_holdings : Int
  max_delegations : Int
}

///|
// This exact record above: one header, nine retained references and three
// scalar inventory words. The selected module/compiler, Option carriers,
// Model Scope, provider and all nested construction frames are separate.
let installed_model_plan_record : @execution.PreparationRepresentationUnits = {
  record_headers: 1L,
  reference_slots: 9L,
  scalar_words: 3L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
/// Read the original completed demand through the shared limits projection.
/// No sequence, Model bound selection, Plan or current callback runs again.
pub fn prepared_installed_managed_model_requirements(
  original : ClientInstalledManagedModelPlan,
) -> Array[Int64] {
  installed_effect_requirements(original.limits)
}

///|
pub fn prepare_installed_mock_model_source_free_plan(
  original : ClientInstalledManagedSourceFreePreparation,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  model_limits : @resources.LedgerLimits,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[ClientInstalledManagedModelPlan, ClientInstalledManagedRunIssue] {
  guard original.owner is Pure(prepared) && original.configuration is Some(_) else {
    return Err(ForeignOriginal)
  }
  prepare_installed_mock_model_plan_owned(
    prepared,
    request,
    original.compilation,
    Some(original),
    None,
    original.limits,
    compiled,
    definition,
    occurrence,
    graph,
    model_limits,
    read_retained_bytes,
    read_execution_bytes,
    max_reservations,
    max_holdings,
    max_delegations,
  )
}

///|
pub fn prepare_installed_mock_model_capture_plan_binding(
  original : ClientInstalledManagedCapturePlan,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  model_limits : @resources.LedgerLimits,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[ClientInstalledManagedModelPlan, ClientInstalledManagedRunIssue] {
  prepare_installed_mock_model_plan_owned(
    original.prepared,
    original.request,
    original.compilation,
    None,
    Some(original),
    original.limits,
    compiled,
    definition,
    occurrence,
    graph,
    model_limits,
    read_retained_bytes,
    read_execution_bytes,
    max_reservations,
    max_holdings,
    max_delegations,
  )
}

///|
fn prepare_installed_mock_model_plan_owned(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  compilation : @publication_host.ClientRunCompilation?,
  source_free : ClientInstalledManagedSourceFreePreparation?,
  captured : ClientInstalledManagedCapturePlan?,
  compute_limits : @resources.LedgerLimits,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  model_limits : @resources.LedgerLimits,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[ClientInstalledManagedModelPlan, ClientInstalledManagedRunIssue] {
  let identity = @publication_host.prepared_client_identity(prepared)
  if !installed_request_model_compilation_matches(
      prepared, compilation, compiled, graph,
    ) ||
    !@publication_host.client_infer_occurrence_matches_compiled_run(
      occurrence, compiled,
    ) ||
    !@publication_host.client_infer_occurrence_matches_plan(occurrence, graph) ||
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Err(_) ||
    identity.program_definition_cid !=
    @publication_host.client_request_program_cid(request) ||
    identity.parameter_values_cid !=
    @publication_host.client_request_parameters_cid(request) {
    return Err(ForeignOriginal)
  }
  guard max_reservations >= 0 &&
    max_holdings >= 0 &&
    max_delegations >= 0 &&
    installed_model_demand_limits(
      model_limits, read_retained_bytes, read_execution_bytes,
    )
    is Some(model) &&
    @resources.add_ledger_limits(compute_limits, model) is Some(limits) else {
    return Err(InsufficientCapacity)
  }
  Ok({
    prepared,
    request,
    compiled,
    definition,
    graph,
    _occurrence: occurrence,
    source_free,
    captured,
    limits,
    max_reservations,
    max_holdings,
    max_delegations,
  })
}
