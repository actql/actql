///|
// The selected existing managed Run retains the same B reservation. These
// bridges project no Ledger and supply no grant, new Root or cleanup ACK.

///|
#export_name("clientProgramInstalledEffectCapturedInputInventoryRetain")
pub fn client_program_installed_effect_captured_input_inventory_retain(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  inputs : @strategy.CapturedEffectInputs,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.retain_installed_effect_captured_input_inventory(
    owner, prepared, request, plan, inputs,
  )
}

///|
#export_name("clientProgramInstalledEffectRecoveredInputInventoryRetain")
pub fn client_program_installed_effect_recovered_input_inventory_retain(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  allowed : @publication_host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  preview : @publication.EffectPreviewIdentity,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.retain_installed_effect_recovered_input_inventory(
    owner, prepared, request, plan, allowed, definition, invocation, preview,
  )
}

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
#export_name("clientProgramInstalledJsonEffectResponseConstructionCapacity")
pub fn client_program_installed_json_effect_response_construction_capacity(
  provider : @execution.ExecutionCapacity,
  max_response_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @execution.ExecutionCapacity? {
  @client_local_host.installed_json_effect_response_construction_capacity(
    provider, max_response_bytes, max_nodes, max_depth,
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
#export_name("clientProgramInstalledEffectResponseBufferConstructionCapacity")
pub fn client_program_installed_effect_response_buffer_construction_capacity(
  max_response_bytes : Int,
) -> @execution.ExecutionCapacity? {
  @client_local_host.installed_effect_response_buffer_construction_capacity(
    max_response_bytes,
  )
}

///|
#export_name("clientProgramInstalledEffectOperationResponseBackingFits")
pub fn client_program_installed_effect_operation_response_backing_fits(
  original : @client_local_host.ClientInstalledEffectOperationExtent,
  max_response_bytes : Int,
  max_header_bytes : Int,
  response_read_quantum : Int,
) -> Bool {
  @client_local_host.installed_effect_operation_response_backing_fits(
    original,
    max_response_bytes,
    max_header_bytes,
    response_read_quantum~,
  )
}

///|
#export_name("clientProgramInstalledEffectHttpResponseConstructionCapacity")
pub fn client_program_installed_effect_http_response_construction_capacity(
  max_response_bytes : Int,
  max_header_bytes : Int,
) -> @execution.ExecutionCapacity? {
  @client_local_host.installed_effect_http_response_construction_capacity(
    max_response_bytes, max_header_bytes,
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

///|
#export_name("clientProgramInstalledEffectOperationControlsBegin")
pub fn client_program_installed_effect_operation_controls_begin(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
) -> Result[
  @client_local_host.ClientInstalledEffectManagedPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_installed_effect_operation_controls(
    owner, prepared, request, plan,
  )
}

///|
// Forward the original provider-native Option/Array/tuple profile into the
// existing Core JSON constructor owner. JavaScript supplies no ABI layout or
// replacement quantities; this result is still constructor DATA only.
#export_name("clientProgramInstalledStandardCreateConstructorCapacities")
pub fn client_program_installed_standard_create_constructor_capacities(
  original : Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ]?,
) -> Result[
  Array[@execution.ExecutionCapacity],
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_standard_create_constructor_capacities(original)
}

///|
#export_name("clientProgramInstalledEffectOperationConstructionComplete")
pub fn client_program_installed_effect_operation_construction_complete(
  original : @client_local_host.ClientInstalledEffectOperationBorrow,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.complete_installed_effect_operation_construction(original)
}

///|
#export_name("clientProgramInstalledEffectOperationConstructionRetain")
pub fn client_program_installed_effect_operation_construction_retain(
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
  @client_local_host.retain_installed_effect_operation_construction(
    owner, prepared, request, plan, member_index, per_row, operation_index, row_index,
    operation,
  )
}

///|
#export_name("clientProgramInstalledEffectOperationConstructionBegin")
pub fn client_program_installed_effect_operation_construction_begin(
  original : @client_local_host.ClientInstalledEffectOperationBorrow,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.begin_installed_effect_operation_construction(original)
}

///|
#export_name("clientProgramInstalledEffectOperationControlsRetain")
pub fn client_program_installed_effect_operation_controls_retain(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
) -> Result[
  @client_local_host.ClientInstalledEffectManagedPlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.retain_installed_effect_operation_controls_before_construction(
    owner, prepared, request, plan,
  )
}

///|
#export_name("clientProgramInstalledEffectOperationControlConstructionBegin")
pub fn client_program_installed_effect_operation_control_construction_begin(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.begin_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  )
}

///|
#export_name("clientProgramInstalledEffectOperationControlInputBegin")
pub fn client_program_installed_effect_operation_control_input_begin(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  wire : String,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.begin_installed_effect_operation_control_input(
    owner, prepared, request, plan, wire,
  )
}

///|
#export_name("clientProgramInstalledEffectOperationControlConstructionComplete")
pub fn client_program_installed_effect_operation_control_construction_complete(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  )
}

///|
#export_name("clientProgramInstalledEffectOperationInputBegin")
pub fn client_program_installed_effect_operation_input_begin(
  original : @client_local_host.ClientInstalledEffectOperationBorrow,
  input : @client_local_host.ClientInstalledEffectOperationExtent,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.begin_installed_effect_operation_input(original, input)
}

///|
#export_name("clientProgramInstalledEffectOperationLedgerCodecBegin")
pub fn client_program_installed_effect_operation_ledger_codec_begin(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  wire : String?,
  nodes : Int,
  depth : Int,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.begin_installed_effect_operation_ledger_codec(
    owner, prepared, request, plan, wire, nodes, depth,
  )
}

///|
#export_name("clientProgramInstalledEffectOperationLedgerCodecComplete")
pub fn client_program_installed_effect_operation_ledger_codec_complete(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.complete_installed_effect_operation_ledger_codec(
    owner, prepared, request, plan,
  )
}

///|
/// Same owned constructor's detached output after actual physical close.
#export_name("clientProgramInstalledEffectOperationConstructionCompleteOutput")
pub fn client_program_installed_effect_operation_construction_complete_output(
  value : @client_local_host.ClientInstalledEffectOperationBorrow,
  wire : String,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.complete_installed_effect_operation_construction_output(
    value, wire,
  )
}
