///|
// The selected existing managed Run retains the same B reservation. These
// bridges project no Ledger and supply no grant, new Root or cleanup ACK.

///|
#export_name("clientProgramInstalledEffectOperationBorrow")
pub fn client_program_installed_effect_operation_borrow(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  member_index : Int,
  per_row : Bool,
  operation_index : Int,
  row_index : Int,
  operation : String,
) -> Result[
  @client_local_host.ClientInstalledEffectOperationBorrow,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.borrow_installed_effect_operation(
    owner, prepared, request, plan, member_index, per_row, operation_index, row_index,
    operation,
  )
}

///|
#export_name("clientProgramInstalledEffectOperationStart")
pub fn client_program_installed_effect_operation_start(
  original : @client_local_host.ClientInstalledEffectOperationBorrow,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.start_installed_effect_operation(original)
}

///|
#export_name("clientProgramInstalledEffectOperationCharge")
pub fn client_program_installed_effect_operation_charge(
  original : @client_local_host.ClientInstalledEffectOperationBorrow,
  bytes : Int64,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.charge_installed_effect_operation(original, bytes)
}

///|
#export_name("clientProgramInstalledEffectOperationTransferUncertain")
pub fn client_program_installed_effect_operation_transfer_uncertain(
  original : @client_local_host.ClientInstalledEffectOperationBorrow,
  bytes : Int64,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.mark_installed_effect_operation_transfer_uncertain(
    original, bytes,
  )
}

///|
#export_name("clientProgramInstalledEffectOperationRetire")
pub fn client_program_installed_effect_operation_retire(
  original : @client_local_host.ClientInstalledEffectOperationBorrow,
  original_cleanup_confirmed : Bool,
) -> Result[Bool, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.retire_installed_effect_operation(
    original, original_cleanup_confirmed,
  )
}

///|
#export_name("clientProgramInstalledJsonEffectRequestConstructionCapacity")
pub fn client_program_installed_json_effect_request_construction_capacity(
  provider : @execution.ExecutionCapacity,
  max_input_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @execution.ExecutionCapacity? {
  @client_local_host.installed_json_effect_request_construction_capacity(
    provider, max_input_bytes, max_nodes, max_depth,
  )
}

///|
// Preserve the original native capacity value instead of projecting/copying
// its byte fields through JavaScript. This remains immutable demand DATA.
#export_name("clientProgramInstalledEffectOperationExtentFromCapacity")
pub fn client_program_installed_effect_operation_extent_from_capacity(
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
// Original selected extent DATA, checked before binding allocation. These
// projections neither admit a transfer nor turn a quota into observed bytes.
#export_name("clientProgramInstalledEffectOperationExtentPhysical")
pub fn client_program_installed_effect_operation_extent_physical(
  original : @client_local_host.ClientInstalledEffectOperationExtent,
) -> Bool {
  @client_local_host.installed_effect_operation_extent_physical(original)
}

///|
#export_name("clientProgramInstalledEffectOperationExtentTransfer")
pub fn client_program_installed_effect_operation_extent_transfer(
  original : @client_local_host.ClientInstalledEffectOperationExtent,
) -> Int64 {
  @client_local_host.installed_effect_operation_extent_transfer(original)
}
