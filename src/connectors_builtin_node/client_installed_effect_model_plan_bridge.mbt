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
  bootstrap_retained_bytes : Int64,
  bootstrap_execution_bytes : Int64,
) -> Result[
  @client_local_host.ClientInstalledManagedModelPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  guard model_retained_bytes >= selected.model.ledger.retained_bytes &&
    model_execution_bytes >= selected.model.ledger.execution_bytes &&
    bootstrap_retained_bytes >= selected.mapping.logical.max_live_value_bytes &&
    bootstrap_execution_bytes >= selected.identity.wire.max_bytes.to_int64() &&
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
    bootstrap=Some((bootstrap_retained_bytes, bootstrap_execution_bytes)),
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
  bootstrap_retained_bytes : Int64,
  bootstrap_execution_bytes : Int64,
) -> Result[
  @client_local_host.ClientInstalledManagedModelPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  guard model_retained_bytes >= selected.model.ledger.retained_bytes &&
    model_execution_bytes >= selected.model.ledger.execution_bytes &&
    bootstrap_retained_bytes >= selected.mapping.logical.max_live_value_bytes &&
    bootstrap_execution_bytes >= selected.identity.wire.max_bytes.to_int64() &&
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
    bootstrap=Some((bootstrap_retained_bytes, bootstrap_execution_bytes)),
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

///|
#export_name("clientProgramPreparedRequestModelInputPrefix")
pub fn client_program_prepared_request_model_input_prefix(
  original : @client_local_host.ClientInstalledManagedCapturePlan,
) -> Result[
  @execution.GeneratedSequence,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepared_request_model_input_prefix(original)
}

///|
#export_name("clientProgramPreparedRequestModelInputSuffix")
pub fn client_program_prepared_request_model_input_suffix(
  original : @client_local_host.ClientInstalledManagedCapturePlan,
) -> Result[
  @execution.GeneratedSequence?,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepared_request_model_input_suffix(original)
}

///|
/// The original installed reader capacity is an opaque Option from this same
/// runtime. Construct the fixed vector here; JS neither unwraps nor reissues it.
#export_name("clientProgramPrepareRequestModelProviderComponentCaptureModule")
pub fn client_program_prepare_request_model_provider_component_capture_module(
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
  construct : (
    @execution.ExecutionCapacity,
    @execution.GeneratedSequence,
    (@infer_host.Execution) -> Result[Unit, @infer_host.Issue],
  ) -> @local.ManagedProvider,
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
    installed_client_family_provider_count() + 1,
    installed_client_family_providers,
    query_time~,
    providers=Some([provider]),
    // Keep the optional sequence in this typed closure. JS forwards the
    // binder unchanged; it never unwraps/reboxes this original Option.
    component_factory=Some((capacity, prefix, suffix) => {
      construct(capacity, prefix, active => {
        match suffix {
          None => Ok(())
          Some(original) => @infer_host.bind_compute_suffix(active, original)
        }
      })
    }),
  ).map_err(issue => Preparation(issue))
}

///|
// Bind the actual deferred Model provider before the one source-free module
// configures its Local dispatch. The optional suffix remains native.
#export_name("clientProgramPrepareRequestModelSourceFreeComponentModule")
pub fn client_program_prepare_request_model_source_free_component_module(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  compilation : @publication_host.ClientTaskCompilation,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  retained_output : Bool,
  query_time : @publication_host.ClientQueryTimePreparation?,
  construct : (
    @execution.ExecutionCapacity,
    @execution.GeneratedSequence,
    (@infer_host.Execution) -> Result[Unit, @infer_host.Issue],
  ) -> @local.ManagedProvider,
) -> Result[
  @client_local_host.ClientInstalledManagedSourceFreePreparation,
  ClientRequestProgramModuleBridgeIssue,
] {
  @client_local_host.prepare_request_model_source_free_module(
    parent,
    input,
    request,
    compiled,
    definition,
    compilation,
    contracts,
    retained_output,
    installed_client_family_provider_count() + 1,
    installed_client_family_providers,
    query_time~,
    component_factory=Some((capacity, prefix, suffix) => {
      construct(capacity, prefix, active => {
        match suffix {
          None => Ok(())
          Some(original) => @infer_host.bind_compute_suffix(active, original)
        }
      })
    }),
  ).map_err(issue => Preparation(issue))
}

///|
// SAME source-free module and compiler vector, one callback per original
// Model occurrence. Keep the optional suffix in the original typed closure;
// JS receives only its existing binder, never an Option/tuple representation.
#export_name("clientProgramPrepareRequestModelsSourceFreeComponentModule")
pub fn client_program_prepare_request_models_source_free_component_module(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  compilation : @publication_host.ClientTaskCompilation,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  retained_output : Bool,
  query_time : @publication_host.ClientQueryTimePreparation?,
  construct : (
    Int,
    @execution.ExecutionCapacity,
    @execution.GeneratedSequence,
    (@infer_host.Execution) -> Result[Unit, @infer_host.Issue],
  ) -> @local.ManagedProvider,
) -> Result[
  @client_local_host.ClientInstalledManagedSourceFreePreparation,
  ClientRequestProgramModuleBridgeIssue,
] {
  @client_local_host.prepare_request_model_source_free_module(
    parent,
    input,
    request,
    compiled,
    definition,
    compilation,
    contracts,
    retained_output,
    installed_client_family_provider_count(),
    installed_client_family_providers,
    query_time~,
    components_factory=Some((index, capacity, prefix, suffix) => {
      construct(index, capacity, prefix, active => {
        match suffix {
          None => Ok(())
          Some(original) => @infer_host.bind_compute_suffix(active, original)
        }
      })
    }),
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramPrepareRequestModelsProviderComponentCaptureModule")
pub fn client_program_prepare_request_models_provider_component_capture_module(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  compilation : @publication_host.ClientTaskCompilation,
  declarations : Array[@client_row_source_host.RowDeclaration],
  providers : Array[@execution.ExecutionCapacity?],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  retained_output : Bool,
  query_time : @publication_host.ClientQueryTimePreparation?,
  construct : (
    Int,
    @execution.ExecutionCapacity,
    @execution.GeneratedSequence,
    (@infer_host.Execution) -> Result[Unit, @infer_host.Issue],
  ) -> @local.ManagedProvider,
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
    declarations,
    query_contract_body,
    evidence_contract_body,
    transport_bytes,
    transport_execution_bytes,
    contracts,
    retained_output,
    installed_client_family_provider_count(),
    installed_client_family_providers,
    query_time~,
    providers=Some(providers),
    components_factory=Some((index, capacity, prefix, suffix) => {
      construct(index, capacity, prefix, active => {
        match suffix {
          None => Ok(())
          Some(original) => @infer_host.bind_compute_suffix(active, original)
        }
      })
    }),
  ).map_err(issue => Preparation(issue))
}

///|
/// Same original complete Limits inventory retained before the one compiler.
/// Project only its existing Model/read/census DATA after the same Request has
/// backed the temporary native containers. No numerical selector runs again.
#export_name("clientProgramPrepareRequestModelsSourceFreePlan")
pub fn client_program_prepare_request_models_source_free_plan(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  original : @client_local_host.ClientInstalledManagedSourceFreePreparation,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrences : Array[@publication_host.ClientInferOccurrence],
  graphs : Array[@publication_host.ClientInferPlanGraph],
  selected : Array[@infer_host.Limits],
) -> Result[
  @client_local_host.ClientInstalledManagedModelPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  client_request_models_plan_projection(
    parent,
    input,
    occurrences,
    graphs,
    selected,
    (model, retained, execution, reservations, holdings, delegations) => {
      @client_local_host.prepare_request_models_source_free_plan(
        parent, input, original, request, compiled, definition, occurrences, graphs,
        model, retained, execution, reservations, holdings, delegations,
      )
    },
  )
}

///|
#export_name("clientProgramPrepareRequestModelsCapturePlan")
pub fn client_program_prepare_request_models_capture_plan(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  original : @client_local_host.ClientInstalledManagedCapturePlan,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrences : Array[@publication_host.ClientInferOccurrence],
  graphs : Array[@publication_host.ClientInferPlanGraph],
  selected : Array[@infer_host.Limits],
) -> Result[
  @client_local_host.ClientInstalledManagedModelPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  client_request_models_plan_projection(
    parent,
    input,
    occurrences,
    graphs,
    selected,
    (model, retained, execution, reservations, holdings, delegations) => {
      @client_local_host.prepare_request_models_capture_plan(
        parent, input, original, request, compiled, definition, occurrences, graphs,
        model, retained, execution, reservations, holdings, delegations,
      )
    },
  )
}

///|
fn client_request_models_plan_projection(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  occurrences : Array[@publication_host.ClientInferOccurrence],
  graphs : Array[@publication_host.ClientInferPlanGraph],
  selected : Array[@infer_host.Limits],
  construct : (
    Array[@resources.LedgerLimits],
    Array[Int64],
    Array[Int64],
    Int,
    Int,
    Int,
  ) -> Result[
    @client_local_host.ClientInstalledManagedModelPlan,
    @client_local_host.ClientInstalledManagedRunIssue,
  ],
) -> Result[
  @client_local_host.ClientInstalledManagedModelPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  let count = selected.length()
  match
    @client_local_host.reserve_request_models_plan_projection(
      parent, input, count,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if selected.length() != count ||
    occurrences.length() != count ||
    graphs.length() != count {
    return Err(ForeignOriginal)
  }
  let model : Array[@resources.LedgerLimits] = []
  let retained : Array[Int64] = []
  let execution : Array[Int64] = []
  let mut reservations = 0
  let mut holdings = 0
  let mut delegations = 0
  for limits in selected {
    let r = limits.input.rows.operation_entries
    let h = limits.input.rows.retained_entries
    let d = limits.input.rows.metadata_entries
    if r < 0 ||
      h < 0 ||
      d < 0 ||
      r > 2147483647 - reservations ||
      h > 2147483647 - holdings ||
      d > 2147483647 - delegations {
      return Err(InsufficientCapacity)
    }
    reservations += r
    holdings += h
    delegations += d
    model.push(limits.model.ledger)
    retained.push(limits.mapping.logical.max_live_value_bytes)
    execution.push(limits.identity.wire.max_bytes.to_int64())
  }
  construct(model, retained, execution, reservations, holdings, delegations)
}

///|
#export_name("clientProgramRequestModelDirectSourceCoordinates")
pub fn client_program_request_model_direct_source_coordinates(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
) -> Result[
  Array[Array[Int]],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  let selected = match
    @client_local_host.request_model_direct_occurrences(parent, input) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let coordinates : Array[Array[Int]] = []
  for
    index in 0..<@publication_host.client_direct_acquisition_occurrence_count(
      selected,
    ) {
    guard @publication_host.client_direct_acquisition_occurrence_at(
        selected, index,
      )
      is Some((stage, input, task)) else {
      return Err(ForeignOriginal)
    }
    coordinates.push([stage, input, task])
  }
  Ok(coordinates)
}
