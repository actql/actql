///|
// The checked single Model component is selected by its original compiler and
// its one retained occurrence, never by a caller mode or an equal CID.
fn installed_mock_model_compilation_matches(
  prepared : @publication_host.PreparedClientProgram,
  compilation : @publication_host.ClientTaskCompilation,
) -> Bool {
  physical_equal(compilation.owner, prepared) &&
  compilation.infers.length() == 1 &&
  physical_equal(compilation.infers[0].owner, prepared) &&
  installed_managed_owner_shape_supported(
    Pure(prepared),
    true,
    model=Some(compilation.infers[0]),
  ) &&
  (match compilation.infers[0].serialization {
    None =>
      @publication_host.client_task_compilation_serialization(compilation)
      is None
    Some(component) =>
      @publication_host.client_task_compilation_serialization(compilation)
      is Some(original) &&
      physical_equal(component, original)
  })
}

///|
/// Retain the original Model compilation in the existing source-free module
/// holder before its Run. The caller backs compilation and factory coexistence
/// on the SAME Request first. No compilation, Scope or admission occurs here.
/// A supplied QueryTime/request pair is already bound to its original Run;
/// the sequences retain that context without another sample or compilation.
/// The caller backs the retained pair and all constructor overlap first.
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
  query_time? : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
  )? = None,
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
      model=Some(compilation.infers[0]),
      query_time~,
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
/// The single Model component retains the SAME supplied acquisition
/// inventory, module and compilation. Its ordinary sibling still excludes
/// Model. This checked component does not supply a physical provider or grant.
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
      model=Some(compilation.infers[0]),
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
  content_prefix : ClientInstalledManagedSerializationPreparation?
  limits : @resources.LedgerLimits
  max_reservations : Int
  max_holdings : Int
  max_delegations : Int
}

///|
// This exact record above: one header, ten retained references and three
// scalar inventory words. The selected module/compiler, Option carriers,
// Model Scope, provider and all nested construction frames are separate.
let installed_model_plan_record : @execution.PreparationRepresentationUnits = {
  record_headers: 1L,
  reference_slots: 10L,
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
fn prepare_installed_mock_model_source_free_plan(
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
  content_prefix? : ClientInstalledManagedSerializationPreparation? = None,
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
    content_prefix~,
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
  content_prefix? : ClientInstalledManagedSerializationPreparation? = None,
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
    content_prefix~,
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
  content_prefix? : ClientInstalledManagedSerializationPreparation? = None,
) -> Result[ClientInstalledManagedModelPlan, ClientInstalledManagedRunIssue] {
  // The module's sequences already retain this original invocation. A later
  // equal-CID request or another saved Run cannot replace its bound context.
  if source_free is Some(selected_module) &&
    selected_module._observed_query_time is Some((original, bound_request)) {
    if !physical_equal(bound_request, request) ||
      !@publication_host.client_query_time_preparation_context(original)
      .map(context => {
        physical_equal(
          @publication.query_evaluation_time_definition(context),
          definition,
        )
      })
      .unwrap_or(false) {
      return Err(ForeignOriginal)
    }
  }
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
  match (graph.serialization, content_prefix) {
    (None, None) => ()
    (Some(component), Some(prefix)) => {
      guard physical_equal(prefix.prepared, prepared) &&
        physical_equal(prefix.request, request) &&
        physical_equal(prefix._observed_compiled, compiled) &&
        physical_equal(prefix._observed_definition, definition) &&
        @publication_host.client_compiled_run_serialization(compiled)
        is Some(original) &&
        physical_equal(original, component) else {
        return Err(ForeignOriginal)
      }
    }
    _ => return Err(ForeignOriginal)
  }
  guard max_reservations >= 0 &&
    max_holdings >= 0 &&
    max_delegations >= 0 &&
    installed_model_demand_limits(
      model_limits, read_retained_bytes, read_execution_bytes,
    )
    is Some(model) &&
    @resources.add_ledger_limits(compute_limits, model) is Some(model_limits) else {
    return Err(InsufficientCapacity)
  }
  let limits = match content_prefix {
    None => model_limits
    Some(prefix) =>
      match @resources.add_ledger_limits(model_limits, prefix.limits) {
        Some(limits) => limits
        None => return Err(InsufficientCapacity)
      }
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
    content_prefix,
    limits,
    max_reservations,
    max_holdings,
    max_delegations,
  })
}
