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
#export_name("clientProgramInstalledEffectOperationUnknown")
pub fn client_program_installed_effect_operation_unknown(
  original : @client_local_host.ClientInstalledEffectOperationBorrow,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.mark_installed_effect_operation_unknown(original)
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
