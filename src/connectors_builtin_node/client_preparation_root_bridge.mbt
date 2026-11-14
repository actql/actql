///|
/// JS-only identity erasure for the fixed ordinary producer receipt. An empty
/// record supplied by a caller is not admitted: the original Node supplier
/// checks membership and purpose before returning its one child port.
#external
type ClientLocalPreparationInputOriginal

///|
#export_name("clientProgramPrepareInstalledEffectCaptureRecovery")
pub fn client_program_prepare_installed_effect_capture_recovery(
  parent : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @client_local_host.ClientInstalledEffectCaptureRecovery,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_effect_capture_recovery(
    parent, prepared, request, definition, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramBeginInstalledEffectCaptureRecovery")
pub fn client_program_begin_installed_effect_capture_recovery(
  original : @client_local_host.ClientInstalledEffectCaptureRecovery,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.begin_installed_effect_capture_recovery(original)
}

///|
#export_name("clientProgramReserveInstalledEffectCaptureRecovery")
pub fn client_program_reserve_installed_effect_capture_recovery(
  original : @client_local_host.ClientInstalledEffectCaptureRecovery,
  encrypted_bytes : Int,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.reserve_installed_effect_capture_recovery(
    original, encrypted_bytes,
  )
}

///|
#export_name("clientProgramRetireInstalledEffectCaptureRecovery")
pub fn client_program_retire_installed_effect_capture_recovery(
  original : @client_local_host.ClientInstalledEffectCaptureRecovery,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.retire_installed_effect_capture_recovery(original)
}

///|
#export_name("clientProgramReserveRequestEffectCaptureRecovery")
pub fn client_program_reserve_request_effect_capture_recovery(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  encrypted_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.reserve_request_effect_capture_recovery(
    parent, input, request, definition, encrypted_bytes, max_wire_bytes, max_nodes,
    max_depth,
  )
}

///|
#export_name("clientProgramReserveRequestModelRecoveryMaterials")
pub fn client_program_reserve_request_model_recovery_materials(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  count : Int,
  wire_at : (Int) -> String,
  containers : Int,
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.reserve_request_model_recovery_materials(
    parent, input, request, definition, count, wire_at, containers,
  )
}

///|
#export_name("clientProgramBorrowRequestModelPlanInput")
pub fn client_program_borrow_request_model_plan_input(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  @client_local_host.ClientRequestPreparationIssue,
] {
  @client_local_host.borrow_request_model_plan_input(parent, input)
}

///|
#export_name("clientProgramPrepareRequestModelContractMaterials")
pub fn client_program_prepare_request_model_contract_materials(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  count : Int,
  wire_at : (Int) -> String,
  container_count : Int,
) -> Result[Unit, ClientRequestProgramModuleBridgeIssue] {
  @client_local_host.prepare_request_model_contract_materials(
    parent, input, count, wire_at, container_count,
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramPrepareRequestModelProviderBinding")
pub fn client_program_prepare_request_model_provider_binding(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  provider_id : String,
  installation : String,
  contract : String,
  configuration : String,
) -> Result[
  @publication.RunEvidenceValue,
  ClientRequestProgramModuleBridgeIssue,
] {
  @client_local_host.prepare_request_model_provider_binding(
    parent, input, provider_id, installation, contract, configuration,
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramPrepareRequestModelSourceFreeModule")
pub fn client_program_prepare_request_model_source_free_module(
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
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramPrepareRequestModelCaptureModule")
pub fn client_program_prepare_request_model_capture_module(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  compilation : @publication_host.ClientTaskCompilation,
  declarations : Array[@client_row_source_host.RowDeclaration],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
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
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramPrepareRequestModelGraph")
pub fn client_program_prepare_request_model_graph(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  occurrence : @publication_host.ClientInferOccurrence,
  execution : @check_environment.ModelExecutionContract,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
) -> Result[
  @publication_host.ClientInferPlanGraph,
  ClientRequestProgramModuleBridgeIssue,
] {
  prepare_request_model_graph_with_file_declarations(
    parent,
    input,
    occurrence,
    execution,
    contracts,
    None,
  )
}

///|
#export_name("clientProgramPrepareRequestDeclaredFileModelGraph")
pub fn client_program_prepare_request_declared_file_model_graph(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  occurrence : @publication_host.ClientInferOccurrence,
  execution : @check_environment.ModelExecutionContract,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  declarations : Array[@client_row_source_host.RowDeclaration],
) -> Result[
  @publication_host.ClientInferPlanGraph,
  ClientRequestProgramModuleBridgeIssue,
] {
  prepare_request_model_graph_with_file_declarations(
    parent,
    input,
    occurrence,
    execution,
    contracts,
    Some(declarations),
  )
}

///|
fn prepare_request_model_graph_with_file_declarations(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  occurrence : @publication_host.ClientInferOccurrence,
  execution : @check_environment.ModelExecutionContract,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  keyed_file_declarations : Array[@client_row_source_host.RowDeclaration]?,
) -> Result[
  @publication_host.ClientInferPlanGraph,
  ClientRequestProgramModuleBridgeIssue,
] {
  let manifests = match client_generated_compilation_manifests() {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @client_local_host.prepare_request_model_graph(
    parent,
    input,
    occurrence,
    execution,
    contracts,
    manifests~,
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    keyed_file_declarations~,
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramPrepareRequestSerializedModelGraph")
pub fn client_program_prepare_request_serialized_model_graph(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  occurrence : @publication_host.ClientInferOccurrence,
  serialization : @publication_host.ClientSerializationPlanGraph,
  execution : @check_environment.ModelExecutionContract,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
) -> Result[
  @publication_host.ClientInferPlanGraph,
  ClientRequestProgramModuleBridgeIssue,
] {
  let manifests = match client_generated_compilation_manifests() {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @client_local_host.prepare_request_model_graph(
    parent,
    input,
    occurrence,
    execution,
    contracts,
    manifests~,
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    serialization=Some(serialization),
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramPrepareRequestModelCompilation")
pub fn client_program_prepare_request_model_compilation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  graph : @publication_host.ClientInferPlanGraph,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
) -> Result[
  @publication_host.ClientTaskCompilation,
  ClientRequestProgramModuleBridgeIssue,
] {
  let manifests = match client_generated_compilation_manifests() {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @client_local_host.prepare_request_model_compilation(
    parent,
    input,
    graph,
    contracts,
    manifests~,
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramPrepareRequestModelsCompilation")
pub fn client_program_prepare_request_models_compilation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  graphs : Array[@publication_host.ClientInferPlanGraph],
  contracts : @client_local_host.ClientInstalledSequenceContracts,
) -> Result[
  @publication_host.ClientTaskCompilation,
  ClientRequestProgramModuleBridgeIssue,
] {
  let manifests = match client_generated_compilation_manifests() {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @client_local_host.prepare_request_models_compilation(
    parent,
    input,
    graphs,
    contracts,
    manifests~,
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramPreparedInstalledManagedModelRequirements")
pub fn client_program_prepared_installed_managed_model_requirements(
  original : @client_local_host.ClientInstalledManagedModelPlan,
) -> Array[Int64] {
  @client_local_host.prepared_installed_managed_model_requirements(original)
}

///|
#export_name("clientProgramPrepareRequestModelReadScope")
pub fn client_program_prepare_request_model_read_scope(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  plan : @client_local_host.ClientInstalledManagedModelPlan,
) -> Result[
  @publication_host.ClientModelReadScope,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_request_model_read_scope(parent, input, plan)
}

///|
// The same retained provider supplies its actual quantity declaration before
// Request/Run binding. Core intersects the original execution contract and
// Resource enforces its existing one-shot preparation-only configuration.
#export_name("clientProgramPrepareRequestModelReadScopeWithQuantities")
pub fn client_program_prepare_request_model_read_scope_with_quantities(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  plan : @client_local_host.ClientInstalledManagedModelPlan,
  tokens : Int64,
  cost_units : Int64,
  duration_ms : Int64,
) -> Result[
  @publication_host.ClientModelReadScope,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_request_model_read_scope(
    parent,
    input,
    plan,
    quantity_limits=Some({ tokens, cost_units, duration_ms, }),
  )
}

///|
#export_name("clientProgramCompleteRequestModelPreparation")
pub fn client_program_complete_request_model_preparation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  plan : @client_local_host.ClientInstalledManagedModelPlan,
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.complete_request_model_preparation(parent, input, plan)
}

///|
#export_name("clientProgramAdoptRequestModelPreparation")
pub fn client_program_adopt_request_model_preparation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  request : @publication_host.ClientRequestIdentity,
  scope : @publication_host.ClientModelReadScope,
) -> Result[
  @client_local_host.ClientInstalledManagedRun,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_request_model_managed_run(parent, request, scope)
}

///|
/// The fixed manager stores this unstarted admission before calling the
/// separate phase driver. A later rejection/unknown outcome must clean this
/// same original and cannot acquire another child for the same receipt.
#export_name("clientProgramPrepareLocalPreparationAdmission")
pub fn client_program_prepare_local_preparation_admission(
  original : @resources.OriginalNodeManagedRunReference,
  input : ClientLocalPreparationInputOriginal,
) -> Result[
  @resources.NodePreparationAdmission[ClientLocalPreparationInputOriginal],
  @resources.ImportedChildLedgerIssue,
] {
  @resources.prepare_node_local_preparation_admission(original, input)
}

///|
/// The original cleanup census refuses while a preparation debit or child
/// duty remains. This operation is not a replacement for phase retirement.
#export_name("clientProgramCleanupLocalPreparationAdmission")
pub fn client_program_cleanup_local_preparation_admission(
  original : @resources.NodePreparationAdmission[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[Unit, @resources.ImportedChildLedgerIssue] {
  @resources.cleanup_node_preparation_admission(original)
}

///|
#export_name("clientProgramRequestPreparationControl")
pub fn client_program_request_preparation_control(
  policy : @client_local_host.ClientLocalResourcePolicy,
) -> Array[Int64] {
  match @client_local_host.client_request_preparation_control_capacity(policy) {
    Some((retained, execution)) => [retained, execution]
    None => []
  }
}

///|
#export_name("clientProgramBeginRequestPreparation")
pub fn client_program_begin_request_preparation(
  initial : @resources.NodePreparationAdmission[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  policy : @client_local_host.ClientLocalResourcePolicy,
) -> Result[
  @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  @client_local_host.ClientRequestPreparationIssue,
] {
  @client_local_host.begin_request_preparation(initial, input, policy)
}

///|
#export_name("clientProgramReserveRequestSnapshot")
pub fn client_program_reserve_request_snapshot(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  units : Int64,
  values : Int64,
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.reserve_request_snapshot(parent, input, units, values)
}

///|
#export_name("clientProgramRequestSnapshotCapacityRefusal")
pub fn client_program_request_snapshot_capacity_refusal(
  result : Result[Unit, @client_local_host.ClientRequestPreparationIssue],
) -> (String, String, Int64, Int64, Int64, Int64)? {
  match result {
    Err(SnapshotCapacityExceeded(original, value)) => {
      let dimension = match original {
        Resource(RetentionLimit) => "retention"
        Resource(ExecutionLimit) => "execution"
        _ => return None
      }
      if value.phase != "request_snapshot" || value.dimension != dimension {
        return None
      }
      Some(
        (
          value.phase,
          value.dimension,
          value.required_retention,
          value.required_execution,
          value.available_retention,
          value.available_execution,
        ),
      )
    }
    _ => None
  }
}

///|
#export_name("clientProgramPrepareRequestNativeProgramInput")
pub fn client_program_prepare_request_native_program_input(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  captured : NativeJsonValue,
  parameters : NativeJsonValue,
  limits : @stage_syntax.Limits,
) -> Result[
  @client_local_host.ClientProgramJsonPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
  @client_local_host.ClientRequestPreparationIssue,
] {
  @client_local_host.prepare_request_native_program_input(
    parent,
    input,
    captured,
    native_json_reader,
    limits,
    supplied=if native_json_parameter_is_absent(parameters) {
      None
    } else {
      Some(parameters)
    },
  )
}

///|
#export_name("clientProgramParseRequestQuerySyntax")
pub fn client_program_parse_request_query_syntax(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  document : String,
  spelling : String,
) -> Result[
  @query_syntax.Query,
  @client_local_host.ClientRequestQuerySyntaxIssue,
] {
  let format = match @source_frontend.select_format(spelling) {
    Err(issue) =>
      return Err(
        @client_local_host.ClientRequestQuerySyntaxIssue::Frontend(issue),
      )
    Ok(value) => value
  }
  @client_local_host.parse_request_query_syntax(parent, input, document, format)
}

///|
#export_name("clientProgramLowerRequestPublishedQuery")
pub fn client_program_lower_request_published_query(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  environment : @program_check.CheckEnvironment,
  declarations : String?,
  public_primary : Bool,
) -> Result[
  (
    @source_frontend.Lowered,
    @program_check.PreparedSourceCatalog,
    @source_frontend.DiagnosticSource,
  ),
  @client_local_host.ClientRequestQueryLoweringIssue,
] {
  @client_local_host.lower_request_published_query(
    parent,
    input,
    publication,
    environment,
    declarations,
    public_primary~,
  )
}

///|
#export_name("clientProgramPreparedRequestQueryLowering")
pub fn client_program_prepared_request_query_lowering(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
) -> Result[
  (
    @source_frontend.Lowered,
    @program_check.PreparedSourceCatalog,
    @source_frontend.DiagnosticSource,
  ),
  @client_local_host.ClientRequestQueryLoweringIssue,
] {
  @client_local_host.prepared_request_query_lowering(parent, input)
}

///|
/// The existing parent retains this exact Source child on the same original input.
#export_name("clientProgramPrepareRequestProgramJson")
pub fn client_program_prepare_request_program_json(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  document : String,
  limits : @stage_syntax.Limits,
) -> Result[
  @client_local_host.ClientProgramJsonPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
  @client_local_host.ClientRequestPreparationIssue,
] {
  @client_local_host.prepare_request_program_json_preparation(
    parent, input, document, limits,
  )
}

///|
#export_name("clientProgramAdvanceProgramJsonPreparation")
pub fn client_program_advance_program_json_preparation(
  owner : @client_local_host.ClientProgramJsonPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
  quantum : Int,
) -> Result[
  @source.JsonSourcePreflightPoll,
  @client_local_host.ClientProgramJsonPreparationIssue,
] {
  @client_local_host.advance_program_json_preparation(owner, quantum)
}

///|
#export_name("clientProgramFinishProgramJsonPreparation")
pub fn client_program_finish_program_json_preparation(
  owner : @client_local_host.ClientProgramJsonPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramJsonPreparationIssue] {
  @client_local_host.finish_program_json_preparation(owner)
}

///|
#export_name("clientProgramConstructProgramJsonPreparation")
pub fn client_program_construct_program_json_preparation(
  owner : @client_local_host.ClientProgramJsonPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramJsonPreparationIssue] {
  @client_local_host.construct_program_json_preparation(owner)
}

///|
#export_name("clientProgramReconcileProgramJsonPreparationStructure")
pub fn client_program_reconcile_program_json_preparation_structure(
  owner : @client_local_host.ClientProgramJsonPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramJsonPreparationIssue] {
  @client_local_host.reconcile_program_json_preparation_structure(owner)
}

///|
/// The parent takes and retains its original Program; no capacity or replacement body escapes.
#export_name("clientProgramPrepareRequestProgramCheck")
pub fn client_program_prepare_request_program_check(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  environment : @program_check.CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : @program_check.CheckLimits,
  source_catalog : @program_check.PreparedSourceCatalog?,
  source_preparation : @stage_parameters.Source?,
) -> Result[
  @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
  @client_local_host.ClientRequestPreparationIssue,
] {
  @client_local_host.prepare_request_program_check_preparation(
    parent,
    input,
    environment,
    supplied,
    evidence,
    limits,
    source_catalog~,
    source_preparation~,
  )
}

///|
#export_name("clientProgramPrepareProgramCheckInput")
pub fn client_program_prepare_program_check_input(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.prepare_program_check_input(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckPrelude")
pub fn client_program_prepare_program_check_prelude(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckPrelude,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_prelude(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckRegistry")
pub fn client_program_prepare_program_check_registry(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckRegistry,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_registry(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckContents")
pub fn client_program_prepare_program_check_contents(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckRegistry,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_contents(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckReferences")
pub fn client_program_prepare_program_check_references(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckRegistry,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_references(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckPolicies")
pub fn client_program_prepare_program_check_policies(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckRegistry,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_policies(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckValues")
pub fn client_program_prepare_program_check_values(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckRegistry,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_values(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckViews")
pub fn client_program_prepare_program_check_views(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckRegistry,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_views(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckCarriers")
pub fn client_program_prepare_program_check_carriers(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckRegistry,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_carriers(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckRequests")
pub fn client_program_prepare_program_check_requests(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckRegistry,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_requests(owner)
}

///|
#export_name("clientProgramReconcileProgramCheckRegistry")
pub fn client_program_reconcile_program_check_registry(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.reconcile_program_check_registry(owner)
}

///|
#export_name("clientProgramReconcileProgramCheckContents")
pub fn client_program_reconcile_program_check_contents(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.reconcile_program_check_contents(owner)
}

///|
#export_name("clientProgramReconcileProgramCheckReferences")
pub fn client_program_reconcile_program_check_references(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.reconcile_program_check_references(owner)
}

///|
#export_name("clientProgramReconcileProgramCheckPolicies")
pub fn client_program_reconcile_program_check_policies(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.reconcile_program_check_policies(owner)
}

///|
#export_name("clientProgramReconcileProgramCheckValues")
pub fn client_program_reconcile_program_check_values(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.reconcile_program_check_values(owner)
}

///|
#export_name("clientProgramReconcileProgramCheckViews")
pub fn client_program_reconcile_program_check_views(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.reconcile_program_check_views(owner)
}

///|
#export_name("clientProgramReconcileProgramCheckCarriers")
pub fn client_program_reconcile_program_check_carriers(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.reconcile_program_check_carriers(owner)
}

///|
#export_name("clientProgramReconcileProgramCheckRequests")
pub fn client_program_reconcile_program_check_requests(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.reconcile_program_check_requests(owner)
}

///|
#export_name("clientProgramAbortRequestPreparation")
pub fn client_program_abort_request_preparation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.abort_request_preparation_after_cleanup(parent)
}

///|
/// Immutable failure DATA only; no owner, Ledger, reservation or grant escapes.
#export_name("clientProgramPreparationCapacityRefusal")
pub fn client_program_preparation_capacity_refusal(
  issue : @client_local_host.ClientClosedValuesPreparationIssue,
) -> (String, String, Int64, Int64, Int64, Int64)? {
  @client_local_host.closed_values_preparation_capacity_refusal(issue)
}

///|
#export_name("strategyCapturedRunPreparationLimits")
pub fn strategy_captured_run_preparation_limits(
  original : @publication.CapturedRunIssuancePreparation,
) -> Array[Int]? {
  @publication.captured_run_preparation_limits(original).map(values => {
    [values.0, values.1, values.2]
  })
}

///|
#export_name("strategyBeginOriginalEffectFreeCapturedRun")
pub fn strategy_begin_original_effect_free_captured_run(
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  snapshots : Array[@publication.CapturedResultSnapshot],
  advances : Array[@publication.PendingSourceStateAdvance],
  authoring : @publication.RunEvidenceValue,
  models : Array[@publication.RunEvidenceValue],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
  content_generations : Array[@publication.BoundContentGeneration],
) -> @publication.CapturedRunIssuancePreparation {
  @publication.start_original_effect_free_captured_run(
    run_definition,
    invocation,
    definitions,
    artifacts,
    manifest,
    receipt,
    snapshots,
    advances,
    authoring,
    models,
    max_wire_bytes,
    max_nodes,
    max_depth,
    max_workspace,
    content_generations~,
  )
}

///|
/// The SAME installation initialization original, before Environment/sequence
/// contracts or Source loading. It is never a completed Request preparation.
#export_name("clientProgramBeginHostInitializationPreparation")
pub fn client_program_begin_host_initialization_preparation(
  initial : @resources.NodePreparationAdmission[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  policy : @client_local_host.ClientLocalResourcePolicy,
) -> Result[
  @client_local_host.ClientHostInitializationPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  @client_local_host.ClientHostInitializationIssue,
] {
  @client_local_host.begin_host_initialization_preparation(
    initial, input, policy,
  )
}

///|
#export_name("clientProgramCloseHostInitializationPreparation")
pub fn client_program_close_host_initialization_preparation(
  original : @client_local_host.ClientHostInitializationPreparation[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[Unit, @client_local_host.ClientHostInitializationIssue] {
  @client_local_host.close_host_initialization_preparation(original)
}

///|
#export_name("clientProgramPrepareRequestComputationCheck")
pub fn client_program_prepare_request_computation_check(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  environment : @program_check.CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  program_limits : @publication_host.ClientProgramPreparationLimits,
  effect_limits : @publication_host.ClientEffectComputationLimits,
  source_catalog : @program_check.PreparedSourceCatalog?,
  source_preparation : @stage_parameters.Source?,
) -> Result[
  @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
  @client_local_host.ClientRequestPreparationIssue,
] {
  @client_local_host.prepare_request_computation_check_preparation(
    parent,
    input,
    environment,
    supplied,
    evidence,
    program_limits,
    effect_limits,
    source_catalog~,
    source_preparation~,
  )
}

///|
/// No raw Prepared leaves this terminal bridge. The same parent retains the
/// compiled body until its actual installed Plan and body borrow are complete.
#export_name("clientProgramFinishRequestComputation")
pub fn client_program_finish_request_computation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  environment : @program_check.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
) -> Result[String, @client_local_host.ClientRequestTerminalIssue] {
  @client_local_host.finish_request_checked_computation(
    parent, input, environment, publication,
  ).map(kind => {
    match kind {
      @client_local_host.Pure => "effect_free"
      @client_local_host.Effect => "effectful"
    }
  })
}

///|
/// The checked Request original, not a new raw or no-plan preparation. The
/// existing installed contracts/factory construct the selected module once.
pub suberror ClientRequestProgramModuleBridgeIssue {
  Manifests(@publication_host.ClientCompilationManifestIssue)
  Preparation(@client_local_host.ClientRequestProgramPlanIssue)
}

///|
/// Same Request artifact before module construction; existing original-sum
/// Run issuers consume it without a second compiler or a mode classifier.
#export_name("clientProgramPrepareRequestProgramCompilation")
pub fn client_program_prepare_request_program_compilation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  retained_output : Bool,
) -> Result[
  @publication_host.ClientRunCompilation,
  ClientRequestProgramModuleBridgeIssue,
] {
  let compilation_limits = match
    @client_local_host.request_program_compilation_limits(parent, input) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  let manifests = match client_generated_compilation_manifests() {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @client_local_host.prepare_request_program_compilation(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits~,
    retained_output~,
    provider_factory=installed_client_family_providers,
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramReserveRequestQueryTimeInvocation")
pub fn client_program_reserve_request_query_time_invocation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  compilation : @publication_host.ClientRunCompilation,
) -> Result[Unit, ClientRequestProgramModuleBridgeIssue] {
  @client_local_host.reserve_request_query_time_invocation(
    parent, input, compilation,
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramPrepareRequestProgramModuleBody")
pub fn client_program_prepare_request_program_module_body(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  retained_output : Bool,
  invocation : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
    @publication_host.ClientCompiledRun,
    @publication.PublicationContract,
  )?,
  source_free_max_work : Int?,
) -> Result[Unit, ClientRequestProgramModuleBridgeIssue] {
  let compilation_limits = match
    @client_local_host.request_program_compilation_limits(parent, input) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  let manifests = match client_generated_compilation_manifests() {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @client_local_host.prepare_request_program_module_body(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits~,
    retained_output~,
    provider_factory=installed_client_family_providers,
    invocation~,
    source_free_max_work~,
    runtime_compilation_limits=Some(compilation_limits),
  ).map_err(issue => Preparation(issue))
}

///|
/// Read only the original installed sequence refusal. Foreign/current/cleanup
/// and all unclassified failures remain uncertain; no input is checked again.
#export_name("clientProgramRequestProgramModuleIssueCode")
pub fn client_program_request_program_module_issue_code(
  result : Result[Unit, ClientRequestProgramModuleBridgeIssue],
) -> String? {
  match result {
    Err(Preparation(CapacityExceeded(_))) =>
      Some("source_free_capacity_exceeded")
    Err(Preparation(Installed(MetadataCapacityUnavailable))) =>
      Some("source_free_metadata_capacity_unavailable")
    Err(Preparation(Installed(Sequence(ValuesFailure(_, ValuesLimit))))) =>
      Some("values_profile_unsupported")
    // The original error owner projects only its exact sequence-budget cause.
    // No caller reconstructs this read-only error or treats a current/foreign
    // or general construction failure as a known input refusal.
    Err(Preparation(issue)) =>
      if @client_local_host.request_program_plan_issue_is_sequence_limit(issue) {
        Some("check_compile_limit")
      } else {
        None
      }
    _ => None
  }
}

///|
/// Diagnostic DATA from this exact typed module refusal, never an allowance.
#export_name("clientProgramRequestProgramModuleCapacityRefusal")
pub fn client_program_request_program_module_capacity_refusal(
  result : Result[Unit, ClientRequestProgramModuleBridgeIssue],
) -> (String, String, Int64, Int64, Int64, Int64)? {
  match result {
    Err(Preparation(CapacityExceeded(value))) =>
      Some(
        (
          value.phase,
          value.dimension,
          value.required_retention,
          value.required_execution,
          value.available_retention,
          value.available_execution,
        ),
      )
    _ => None
  }
}

///|
#export_name("clientProgramBorrowRequestProgramPreparation")
pub fn client_program_borrow_request_program_preparation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  @client_local_host.ClientRequestPreparationIssue,
] {
  @client_local_host.borrow_request_program_preparation(parent)
}

///|
#export_name("clientProgramAdoptRequestProgramPreparation")
pub fn client_program_adopt_request_program_preparation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @client_local_host.ClientInstalledManagedRun,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_request_program_managed_run(parent, request)
}

///|
#export_name("clientProgramPrepareRequestSubmittedIntent")
pub fn client_program_prepare_request_submitted_intent(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  captured : NativeJsonValue,
) -> Result[String, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.prepare_request_submitted_intent(
    parent, input, captured, native_json_reader,
  )
}

///|
#export_name("clientProgramRetainRequestSubmittedIntent")
pub fn client_program_retain_request_submitted_intent(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  intent : @publication_host.ClientSubmittedIntent,
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.retain_request_submitted_intent(parent, input, intent)
}

///|
#export_name("clientProgramFinishRequestSubmittedIntent")
pub fn client_program_finish_request_submitted_intent(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.finish_request_submitted_intent(parent, input)
}

///|
#export_name("clientProgramReserveRequestRetainedProgramMaterial")
pub fn client_program_reserve_request_retained_program_material(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  wire : String,
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.reserve_request_retained_program_material(
    parent, input, wire,
  )
}

///|
#export_name("clientProgramRequestSubmittedIntentOriginal")
pub fn client_program_request_submitted_intent_original(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
) -> @publication_host.ClientSubmittedIntent? {
  @client_local_host.request_submitted_intent_original(parent, input)
}

///|
#export_name("clientProgramBorrowRequestProgramPlanInput")
pub fn client_program_borrow_request_program_plan_input(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  @client_local_host.ClientRequestPreparationIssue,
] {
  @client_local_host.borrow_request_program_plan_input(parent, input)
}

///|
/// The Host supplies the complete original capture inventory on the same
/// Request before this constructor. These immutable bounds grant no backing,
/// read permission or physical-child retirement acknowledgement.
#export_name("clientProgramInstalledManagedCapturePlanPrepare")
pub fn client_program_installed_managed_capture_plan_prepare(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  captures : Array[@client_local_host.ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  retained_output : Bool,
  query_time : @publication_host.ClientQueryTimePreparation?,
) -> Result[
  @client_local_host.ClientInstalledManagedCapturePlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_managed_capture_plan(
    prepared,
    request,
    captures,
    transport_bytes,
    transport_execution_bytes,
    contracts,
    values_body,
    fragment_body,
    ordered_body,
    retained_output~,
    provider_factory=installed_client_family_providers,
    query_time~,
    runtime_admission=true,
  )
}

///|
#export_name("clientProgramAdoptRequestCapturePreparation")
pub fn client_program_adopt_request_capture_preparation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @client_local_host.ClientInstalledManagedRun,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_request_capture_managed_run(parent, request)
}

///|
#export_name("clientProgramBorrowRequestEffectPlanInput")
pub fn client_program_borrow_request_effect_plan_input(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
) -> Result[
  @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientEffectComputation,
  ],
  @client_local_host.ClientRequestPreparationIssue,
] {
  @client_local_host.borrow_request_effect_plan_input(parent, input)
}

///|
#export_name("clientProgramReserveRequestEffectOriginalMaterial")
pub fn client_program_reserve_request_effect_original_material(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  prepared : @publication_host.PreparedClientEffectComputation,
  count : Int,
  wire_at : (Int) -> String,
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.reserve_request_effect_original_material(
    parent, input, prepared, count, wire_at,
  )
}

///|
#export_name("clientProgramCompleteRequestEffectPreparation")
pub fn client_program_complete_request_effect_preparation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.complete_request_effect_preparation(parent, input, plan)
}

///|
#export_name("clientProgramAdoptRequestEffectPreparation")
pub fn client_program_adopt_request_effect_preparation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @client_local_host.ClientInstalledManagedRun,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_request_effect_managed_run(parent, request)
}

///|
#export_name("clientProgramEffectPreparationInputRead")
pub fn client_program_effect_preparation_input_read(
  original : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientEffectComputation,
  ],
) -> @publication_host.PreparedClientEffectComputation? {
  @resources.preparation_body_borrow_value(original)
}

///|
#export_name("clientProgramEffectPreparationInputReturn")
pub fn client_program_effect_preparation_input_return(
  original : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientEffectComputation,
  ],
) -> Result[Bool, @resources.PreparationCapacityIssue] {
  @resources.return_preparation_body_borrow(original)
}

///|
#export_name("clientProgramEffectPreparationInputSibling")
pub fn client_program_effect_preparation_input_sibling(
  original : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientEffectComputation,
  ],
) -> Result[
  @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientEffectComputation,
  ],
  @resources.PreparationCapacityIssue,
] {
  @resources.borrow_preparation_body_sibling(original)
}

///|
#export_name("clientProgramEffectPreparationInputRetirementStarted")
pub fn client_program_effect_preparation_input_retirement_started(
  original : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientEffectComputation,
  ],
) -> Bool {
  @resources.preparation_body_retirement_started(original)
}

///|
#export_name("clientProgramPrepareRequestNativeComputation")
pub fn client_program_prepare_request_native_computation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  captured : NativeJsonValue,
  parameters : NativeJsonValue,
  environment : @program_check.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  values_max_rows : Int?,
) -> Result[Unit, @client_local_host.ClientRequestTerminalIssue] {
  let selected = match
    @client_local_host.request_default_program_preparation_limits(parent, input) {
    Ok(limits) => limits
    Err(issue) => return Err(issue)
  }
  @client_local_host.prepare_request_native_computation_check(
    parent,
    input,
    captured,
    native_json_reader,
    environment,
    publication,
    [],
    { ..selected, values_max_rows, },
    @publication_host.client_standard_effect_computation_limits(),
    supplied=if native_json_parameter_is_absent(parameters) {
      None
    } else {
      Some(parameters)
    },
  )
}

///|
#export_name("clientProgramRequestParametersOriginal")
pub fn client_program_request_parameters_original(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
) -> Result[@decode.Cursor?, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.request_preparation_parameters_original(parent, input)
}

///|
/// SAME original Request accounting, including its adopted body continuation.
#export_name("clientProgramRequestPreparationAccounting")
pub fn client_program_request_preparation_accounting(
  owner : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
) -> (Int64, Int64, Int64, Int64, Int64, Int64) {
  @client_local_host.request_preparation_accounting(owner)
}

///|
/// SAME SDK native Source/Parameters, original Request and installed context.
/// Fixed own-DATA extraction observes no application getter or source I/O.
#export_name("clientProgramPrepareRequestSourceComputation")
pub fn client_program_prepare_request_source_computation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  captured : NativeJsonValue,
  parameters : NativeJsonValue,
  environment : @program_check.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  values_max_rows : Int?,
) -> Result[Unit, @client_local_host.ClientRequestTerminalIssue] {
  @client_local_host.prepare_request_default_source_computation_check(
    parent,
    input,
    captured,
    native_json_reader,
    environment,
    publication,
    [],
    values_max_rows,
    @publication_host.client_standard_effect_computation_limits(),
    supplied=if native_json_parameter_is_absent(parameters) {
      None
    } else {
      Some(parameters)
    },
  )
}

///|
// SAME original Request after semantic check, before compiler/Plan selection.
#export_name("clientProgramPrepareRequestPolicySubjects")
pub fn client_program_prepare_request_policy_subjects(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  environment : @program_check.CheckEnvironment,
) -> Result[Int, @client_local_host.ClientRequestTerminalIssue] {
  @client_local_host.prepare_request_computation_policy_subjects(
    parent,
    input,
    environment,
    client_request_value_policy_limits(),
  )
}

///|
#export_name("clientProgramReadRequestPolicySubject")
pub fn client_program_read_request_policy_subject(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  environment : @program_check.CheckEnvironment,
  index : Int,
) -> Result[String, @client_local_host.ClientRequestTerminalIssue] {
  @client_local_host.request_computation_policy_subject(
    parent, input, environment, index,
  )
}

///|
// Invoke once per original descriptor, including an explicit verifier decline.
#export_name("clientProgramBindRequestPolicySubject")
pub fn client_program_bind_request_policy_subject(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  environment : @program_check.CheckEnvironment,
  index : Int,
  policy_cid : String?,
) -> Result[Unit, @client_local_host.ClientRequestTerminalIssue] {
  @client_local_host.bind_request_computation_policy_subject(
    parent, input, environment, index, policy_cid,
  )
}

///|
// Finish work and supplement this SAME child; no selected Environment escapes.
#export_name("clientProgramFinishRequestPolicySubjects")
pub fn client_program_finish_request_policy_subjects(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  environment : @program_check.CheckEnvironment,
) -> Result[Unit, @client_local_host.ClientRequestTerminalIssue] {
  @client_local_host.finish_request_computation_policy_subjects(
    parent, input, environment,
  )
}

///|
#export_name("clientProgramPrepareRequestEffectModelReadScope")
pub fn client_program_prepare_request_effect_model_read_scope(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
) -> Result[
  @publication_host.ClientModelReadScope,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_request_effect_model_read_scope(
    parent, input, plan,
  )
}

///|
#export_name("clientProgramPrepareRequestEffectModelReadScopeWithQuantities")
pub fn client_program_prepare_request_effect_model_read_scope_with_quantities(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  tokens : Int64,
  cost_units : Int64,
  duration_ms : Int64,
) -> Result[
  @publication_host.ClientModelReadScope,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_request_effect_model_read_scope(
    parent,
    input,
    plan,
    quantity_limits=Some({ tokens, cost_units, duration_ms, }),
  )
}

///|
#export_name("clientProgramAdoptRequestEffectModelPreparation")
pub fn client_program_adopt_request_effect_model_preparation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  request : @publication_host.ClientRequestIdentity,
  scope : @publication_host.ClientModelReadScope,
) -> Result[
  @client_local_host.ClientInstalledManagedRun,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_request_effect_model_managed_run(
    parent, request, scope,
  )
}

///|
#export_name("clientProgramBorrowRequestContentPlanInput")
pub fn client_program_borrow_request_content_plan_input(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  @client_local_host.ClientRequestPreparationIssue,
] {
  @client_local_host.borrow_request_content_plan_input(parent, input)
}

///|
#export_name("clientProgramCompleteRequestContentPreparation")
pub fn client_program_complete_request_content_preparation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  selected : @client_local_host.ClientInstalledManagedKeyedPreparation,
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.complete_request_content_preparation(
    parent, input, request, selected,
  )
}

///|
#export_name("clientProgramCompleteRequestSerializationPreparation")
pub fn client_program_complete_request_serialization_preparation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  selected : @client_local_host.ClientInstalledManagedSerializationPreparation,
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.complete_request_serialization_preparation(
    parent, input, selected,
  )
}

///|
/// The original Request owns measurement, Graph construction and later compilation.
#export_name("clientProgramPrepareRequestSerializationGraph")
pub fn client_program_prepare_request_serialization_graph(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  task : Int,
  step : Int,
  policy_cid : String,
  policy_wire : String,
  max_rows : Int,
  max_bytes : Int,
  include_results : Bool,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
) -> Result[
  @publication_host.ClientSerializationPlanGraph,
  ClientRequestProgramModuleBridgeIssue,
] {
  let manifests = match client_generated_compilation_manifests() {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @client_local_host.prepare_request_serialization_graph(
    parent,
    input,
    task,
    step,
    policy_cid,
    policy_wire,
    max_rows,
    max_bytes,
    include_results,
    contracts,
    manifests~,
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramPrepareRequestAcquiredSerializationGraph")
pub fn client_program_prepare_request_acquired_serialization_graph(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  task : Int,
  step : Int,
  max_rows : Int,
  max_bytes : Int,
  include_results : Bool,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
) -> Result[
  @publication_host.ClientSerializationPlanGraph,
  ClientRequestProgramModuleBridgeIssue,
] {
  let manifests = match client_generated_compilation_manifests() {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @client_local_host.prepare_request_acquired_serialization_graph(
    parent,
    input,
    task,
    step,
    max_rows,
    max_bytes,
    include_results,
    contracts,
    manifests~,
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramPrepareRequestSerializationCompilation")
pub fn client_program_prepare_request_serialization_compilation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  component : @publication_host.ClientSerializationPlanGraph,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
) -> Result[
  @publication_host.ClientTaskCompilation,
  ClientRequestProgramModuleBridgeIssue,
] {
  let manifests = match client_generated_compilation_manifests() {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @client_local_host.prepare_request_serialization_compilation(
    parent,
    input,
    component,
    contracts,
    manifests~,
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramPrepareRequestKeyedSerializationCompilation")
pub fn client_program_prepare_request_keyed_serialization_compilation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  selected : @client_local_host.ClientInstalledManagedKeyedPreparation,
  component : @publication_host.ClientSerializationPlanGraph,
) -> Result[
  @publication_host.ClientTaskCompilation,
  ClientRequestProgramModuleBridgeIssue,
] {
  let manifests = match client_generated_compilation_manifests() {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @client_local_host.prepare_request_keyed_serialization_compilation(
    parent,
    input,
    selected,
    component,
    manifests~,
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramAdoptRequestContentPreparation")
pub fn client_program_adopt_request_content_preparation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @client_local_host.ClientInstalledManagedRun,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_request_content_managed_run(parent, request)
}

///|
#export_name("clientProgramInstalledManagedKeyedContentPrepare")
pub fn client_program_installed_managed_keyed_content_prepare(
  prepared : @publication_host.PreparedClientProgram,
  direct : @client_local_host.ClientInstalledCaptureCapacity,
  keyed : @publication_host.ClientKeyedAcquisition,
  declaration : @client_row_source_host.RowDeclaration,
  max_page_bytes : Int,
  max_text_bytes : Int,
  row_work : Int,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  max_bytes : Int,
  max_work : Int,
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  task : Int,
  step : Int,
  prefix_retained_bytes : Int64,
  prefix_execution_bytes : Int64,
) -> Result[
  @client_local_host.ClientInstalledManagedKeyedPreparation,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_managed_keyed_content(
    prepared,
    direct,
    keyed,
    declaration,
    @client_local_host.installed_keyed_row_limits(
      max_page_bytes, max_text_bytes, row_work,
    ),
    transport_bytes,
    transport_execution_bytes,
    max_bytes,
    max_work,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    task,
    step,
    prefix_retained_bytes,
    prefix_execution_bytes,
  )
}

///|
// The SAME Effect Model occurrence owns this intermediate Content component.
#export_name("clientProgramPrepareRequestModelSerializationGraph")
pub fn client_program_prepare_request_model_serialization_graph(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  occurrence : @publication_host.ClientInferOccurrence,
  task : Int,
  step : Int,
  policy_cid : String,
  policy_wire : String,
  max_rows : Int,
  max_bytes : Int,
  include_results : Bool,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
) -> Result[
  @publication_host.ClientSerializationPlanGraph,
  ClientRequestProgramModuleBridgeIssue,
] {
  let manifests = match client_generated_compilation_manifests() {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @client_local_host.prepare_request_serialization_graph(
    parent,
    input,
    task,
    step,
    policy_cid,
    policy_wire,
    max_rows,
    max_bytes,
    include_results,
    contracts,
    manifests~,
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    model_occurrence=Some(occurrence),
  ).map_err(issue => Preparation(issue))
}

///|
// The SAME Effect Model occurrence owns this intermediate Content component.
#export_name("clientProgramPrepareRequestModelAcquiredSerializationGraph")
pub fn client_program_prepare_request_model_acquired_serialization_graph(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  occurrence : @publication_host.ClientInferOccurrence,
  task : Int,
  step : Int,
  max_rows : Int,
  max_bytes : Int,
  include_results : Bool,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
) -> Result[
  @publication_host.ClientSerializationPlanGraph,
  ClientRequestProgramModuleBridgeIssue,
] {
  let manifests = match client_generated_compilation_manifests() {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @client_local_host.prepare_request_acquired_serialization_graph(
    parent,
    input,
    task,
    step,
    max_rows,
    max_bytes,
    include_results,
    contracts,
    manifests~,
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    model_occurrence=Some(occurrence),
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramPrepareRequestModelsReadScopes")
pub fn client_program_prepare_request_models_read_scopes(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  plan : @client_local_host.ClientInstalledManagedModelPlan,
) -> Result[
  Array[@publication_host.ClientModelReadScope],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_request_models_read_scopes(parent, input, plan)
}

///|
#export_name("clientProgramPrepareRequestModelsReadScopesWithQuantities")
pub fn client_program_prepare_request_models_read_scopes_with_quantities(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  plan : @client_local_host.ClientInstalledManagedModelPlan,
  tokens : Int64,
  cost_units : Int64,
  duration_ms : Int64,
) -> Result[
  Array[@publication_host.ClientModelReadScope],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_request_models_read_scopes(
    parent,
    input,
    plan,
    quantity_limits=Some({ tokens, cost_units, duration_ms, }),
  )
}

///|
#export_name("clientProgramAdoptRequestModelsPreparation")
pub fn client_program_adopt_request_models_preparation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  request : @publication_host.ClientRequestIdentity,
  scopes : Array[@publication_host.ClientModelReadScope],
) -> Result[
  @client_local_host.ClientInstalledManagedRun,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  guard scopes.get(0) is Some(first) else { return Err(ForeignOriginal) }
  @client_local_host.begin_request_model_managed_run(
    parent,
    request,
    first,
    scopes=Some(scopes),
  )
}

///|
fn prepare_request_model_recovery_scopes_original(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  graphs : Array[@publication_host.ClientInferPlanGraph],
  selected : Array[@infer_host.Limits],
  model_retained_bytes : Array[Int64],
  model_execution_bytes : Array[Int64],
  read_retained_bytes : Array[Int64],
  read_execution_bytes : Array[Int64],
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
  quantities : @resources.QuantityAmounts?,
) -> Result[
  Array[@publication_host.ClientModelReadScope],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  let count = graphs.length()
  guard count > 0 &&
    selected.length() == count &&
    model_retained_bytes.length() == count &&
    model_execution_bytes.length() == count &&
    read_retained_bytes.length() == count &&
    read_execution_bytes.length() == count else {
    return Err(ForeignOriginal)
  }
  let mut total : @resources.LedgerLimits = {
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 0L,
  }
  for index in 0..<count {
    let bounds = selected[index]
    guard model_retained_bytes[index] >= bounds.model.ledger.retained_bytes &&
      model_execution_bytes[index] >= bounds.model.ledger.execution_bytes &&
      max_reservations >= bounds.input.rows.operation_entries &&
      max_holdings >= bounds.input.rows.retained_entries &&
      max_delegations >= bounds.input.rows.metadata_entries &&
      @resources.add_ledger_limits(total, {
        ..bounds.model.ledger,
        retained_bytes: model_retained_bytes[index],
        execution_bytes: model_execution_bytes[index],
      })
      is Some(next) else {
      return Err(InsufficientCapacity)
    }
    total = next
  }
  @client_local_host.prepare_request_model_recovery_read_scopes(
    parent,
    input,
    request,
    definition,
    prepared,
    compiled,
    graphs,
    total,
    read_retained_bytes,
    read_execution_bytes,
    max_reservations,
    max_holdings,
    max_delegations,
    quantity_limits=quantities,
  )
}

///|
#export_name("clientProgramPrepareRequestModelRecoveryReadScopes")
pub fn client_program_prepare_request_model_recovery_read_scopes(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  graphs : Array[@publication_host.ClientInferPlanGraph],
  selected : Array[@infer_host.Limits],
  model_retained_bytes : Array[Int64],
  model_execution_bytes : Array[Int64],
  read_retained_bytes : Array[Int64],
  read_execution_bytes : Array[Int64],
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[
  Array[@publication_host.ClientModelReadScope],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  prepare_request_model_recovery_scopes_original(
    parent,
    input,
    request,
    definition,
    prepared,
    compiled,
    graphs,
    selected,
    model_retained_bytes,
    model_execution_bytes,
    read_retained_bytes,
    read_execution_bytes,
    max_reservations,
    max_holdings,
    max_delegations,
    None,
  )
}

///|
#export_name("clientProgramPrepareRequestModelRecoveryReadScopesWithQuantities")
pub fn client_program_prepare_request_model_recovery_read_scopes_with_quantities(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  graphs : Array[@publication_host.ClientInferPlanGraph],
  selected : Array[@infer_host.Limits],
  model_retained_bytes : Array[Int64],
  model_execution_bytes : Array[Int64],
  read_retained_bytes : Array[Int64],
  read_execution_bytes : Array[Int64],
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
  tokens : Int64,
  cost_units : Int64,
  duration_ms : Int64,
) -> Result[
  Array[@publication_host.ClientModelReadScope],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  prepare_request_model_recovery_scopes_original(
    parent,
    input,
    request,
    definition,
    prepared,
    compiled,
    graphs,
    selected,
    model_retained_bytes,
    model_execution_bytes,
    read_retained_bytes,
    read_execution_bytes,
    max_reservations,
    max_holdings,
    max_delegations,
    Some({ tokens, cost_units, duration_ms, }),
  )
}

///|
#export_name("clientProgramRequestModelRecoveryLedger")
pub fn client_program_request_model_recovery_ledger(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
) -> Result[@resources.Ledger, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.request_model_recovery_ledger(
    parent, input, request, definition,
  )
}

///|
/// Open the existing Local driver on this recovery Request's original Ledger.
/// Captures/providers retain their old current and cleanup responsibilities.
#export_name("clientProgramOpenRequestModelRecoveryHost")
pub fn client_program_open_request_model_recovery_host(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  prepared : @publication_host.PreparedClientProgram,
  sources : Array[@query.CapturedInputSource],
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
  providers : Array[@local.ManagedProvider],
) -> Result[
  @builtin.ConfiguredComputeHost[@strategy.RunIssue]?,
  @client_local_host.ClientRequestPreparationIssue,
] {
  let program = @publication_host.prepared_client_identity(prepared)
  guard sources.length() <= 2 &&
    sources.length() ==
    @publication_host.prepared_client_acquisition_count(prepared) &&
    program.program_definition_cid ==
    @publication_host.client_request_program_cid(request) &&
    program.parameter_values_cid ==
    @publication_host.client_request_parameters_cid(request) else {
    return Err(ForeignOriginal)
  }
  let ledger = match
    @client_local_host.request_model_recovery_ledger(
      parent, input, request, definition,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let provider_factory = capacity => {
    let families = installed_client_family_providers(capacity)
    for provider in providers {
      families.push(provider)
    }
    families
  }
  // A single restored Source is not a two-capture prefix. Keep its original
  // Request ledger and providers through the existing single-capture owner.
  if sources.length() == 1 {
    return Ok(
      @client_local_host.open_captured_local_retained_host_on_ledger(
        prepared,
        sources[0],
        ledger,
        contracts,
        values,
        fragment,
        ordered,
        provider_factory~,
      ),
    )
  }
  let captures = []
  for index in 0..<sources.length() {
    captures.push((index, sources[index]))
  }
  Ok(
    @client_local_host.open_multi_captured_local_retained_host(
      prepared,
      captures,
      ledger,
      contracts,
      values,
      fragment,
      ordered,
      provider_factory~,
    ),
  )
}

///|
#export_name("clientProgramRequestModelRecoveryUsageIsolated")
pub fn client_program_request_model_recovery_usage_isolated(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  captured : @strategy.CapturedDAG,
) -> Bool {
  @client_local_host.request_model_recovery_usage_isolated(
    parent, input, request, definition, captured,
  )
}

///|
#export_name("clientProgramRequestModelRecoverySourceCoordinates")
pub fn client_program_request_model_recovery_source_coordinates(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  Array[Array[Int]],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  let selected = match
    @client_local_host.request_model_recovery_direct_occurrences(
      parent, input, request, definition, prepared,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let coordinates = []
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

///|
#export_name("clientProgramReserveInstalledEffectCaptureDecoded")
pub fn client_program_reserve_installed_effect_capture_decoded(
  original : @client_local_host.ClientInstalledEffectCaptureRecovery,
  wire : String,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.reserve_installed_effect_capture_decoded(original, wire)
}

///|
#export_name("clientProgramCompleteInstalledEffectCaptureRecovery")
pub fn client_program_complete_installed_effect_capture_recovery(
  original : @client_local_host.ClientInstalledEffectCaptureRecovery,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.complete_installed_effect_capture_recovery(original)
}

///|
#export_name("clientProgramPrepareRequestEffectModelsReadScopes")
pub fn client_program_prepare_request_effect_models_read_scopes(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
) -> Result[
  Array[@publication_host.ClientModelReadScope],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_request_effect_models_read_scopes(
    parent, input, plan,
  )
}

///|
#export_name("clientProgramPrepareRequestEffectModelsReadScopesWithQuantities")
pub fn client_program_prepare_request_effect_models_read_scopes_with_quantities(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  tokens : Int64,
  cost_units : Int64,
  duration_ms : Int64,
) -> Result[
  Array[@publication_host.ClientModelReadScope],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_request_effect_models_read_scopes(
    parent,
    input,
    plan,
    quantity_limits=Some({ tokens, cost_units, duration_ms, }),
  )
}

///|
#export_name("clientProgramAdoptRequestEffectModelsPreparation")
pub fn client_program_adopt_request_effect_models_preparation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  request : @publication_host.ClientRequestIdentity,
  scopes : Array[@publication_host.ClientModelReadScope],
) -> Result[
  @client_local_host.ClientInstalledManagedRun,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  guard scopes.get(0) is Some(scope) else {
    return Err(@client_local_host.ForeignOriginal)
  }
  @client_local_host.begin_request_effect_model_managed_run(
    parent,
    request,
    scope,
    scopes=Some(scopes),
  )
}

///|
#export_name("clientProgramInstalledEffectModelsDemandPrepare")
pub fn client_program_installed_effect_models_demand_prepare(
  originals : Array[@client_local_host.ClientInstalledEffectModelDemand],
) -> Result[
  @client_local_host.ClientInstalledEffectModelDemand,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_effect_models_demand(originals)
}
