///|
// Typed original DATA and the existing managed-parent supplier, never a
// physical dispatcher, permission issuer or provider-owned Resource root.

///|
#export_name("clientProgramInstalledEffectManagedHostOpen")
pub fn client_program_installed_effect_managed_host_open(
  owner : @client_local_host.ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
) -> Result[
  ClientLocalEffectHost?,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.open_installed_effect_managed_host(owner, bound, sources).map(value => {
      value.map(tuple => {
        let (host, run, sequences) = tuple
        { host, run, prepared: bound, sequences, }
      })
    },
  )
}

///|
#export_name("clientProgramInstalledEffectOperationExtentPrepare")
pub fn client_program_installed_effect_operation_extent_prepare(
  operation : String,
  retained_bytes : Int64,
  execution_bytes : Int64,
  transfer_bytes : Int64,
  physical_attempt : Bool,
) -> Result[
  @client_local_host.ClientInstalledEffectOperationExtent,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  guard @execution.execution_capacity(retained_bytes, execution_bytes)
    is Some(capacity) else {
    return Err(Unsupported)
  }
  @client_local_host.prepare_installed_effect_operation_extent(
    operation, capacity, transfer_bytes, physical_attempt,
  )
}

///|
// The existing typed extent constructor consumes an original opaque quantity;
// callers never reconstruct its representation or peel its retained fields.
#export_name("clientProgramInstalledEffectOperationExtentFromCapacityPrepare")
pub fn client_program_installed_effect_operation_extent_from_capacity_prepare(
  operation : String,
  capacity : @execution.ExecutionCapacity,
  transfer_bytes : Int64,
  physical_attempt : Bool,
) -> Result[
  @client_local_host.ClientInstalledEffectOperationExtent,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_effect_operation_extent(
    operation, capacity, transfer_bytes, physical_attempt,
  )
}

///|
#export_name("clientProgramInstalledStandardCreateRecipeCapacities")
pub fn client_program_installed_standard_create_recipe_capacities(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]?,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  request_bytes : Int,
  response_bytes : Int,
  check_request_bytes : Int,
  check_response_bytes : Int,
  before_send : Bool,
  secret_bytes : Int,
  secret_prefix_units : Int,
  header_bytes : Int,
  stored_bytes : Int,
  stored_nodes : Int,
  stored_depth : Int,
  metadata_units : Int64,
  response_read_quantum : Int,
) -> Result[
  Array[@execution.ExecutionCapacity],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_standard_create_recipe_capacities(
    original,
    input_bytes,
    input_nodes,
    input_depth,
    request_bytes,
    response_bytes,
    check_request_bytes,
    check_response_bytes,
    before_send,
    secret_bytes,
    secret_prefix_units,
    header_bytes,
    stored_bytes,
    stored_nodes,
    stored_depth,
    metadata_units,
    response_read_quantum~,
  )
}

///|
#export_name("clientProgramInstalledStandardCreateRequestRecipeCapacities")
pub fn client_program_installed_standard_create_request_recipe_capacities(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]?,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  row_input_bytes : Int,
  row_input_nodes : Int,
  row_input_depth : Int,
  request_bytes : Int,
  response_bytes : Int,
  check_request_bytes : Int,
  check_response_bytes : Int,
  before_send : Bool,
  secret_bytes : Int,
  secret_prefix_units : Int,
  header_bytes : Int,
  stored_bytes : Int,
  stored_nodes : Int,
  stored_depth : Int,
  metadata_units : Int64,
  response_read_quantum : Int,
) -> Result[
  Array[@execution.ExecutionCapacity],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_standard_create_request_recipe_capacities(
    original,
    input_bytes,
    input_nodes,
    input_depth,
    row_input_bytes,
    row_input_nodes,
    row_input_depth,
    request_bytes,
    response_bytes,
    check_request_bytes,
    check_response_bytes,
    before_send,
    secret_bytes,
    secret_prefix_units,
    header_bytes,
    stored_bytes,
    stored_nodes,
    stored_depth,
    metadata_units,
    response_read_quantum~,
    defer_ledger_codec=true,
  )
}

///|
#export_name("clientProgramInstalledStandardDriverRecipeCapacities")
pub fn client_program_installed_standard_driver_recipe_capacities(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]?,
  capture_original : Array[@execution.ExecutionCapacity]?,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  row_input_bytes : Int,
  row_input_nodes : Int,
  row_input_depth : Int,
  request_bytes : Int,
  response_bytes : Int,
  check_request_bytes : Int,
  check_response_bytes : Int,
  before_send : Bool,
  secret_bytes : Int,
  secret_prefix_units : Int,
  header_bytes : Int,
  stored_bytes : Int,
  stored_nodes : Int,
  stored_depth : Int,
  metadata_units : Int64,
  response_read_quantum : Int,
) -> Result[
  Array[@execution.ExecutionCapacity],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_standard_driver_recipe_capacities(
    original,
    capture_original,
    input_bytes,
    input_nodes,
    input_depth,
    row_input_bytes,
    row_input_nodes,
    row_input_depth,
    request_bytes,
    response_bytes,
    check_request_bytes,
    check_response_bytes,
    before_send,
    secret_bytes,
    secret_prefix_units,
    header_bytes,
    stored_bytes,
    stored_nodes,
    stored_depth,
    metadata_units,
    response_read_quantum~,
  )
}

///|
#export_name("clientProgramInstalledDescribedEffectRecipeCapacities")
pub fn client_program_installed_described_effect_recipe_capacities(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]?,
  capture_original : Array[@execution.ExecutionCapacity]?,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  row_input_bytes : Int,
  row_input_nodes : Int,
  row_input_depth : Int,
  request_bytes : Int,
  response_bytes : Int,
  target_reads : Bool,
  target_request_bytes : Int,
  target_response_bytes : Int,
  metadata_request_bytes : Int,
  metadata_response_bytes : Int,
  secret_bytes : Int,
  secret_prefix_units : Int,
  header_bytes : Int,
  stored_bytes : Int,
  stored_nodes : Int,
  stored_depth : Int,
  metadata_units : Int64,
  response_read_quantum : Int,
) -> Result[
  Array[@execution.ExecutionCapacity],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_described_effect_recipe_capacities(
    original,
    capture_original,
    input_bytes,
    input_nodes,
    input_depth,
    row_input_bytes,
    row_input_nodes,
    row_input_depth,
    request_bytes,
    response_bytes,
    target_reads,
    target_request_bytes,
    target_response_bytes,
    metadata_request_bytes,
    metadata_response_bytes,
    secret_bytes,
    secret_prefix_units,
    header_bytes,
    stored_bytes,
    stored_nodes,
    stored_depth,
    metadata_units,
    response_read_quantum~,
  )
}

///|
// Pure same-Plan capture quantity. JavaScript forwards the native capacity
// unchanged; Core supplies its checked row multiplicity, never an ABI tuple
// or an independent caller estimate.
#export_name("clientProgramInstalledEffectCaptureExtentPrepare")
pub fn client_program_installed_effect_capture_extent_prepare(
  operation : String,
  fixed_capacity : @execution.ExecutionCapacity,
  capacity_per_checked_row : @execution.ExecutionCapacity,
) -> Result[
  @client_local_host.ClientInstalledEffectOperationExtent,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_effect_capture_extent(
    operation, fixed_capacity, capacity_per_checked_row,
  )
}

///|
#export_name("clientProgramInstalledEffectCaptureRecipeExtentPrepare")
pub fn client_program_installed_effect_capture_recipe_extent_prepare(
  operation : String,
  recipe : Array[@execution.ExecutionCapacity],
) -> Result[
  @client_local_host.ClientInstalledEffectOperationExtent,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_effect_capture_recipe_extent(
    operation, recipe,
  )
}

///|
#export_name("clientProgramInstalledEffectHostInputCaptureRecipeExtentPrepare")
pub fn client_program_installed_effect_host_input_capture_recipe_extent_prepare(
  operation : String,
  recipe : Array[@execution.ExecutionCapacity],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @client_local_host.ClientInstalledEffectOperationExtent,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_effect_host_input_capture_recipe_extent(
    operation, recipe, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedPlanHasHostInput")
pub fn client_program_installed_effect_managed_plan_has_host_input(
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
) -> Bool {
  @client_local_host.installed_effect_managed_plan_has_host_input(plan)
}

///|
#export_name("clientProgramInstalledEffectOperationDemandPrepare")
pub fn client_program_installed_effect_operation_demand_prepare(
  prepared : @publication_host.PreparedClientEffectComputation,
  stage_index : Int,
  effect_id : String,
  member_extents : Array[
    @client_local_host.ClientInstalledEffectOperationExtent,
  ],
  row_extents : Array[@client_local_host.ClientInstalledEffectOperationExtent],
) -> Result[
  @client_local_host.ClientInstalledEffectOperationDemand,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_effect_operation_demand(
    prepared, stage_index, effect_id, member_extents, row_extents,
  )
}

///|
#export_name("clientProgramInstalledEffectOperationDemandWithControlsPrepare")
pub fn client_program_installed_effect_operation_demand_with_controls_prepare(
  prepared : @publication_host.PreparedClientEffectComputation,
  stage_index : Int,
  effect_id : String,
  member_extents : Array[
    @client_local_host.ClientInstalledEffectOperationExtent,
  ],
  row_extents : Array[@client_local_host.ClientInstalledEffectOperationExtent],
  controls_per_row : @execution.ExecutionCapacity,
) -> Result[
  @client_local_host.ClientInstalledEffectOperationDemand,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_effect_operation_demand_with_controls(
    prepared, stage_index, effect_id, member_extents, row_extents, controls_per_row,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedPlanPrepare")
pub fn client_program_installed_effect_managed_plan_prepare(
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
) -> Result[
  @client_local_host.ClientInstalledEffectManagedPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
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
    provider_factory=installed_client_family_providers,
    runtime_admission=true,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedPlanPrepareAtQueryTime")
pub fn client_program_installed_effect_managed_plan_prepare_at_query_time(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  query_time : @publication_host.ClientQueryTimePreparation,
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
) -> Result[
  @client_local_host.ClientInstalledEffectManagedPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
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
    query_time=Some(query_time),
    provider_factory=installed_client_family_providers,
    runtime_admission=true,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedPlanRequirements")
pub fn client_program_installed_effect_managed_plan_requirements(
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
) -> Array[Int64] {
  @client_local_host.prepared_installed_effect_managed_requirements(plan)
}

///|
#export_name("clientProgramInstalledEffectManagedPlanCaptureChildren")
pub fn client_program_installed_effect_managed_plan_capture_children(
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
) -> Int {
  @client_local_host.prepared_installed_effect_managed_capture_children(plan)
}

///|
#export_name("clientProgramInstalledEffectManagedPlanShape")
pub fn client_program_installed_effect_managed_plan_shape(
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
) -> (Int, Int, Int) {
  @client_local_host.prepared_installed_effect_managed_shape(plan)
}

///|
#export_name("clientProgramInstalledEffectManagedPlanSource")
pub fn client_program_installed_effect_managed_plan_source(
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  occurrence : Int,
) -> Result[
  (
    @client_row_source_host.RowDeclaration,
    @planning.QueryRequirement,
    @client_row_source_host.RowAcquisition,
    @client_local_host.ClientInstalledCaptureCapacity,
  ),
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepared_installed_effect_managed_source(plan, occurrence)
}

///|
#export_name("clientProgramInstalledEffectManagedPlanOperation")
pub fn client_program_installed_effect_managed_plan_operation(
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  member_index : Int,
  per_row : Bool,
  operation_index : Int,
  operation : String,
) -> Result[
  @client_local_host.ClientInstalledEffectOperationExtent,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepared_installed_effect_managed_operation(
    plan, member_index, per_row, operation_index, operation,
  )
}

///|
#export_name("clientProgramNodeEffectManagedPlanCleanup")
pub fn client_program_node_effect_managed_plan_cleanup(
  admission : @resources.NodeManagedRunAdmission[
    @client_local_host.ClientInstalledEffectManagedPlan,
  ],
) -> Result[Unit, @resources.ImportedChildLedgerIssue] {
  @resources.cleanup_node_managed_run_admission(admission)
}

///|
#export_name("clientProgramInstalledEffectManagedOperationPlan")
pub fn client_program_installed_effect_managed_operation_plan(
  value : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @client_local_host.ClientInstalledEffectManagedPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_effect_managed_operation_plan(
    value, prepared, request,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedProviderPlanPrepare")
pub fn client_program_installed_effect_managed_provider_plan_prepare(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  declarations : Array[@client_row_source_host.RowDeclaration],
  providers : Array[@execution.ExecutionCapacity],
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
) -> Result[
  @client_local_host.ClientInstalledEffectManagedPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
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
    source_providers=Some(providers),
    provider_factory=installed_client_family_providers,
    runtime_admission=true,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedProviderPlanPrepareAtQueryTime")
pub fn client_program_installed_effect_managed_provider_plan_prepare_at_query_time(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  query_time : @publication_host.ClientQueryTimePreparation,
  declarations : Array[@client_row_source_host.RowDeclaration],
  providers : Array[@execution.ExecutionCapacity],
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
) -> Result[
  @client_local_host.ClientInstalledEffectManagedPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
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
    query_time=Some(query_time),
    source_providers=Some(providers),
    provider_factory=installed_client_family_providers,
    runtime_admission=true,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedSourceRead")
pub fn client_program_installed_effect_managed_source_read(
  owner : @client_local_host.ClientInstalledManagedRun,
  declaration : @client_row_source_host.RowDeclaration,
  occurrence : Int,
) -> Result[
  (
    @client_local_host.ClientInstalledSourceRead,
    @planning.QueryRequirement,
    @client_row_source_host.RowAcquisition,
    @client_local_host.ClientInstalledCaptureCapacity,
  ),
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_installed_effect_managed_source_read(
    owner, declaration, occurrence,
  )
}

///|
#export_name("clientProgramInstalledLocalFileStoreRecipeCapacities")
pub fn client_program_installed_local_file_store_recipe_capacities(
  body_bytes : Int,
  body_nodes : Int,
  body_depth : Int,
  preview_bytes : Int,
  preview_nodes : Int,
  preview_depth : Int,
  request_bytes : Int,
  recovery_bytes : Int,
  response_bytes : Int,
  stored_bytes : Int,
  stored_nodes : Int,
  stored_depth : Int,
  native_original_bytes : Int64,
  path_bytes : Int,
  name_bytes : Int,
  max_components : Int,
  native_depth : Int,
  content_read_window_bytes : Int,
  control_wire_bytes : Int?,
) -> Result[
  Array[@execution.ExecutionCapacity],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_local_file_store_recipe_capacities(
    body_bytes,
    body_nodes,
    body_depth,
    preview_bytes,
    preview_nodes,
    preview_depth,
    request_bytes,
    recovery_bytes,
    response_bytes,
    stored_bytes,
    stored_nodes,
    stored_depth,
    native_original_bytes,
    path_bytes,
    name_bytes,
    max_components,
    native_depth,
    content_read_window_bytes,
    control_wire_bytes~,
  )
}

///|
#export_name("clientProgramInstalledEffectContentPreparationPrepare")
pub fn client_program_installed_effect_content_preparation_prepare(
  prepared : @publication_host.PreparedClientEffectComputation,
  compiled : @publication_host.ClientCompiledRun,
  compilation : @publication_host.ClientEffectCompilation,
  definition : @publication.PublicationContract,
  component : @publication_host.ClientSerializationPlanGraph,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
  workspace : @client_local_host.ClientSerializationWorkspaceLimits,
  cancel : () -> Bool,
  stopped : () -> Bool,
  cleanup : () -> Bool,
  retain : (@client_local_host.ClientLocalContentStep) -> Bool,
) -> Result[
  @client_local_host.ClientInstalledEffectContentPreparation,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  let (execution, measurement) = client_program_local_execution_limits()
  @client_local_host.prepare_installed_effect_content(
    prepared,
    compiled,
    compilation,
    definition,
    component,
    contracts,
    values,
    fragment,
    ordered,
    execution,
    measurement,
    workspace,
    { cancel, stopped, cleanup: () => Ok(cleanup()), },
    retain,
  )
}

///|
#export_name("clientProgramInstalledEffectContentPreparationProvider")
pub fn client_program_installed_effect_content_preparation_provider(
  original : @client_local_host.ClientInstalledEffectContentPreparation,
) -> @local.ManagedProvider {
  @client_local_host.installed_effect_content_provider(original)
}

///|
#export_name("clientProgramInstalledEffectContentManagedPlanPrepare")
pub fn client_program_installed_effect_content_managed_plan_prepare(
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
  operations : Array[@client_local_host.ClientInstalledEffectOperationDemand],
  content : @client_local_host.ClientInstalledEffectContentPreparation,
  query_time : @publication_host.ClientQueryTimePreparation?,
) -> Result[
  @client_local_host.ClientInstalledEffectManagedPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
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
    operations,
    content=Some(content),
    source_providers=if source_providers.is_empty() {
      None
    } else {
      Some(source_providers)
    },
    query_time~,
    provider_factory=installed_client_family_providers,
    runtime_admission=true,
  )
}

///|
#export_name("clientProgramInstalledLocalFileStoreControlWireBound")
pub fn client_program_installed_local_file_store_control_wire_bound() -> Int {
  @client_local_host.installed_local_file_store_control_wire_bound()
}

///|
#export_name("clientProgramInstalledEffectOperationStagedExtentPrepare")
pub fn client_program_installed_effect_operation_staged_extent_prepare(
  initial : @client_local_host.ClientInstalledEffectOperationExtent,
  maximum : @client_local_host.ClientInstalledEffectOperationExtent,
) -> Result[
  @client_local_host.ClientInstalledEffectOperationExtent,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_effect_staged_extent(initial, maximum)
}

///|
#export_name("clientProgramInstalledDescribedEffectInputRecipeCapacities")
pub fn client_program_installed_described_effect_input_recipe_capacities(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]?,
  capture_original : Array[@execution.ExecutionCapacity]?,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  row_input_bytes : Int,
  row_input_nodes : Int,
  row_input_depth : Int,
  request_bytes : Int,
  response_bytes : Int,
  target_reads : Bool,
  target_request_bytes : Int,
  target_response_bytes : Int,
  metadata_request_bytes : Int,
  metadata_response_bytes : Int,
  secret_bytes : Int,
  secret_prefix_units : Int,
  header_bytes : Int,
  stored_bytes : Int,
  stored_nodes : Int,
  stored_depth : Int,
  metadata_units : Int64,
  response_read_quantum : Int,
  control_wire_bytes : Int,
  host_input_bytes : Int,
) -> Result[
  Array[@execution.ExecutionCapacity],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_described_effect_recipe_capacities(
    original,
    capture_original,
    input_bytes,
    input_nodes,
    input_depth,
    row_input_bytes,
    row_input_nodes,
    row_input_depth,
    request_bytes,
    response_bytes,
    target_reads,
    target_request_bytes,
    target_response_bytes,
    metadata_request_bytes,
    metadata_response_bytes,
    secret_bytes,
    secret_prefix_units,
    header_bytes,
    stored_bytes,
    stored_nodes,
    stored_depth,
    metadata_units,
    response_read_quantum~,
    metadata_on_child=true,
    // Zero selects the unchanged wider composed-implementation fallback.
    defer_ledger_codec=control_wire_bytes > 0,
    control_wire_bytes=if control_wire_bytes == 0 {
      None
    } else {
      Some(control_wire_bytes)
    },
    host_input_bytes=if host_input_bytes < 0 {
      None
    } else {
      Some(host_input_bytes)
    },
  )
}

///|
#export_name("clientProgramInstalledEffectControlWireBound")
pub fn client_program_installed_effect_control_wire_bound(
  outcome_bytes : Int,
  maximum_bytes : Int,
) -> Result[Int, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.installed_effect_control_wire_bound(
    outcome_bytes, maximum_bytes,
  )
}

///|
#export_name("clientProgramInstalledPhysicalWriteRecipeCapacities")
pub fn client_program_installed_physical_write_recipe_capacities(
  body_bytes : Int,
  body_nodes : Int,
  body_depth : Int,
  preview_bytes : Int,
  preview_nodes : Int,
  preview_depth : Int,
  request_bytes : Int,
  recovery_bytes : Int,
  response_bytes : Int,
  stored_bytes : Int,
  stored_nodes : Int,
  stored_depth : Int,
  physical : @execution.ExecutionCapacity,
  control_wire_bytes : Int,
) -> Result[
  Array[@execution.ExecutionCapacity],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_physical_write_recipe_capacities(
    body_bytes,
    body_nodes,
    body_depth,
    preview_bytes,
    preview_nodes,
    preview_depth,
    request_bytes,
    recovery_bytes,
    response_bytes,
    stored_bytes,
    stored_nodes,
    stored_depth,
    physical,
    control_wire_bytes=if control_wire_bytes == 0 {
      None
    } else {
      Some(control_wire_bytes)
    },
  )
}

///|
#export_name("clientProgramInstalledEffectRowSourceInputPrepare")
pub fn client_program_installed_effect_row_source_input_prepare(
  declaration : @client_row_source_host.RowDeclaration,
  provider : @execution.ExecutionCapacity?,
) -> Result[
  @client_local_host.ClientInstalledEffectSourceInput,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_effect_row_source_input(
    declaration, provider,
  )
}

///|
#export_name("clientProgramInstalledEffectDuckDBSourceInputPrepare")
pub fn client_program_installed_effect_duckdb_source_input_prepare(
  source_ref : String,
  database_schema : String,
  table : String,
  query_contract : String,
  evidence_contract : String,
  two_receipt_contract : String,
) -> Result[
  @client_local_host.ClientInstalledEffectSourceInput,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_effect_duckdb_source_input(
    source_ref, database_schema, table, query_contract, evidence_contract, two_receipt_contract,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedSourcePlanPrepare")
pub fn client_program_installed_effect_managed_source_plan_prepare(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  inputs : Array[@client_local_host.ClientInstalledEffectSourceInput],
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
  query_time : @publication_host.ClientQueryTimePreparation?,
  model : @client_local_host.ClientInstalledEffectModelDemand?,
  components : Array[@local.ManagedProvider],
  content : @client_local_host.ClientInstalledEffectContentPreparation?,
) -> Result[
  @client_local_host.ClientInstalledEffectManagedPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  if model is Some(_) && components.is_empty() {
    return Err(Unsupported)
  }
  let components = components.copy()
  @client_local_host.prepare_installed_effect_managed_source_plan(
    prepared,
    request,
    inputs,
    query_contract_body,
    evidence_contract_body,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    selected_operations,
    query_time~,
    model~,
    content~,
    provider_factory=capacity => {
      let providers = installed_client_family_providers(capacity)
      for component in components {
        providers.push(component)
      }
      providers
    },
    runtime_admission=true,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedDuckDBCapture")
pub fn client_program_installed_effect_managed_duckdb_capture(
  run : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  occurrence : Int,
) -> Result[
  (
    @planning.QueryRequirement,
    @client_local_host.ClientInstalledCaptureCapacity,
  ),
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_effect_managed_duckdb_capture(
    run, prepared, request, occurrence,
  )
}

///|
#export_name("clientProgramInstalledFileEffectConstructionCapacity")
pub fn client_program_installed_file_effect_construction_capacity(
  provider : @execution.ExecutionCapacity,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[
  @execution.ExecutionCapacity,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_file_effect_constructor_capacity(
    provider, bytes, nodes, depth,
  )
}

///|
#export_name("clientProgramInstalledPhysicalWriteRecipeCapacitiesWithRequest")
pub fn client_program_installed_physical_write_recipe_capacities_with_request(
  body_bytes : Int,
  body_nodes : Int,
  body_depth : Int,
  preview_bytes : Int,
  preview_nodes : Int,
  preview_depth : Int,
  request_bytes : Int,
  recovery_bytes : Int,
  response_bytes : Int,
  stored_bytes : Int,
  stored_nodes : Int,
  stored_depth : Int,
  physical : @execution.ExecutionCapacity,
  control_wire_bytes : Int,
  request_construction : @execution.ExecutionCapacity,
) -> Result[
  Array[@execution.ExecutionCapacity],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_physical_write_recipe_capacities(
    body_bytes,
    body_nodes,
    body_depth,
    preview_bytes,
    preview_nodes,
    preview_depth,
    request_bytes,
    recovery_bytes,
    response_bytes,
    stored_bytes,
    stored_nodes,
    stored_depth,
    physical,
    control_wire_bytes=if control_wire_bytes == 0 {
      None
    } else {
      Some(control_wire_bytes)
    },
    request_construction=Some(request_construction),
  )
}
