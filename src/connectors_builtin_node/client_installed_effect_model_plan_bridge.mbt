///|
/// Project the selected domain's original bounds beside the SAME checked
/// compilation. JS supplies no Model Ledger vector or replacement Scope.
#export_name("clientProgramInstalledEffectModelDemandPrepare")
pub fn client_program_installed_effect_model_demand_prepare(
  prepared : @publication_host.PreparedClientEffectComputation,
  compiled : @publication_host.ClientCompiledRun,
  compilation : @publication_host.ClientEffectCompilation,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
) -> Result[
  @client_local_host.ClientInstalledEffectModelDemand,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  let selected = match
    original_composed_model_limits(compiled, definition, occurrence, graph) {
    Err(_) => return Err(ForeignOriginal)
    Ok(value) => value
  }
  @client_local_host.prepare_installed_effect_model_demand(
    prepared,
    compiled,
    compilation,
    definition,
    occurrence,
    graph,
    selected.model.ledger,
    selected.mapping.logical.max_live_value_bytes,
    selected.identity.wire.max_bytes.to_int64(),
    selected.input.rows.operation_entries,
    selected.input.rows.retained_entries,
    selected.input.rows.metadata_entries,
  )
}

///|
/// Read the window retained by the SAME already prepared Model demand.
#export_name("clientProgramInstalledEffectModelReadWindow")
pub fn client_program_installed_effect_model_read_window(
  model : @client_local_host.ClientInstalledEffectModelDemand,
) -> Array[Int64] {
  @client_local_host.installed_effect_model_read_window(model)
}

///|
/// Retain the actual early selected bounds. This later original binding does
/// not invoke their numerical selector again or accept a raw Ledger vector.
#export_name("clientProgramPrepareRequestModelSourceFreePlan")
pub fn client_program_prepare_request_model_source_free_plan(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  original : @client_local_host.ClientInstalledManagedSourceFreePreparation,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  selected : @infer_host.Limits,
) -> Result[
  @client_local_host.ClientInstalledManagedModelPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_request_model_source_free_plan(
    parent,
    input,
    original,
    request,
    compiled,
    definition,
    occurrence,
    graph,
    selected.model.ledger,
    selected.mapping.logical.max_live_value_bytes,
    selected.identity.wire.max_bytes.to_int64(),
    selected.input.rows.operation_entries,
    selected.input.rows.retained_entries,
    selected.input.rows.metadata_entries,
  )
}

///|
/// Keep the original checked bounds' non-byte dimensions. The installed Node
/// declaration must cover those SAME Model extents; it cannot shrink them.
/// The fixed Request/Plan/Scope owns admission, never these numeric inputs.
#export_name("clientProgramPrepareRequestNodeModelSourceFreePlan")
pub fn client_program_prepare_request_node_model_source_free_plan(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  original : @client_local_host.ClientInstalledManagedSourceFreePreparation,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  selected : @infer_host.Limits,
  layout : @publication_host.ClientNodeModelPreparationLayout?,
  installation : @check_environment.ModelResponseProfileInstallation,
  runtime_artifact_cid : String,
  layout_artifact_cid : String,
  probability : @check_environment.DecisionProbabilityProfile?,
  model_retained_bytes : Int64,
  model_execution_bytes : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[
  @client_local_host.ClientInstalledManagedModelPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  guard model_retained_bytes >= selected.model.ledger.retained_bytes &&
    model_execution_bytes >= selected.model.ledger.execution_bytes &&
    max_reservations >= 0 &&
    max_holdings >= 0 &&
    max_delegations >= 0 else {
    return Err(InsufficientCapacity)
  }
  @client_local_host.prepare_request_node_model_source_free_plan(
    parent,
    input,
    original,
    request,
    compiled,
    definition,
    occurrence,
    graph,
    {
      ..selected.model.ledger,
      retained_bytes: model_retained_bytes,
      execution_bytes: model_execution_bytes,
    },
    layout,
    installation,
    runtime_artifact_cid,
    layout_artifact_cid,
    probability,
    Int::max(selected.input.rows.operation_entries, max_reservations),
    Int::max(selected.input.rows.retained_entries, max_holdings),
    Int::max(selected.input.rows.metadata_entries, max_delegations),
  )
}

///|
/// Keep the original checked bounds' non-byte dimensions. The installed Node
/// declaration must cover those SAME Model extents; it cannot shrink them.
/// The fixed Request/Plan/Scope owns admission, never these numeric inputs.
#export_name("clientProgramPrepareRequestNodeModelCapturePlan")
pub fn client_program_prepare_request_node_model_capture_plan(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  original : @client_local_host.ClientInstalledManagedCapturePlan,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  selected : @infer_host.Limits,
  layout : @publication_host.ClientNodeModelPreparationLayout?,
  installation : @check_environment.ModelResponseProfileInstallation,
  runtime_artifact_cid : String,
  layout_artifact_cid : String,
  probability : @check_environment.DecisionProbabilityProfile?,
  model_retained_bytes : Int64,
  model_execution_bytes : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[
  @client_local_host.ClientInstalledManagedModelPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  guard model_retained_bytes >= selected.model.ledger.retained_bytes &&
    model_execution_bytes >= selected.model.ledger.execution_bytes &&
    max_reservations >= 0 &&
    max_holdings >= 0 &&
    max_delegations >= 0 else {
    return Err(InsufficientCapacity)
  }
  @client_local_host.prepare_request_node_model_capture_plan(
    parent,
    input,
    original,
    request,
    compiled,
    definition,
    occurrence,
    graph,
    {
      ..selected.model.ledger,
      retained_bytes: model_retained_bytes,
      execution_bytes: model_execution_bytes,
    },
    layout,
    installation,
    runtime_artifact_cid,
    layout_artifact_cid,
    probability,
    Int::max(selected.input.rows.operation_entries, max_reservations),
    Int::max(selected.input.rows.retained_entries, max_holdings),
    Int::max(selected.input.rows.metadata_entries, max_delegations),
  )
}

///|
#export_name("clientProgramInstalledMockModelCapturePlanBind")
pub fn client_program_installed_mock_model_capture_plan_bind(
  original : @client_local_host.ClientInstalledManagedCapturePlan,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  selected : @infer_host.Limits,
) -> Result[
  @client_local_host.ClientInstalledManagedModelPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_mock_model_capture_plan_binding(
    original,
    compiled,
    definition,
    occurrence,
    graph,
    selected.model.ledger,
    selected.mapping.logical.max_live_value_bytes,
    selected.identity.wire.max_bytes.to_int64(),
    selected.input.rows.operation_entries,
    selected.input.rows.retained_entries,
    selected.input.rows.metadata_entries,
  )
}

///|
/// Retain the original component providers when the original Plan is prepared.
/// The canonical fixed family constructors and their order remain unchanged;
/// the component references are the SAME handles, never late replacements.
// The JS base entry has no optional Array argument. Only these typed Moon
// entries construct None/Some; JS cannot substitute its unboxed Array layout.
#export_name("clientProgramInstalledEffectModelManagedPlanPrepare")
pub fn client_program_installed_effect_model_managed_plan_prepare(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  declarations : Array[@client_row_source_host.RowDeclaration],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  selected_operations : Array[
    @client_local_host.ClientInstalledEffectOperationDemand,
  ],
  model : @client_local_host.ClientInstalledEffectModelDemand,
  components : Array[@local.ManagedProvider],
  query_time : @publication_host.ClientQueryTimePreparation?,
) -> Result[
  @client_local_host.ClientInstalledEffectManagedPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  installed_effect_model_plan_from_original_sources(
    prepared,
    request,
    declarations,
    None,
    query_contract_body,
    evidence_contract_body,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    selected_operations,
    model,
    components,
    query_time,
  )
}

///|
// Preserve the SAME nonempty provider-capacity vector and checked Source count.
#export_name("clientProgramInstalledEffectModelManagedProviderPlanPrepare")
pub fn client_program_installed_effect_model_managed_provider_plan_prepare(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  declarations : Array[@client_row_source_host.RowDeclaration],
  source_providers : Array[@execution.ExecutionCapacity],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  selected_operations : Array[
    @client_local_host.ClientInstalledEffectOperationDemand,
  ],
  model : @client_local_host.ClientInstalledEffectModelDemand,
  components : Array[@local.ManagedProvider],
  query_time : @publication_host.ClientQueryTimePreparation?,
) -> Result[
  @client_local_host.ClientInstalledEffectManagedPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  installed_effect_model_plan_from_original_sources(
    prepared,
    request,
    declarations,
    Some(source_providers),
    query_contract_body,
    evidence_contract_body,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    selected_operations,
    model,
    components,
    query_time,
  )
}

///|
// One shared original component/Plan construction for both typed entrances.
fn installed_effect_model_plan_from_original_sources(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  declarations : Array[@client_row_source_host.RowDeclaration],
  source_providers : Array[@execution.ExecutionCapacity]?,
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  selected_operations : Array[
    @client_local_host.ClientInstalledEffectOperationDemand,
  ],
  model : @client_local_host.ClientInstalledEffectModelDemand,
  components : Array[@local.ManagedProvider],
  query_time : @publication_host.ClientQueryTimePreparation?,
) -> Result[
  @client_local_host.ClientInstalledEffectManagedPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  // An absent component is not supplied by the fixed nine standard families.
  // The actual graph still resolves the original required provider; neither
  // nonempty DATA nor this copied vector establishes its backing or authority.
  if components.is_empty() {
    return Err(Unsupported)
  }
  let components = components.copy()
  @client_local_host.prepare_installed_effect_managed_plan(
    prepared,
    request,
    declarations,
    query_contract_body,
    evidence_contract_body,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    selected_operations,
    model=Some(model),
    query_time~,
    source_providers~,
    provider_factory=capacity => {
      let providers = installed_client_family_providers(capacity)
      for component in components {
        providers.push(component)
      }
      providers
    },
  )
}

///|
#export_name("clientProgramInstalledEffectPlanMatchesModelDemand")
pub fn client_program_installed_effect_plan_matches_model_demand(
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  model : @client_local_host.ClientInstalledEffectModelDemand,
) -> Bool {
  @client_local_host.installed_effect_plan_matches_model_demand(plan, model)
}

///|
/// The original installed reader capacity is an opaque Option from this same
/// runtime. Construct the fixed vector here; JS neither unwraps nor reissues it.
#export_name("clientProgramPrepareRequestModelProviderCaptureModule")
pub fn client_program_prepare_request_model_provider_capture_module(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  compilation : @publication_host.ClientTaskCompilation,
  declaration : @client_row_source_host.RowDeclaration,
  provider : @execution.ExecutionCapacity?,
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Int64,
  transport_execution_bytes : Int64,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  retained_output : Bool,
  query_time : @publication_host.ClientQueryTimePreparation?,
) -> Result[
  @client_local_host.ClientInstalledManagedCapturePlan,
  ClientRequestProgramModuleBridgeIssue,
] {
  @client_local_host.prepare_request_model_capture_module(
    parent,
    input,
    request,
    compiled,
    definition,
    compilation,
    [declaration],
    query_contract_body,
    evidence_contract_body,
    [transport_bytes],
    [transport_execution_bytes],
    contracts,
    retained_output,
    installed_client_family_provider_count(),
    installed_client_family_providers,
    query_time~,
    providers=Some([provider]),
  ).map_err(issue => Preparation(issue))
}
