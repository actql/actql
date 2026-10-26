///|
// Typed original DATA and the existing managed-parent supplier, never a
// physical dispatcher, permission issuer or provider-owned Resource root.

///|
#export_name("clientProgramInstalledEffectManagedHostOpen")
pub fn client_program_installed_effect_managed_host_open(
  owner : @client_local_host.ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
  providers : Array[@local.ManagedProvider],
) -> Result[
  ClientLocalEffectHost?,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.open_installed_effect_managed_host(owner, bound, sources, provider_factory=_ => {
    return providers
  }).map(value => {
    value.map(tuple => {
      let (host, run, sequences) = tuple
      { host, run, prepared: bound, sequences, }
    })
  })
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
    prepared, request, declarations, query_contract_body, evidence_contract_body,
    transport_bytes, transport_execution_bytes, installed_contracts, values_body,
    fragment_body, ordered_body, selected_operations,
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
#export_name("clientProgramNodeEffectManagedPlanPrepare")
pub fn client_program_node_effect_managed_plan_prepare(
  original : @resources.OriginalNodeManagedRunReference,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
) -> Result[
  @resources.NodeManagedRunAdmission[
    @client_local_host.ClientInstalledEffectManagedPlan,
  ],
  @resources.ImportedChildLedgerIssue,
] {
  @resources.prepare_node_managed_run_admission(original, plan)
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
#export_name("clientProgramInstalledEffectManagedPlanBegin")
pub fn client_program_installed_effect_managed_plan_begin(
  admission : @resources.NodeManagedRunAdmission[
    @client_local_host.ClientInstalledEffectManagedPlan,
  ],
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
) -> Result[
  @client_local_host.ClientInstalledManagedRun,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_prepared_installed_effect_managed_run(
    admission, prepared, request, plan,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedOperationPlan")
pub fn client_program_installed_effect_managed_operation_plan(
  value : @client_local_host.ClientInstalledManagedRun,
) -> Result[
  @client_local_host.ClientInstalledEffectManagedPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_effect_managed_operation_plan(value)
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
