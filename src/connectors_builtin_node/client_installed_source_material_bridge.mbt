///|
/// The fixed installation service retains this original pair before its next
/// fallible constructor. Taking it grants no variable Source bytes and never
/// reconstructs the opaque Host input or exposes its Ledger.
#export_name("clientProgramTakeHostInitializationSourceCapacity")
pub fn client_program_take_host_initialization_source_capacity(
  owner : @client_local_host.ClientHostInitializationPreparation[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[
  (
    ClientLocalPreparationInputOriginal,
    @resources.PreparationCapacity[ClientLocalPreparationInputOriginal, Unit],
  ),
  @client_local_host.ClientHostInitializationIssue,
] {
  @client_local_host.take_host_initialization_preparation_capacity(owner)
}

///|
/// Choose the actual Source aggregate/Environment body on the SAME original
/// working reservation. The service must keep the uncontinued pair on failure
/// and retain this successor before any later constructor. No body or capacity
/// is manufactured by the type projection.
#export_name("clientProgramContinueInstalledSourceMaterial")
pub fn client_program_continue_installed_source_material(
  capacity : @resources.PreparationCapacity[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
  input : ClientLocalPreparationInputOriginal,
) -> Result[
  @resources.PreparationCapacity[
    ClientLocalPreparationInputOriginal,
    (
      ClientLocalPreparationInputOriginal,
      @source_publication.PreparedPublishedQueryEnvironment,
    ),
  ],
  @resources.PreparationCapacityIssue,
] {
  @resources.continue_preparation_capacity(capacity, input)
}

///|
/// DATA projection from a live original borrow, including existing retiring
/// borrows used for cleanup. It cannot start work, authenticate a Host, admit a
/// Request or acknowledge a physical child's stop.
#export_name("clientProgramBorrowedInstalledSourceEnvironment")
pub fn client_program_borrowed_installed_source_environment(
  holder : @resources.PreparationBodyBorrow[
    (
      ClientLocalPreparationInputOriginal,
      @source_publication.PreparedPublishedQueryEnvironment,
    ),
  ],
  source_original : ClientLocalPreparationInputOriginal,
) -> Result[
  @source_publication.PreparedPublishedQueryEnvironment,
  @resources.PreparationCapacityIssue,
] {
  @client_local_host.borrowed_installed_source_environment(
    holder, source_original,
  )
}

///|
#export_name("clientProgramInstalledSourceConstructionCapacity")
pub fn client_program_installed_source_construction_capacity(
  retained_nodes : Int64,
  retained_text_bytes : Int64,
  retained_wire_bytes : Int64,
  workspace_nodes : Int64,
  workspace_text_bytes : Int64,
  workspace_wire_bytes : Int64,
) -> Result[@execution.ExecutionCapacity, @resources.PreparationCapacityIssue] {
  match
    @client_local_host.installed_source_construction_capacity(
      retained_nodes, retained_text_bytes, retained_wire_bytes, workspace_nodes,
      workspace_text_bytes, workspace_wire_bytes,
    ) {
    Some(value) => Ok(value)
    None => Err(@resources.InvalidExtent)
  }
}

///|
#export_name("clientProgramInstalledSourceJsonConstructionCapacity")
pub fn client_program_installed_source_json_construction_capacity(
  wire_nodes : Int64,
  wire_units : Int64,
  buffer_bytes : Int64,
  returned_nodes : Int64,
  returned_text_bytes : Int64,
) -> Result[@execution.ExecutionCapacity?, @resources.PreparationCapacityIssue] {
  match
    @client_local_host.installed_source_json_construction_capacity(
      wire_nodes, wire_units, buffer_bytes, returned_nodes, returned_text_bytes,
    ) {
    Some(value) => Ok(Some(value))
    None => Err(@resources.InvalidExtent)
  }
}

///|
#export_name("clientProgramInstalledProfileConstructionCapacities")
pub fn client_program_installed_profile_construction_capacities(
  nodes : Int64,
  units : Int64,
) -> Result[
  Array[@execution.ExecutionCapacity?],
  @resources.PreparationCapacityIssue,
] {
  match
    @client_local_host.installed_profile_construction_capacities(nodes, units) {
    Some(values) => Ok(values.map(value => Some(value)))
    None => Err(@resources.InvalidExtent)
  }
}

///|
#export_name("clientProgramInstalledSourceInspectionConstructionCapacity")
pub fn client_program_installed_source_inspection_construction_capacity(
  original : @execution.ExecutionCapacity?,
) -> Result[@execution.ExecutionCapacity?, @resources.PreparationCapacityIssue] {
  guard original is Some(value) else { return Err(@resources.InvalidExtent) }
  Ok(
    Some(
      @client_local_host.installed_source_inspection_construction_capacity(
        value,
      ),
    ),
  )
}

///|
#export_name("clientProgramInstalledTableConstructionInventory")
pub fn client_program_installed_table_construction_inventory(
  nodes : Int64,
  wire : Int64,
  strings : Int64,
  serializer_text : Int64,
) -> Result[Array[Int64], @resources.PreparationCapacityIssue] {
  match
    @client_local_host.installed_table_construction_inventory(
      nodes, wire, strings, serializer_text,
    ) {
    Some(value) => Ok(value)
    None => Err(@resources.InvalidExtent)
  }
}

///|
#export_name("clientProgramComposeInstalledSourceConstructionCapacity")
pub fn client_program_compose_installed_source_construction_capacity(
  original : @execution.ExecutionCapacity,
  providers : Array[@execution.ExecutionCapacity?],
) -> Result[@execution.ExecutionCapacity, @resources.PreparationCapacityIssue] {
  // Native constructor quotes return this original Option. Consume it in
  // typed Core; the Host forwards it unchanged and never guesses/reboxes its
  // compiler representation or uses an absent quote as an allowance.
  let selected = []
  for provider in providers {
    guard provider is Some(provider) else {
      return Err(@resources.InvalidExtent)
    }
    selected.push(provider)
  }
  match
    @client_local_host.compose_installed_source_construction_capacity(
      original, selected,
    ) {
    Some(value) => Ok(value)
    None => Err(@resources.InvalidExtent)
  }
}

///|
/// Keep the original optional quantity in typed Core. This is DATA only;
/// selecting its retained part neither proves constructor completion nor
/// issues or retires a Resource. No Host-side Option layout is constructed.
#export_name("clientProgramInstalledSourceRetainedConstructionCapacity")
pub fn client_program_installed_source_retained_construction_capacity(
  original : @execution.ExecutionCapacity?,
) -> Result[@execution.ExecutionCapacity?, @resources.PreparationCapacityIssue] {
  guard original is Some(capacity) else { return Err(@resources.InvalidExtent) }
  if @execution.execution_capacity_retained_bytes(capacity) ==
    @execution.execution_capacity_execution_bytes(capacity) {
    Ok(original)
  } else {
    Ok(
      Some(
        @client_local_host.retained_installed_source_construction_capacity(
          capacity,
        ),
      ),
    )
  }
}

///|
#export_name("clientProgramReserveInstalledSourceConstruction")
pub fn client_program_reserve_installed_source_construction(
  owner : @resources.PreparationCapacity[
    ClientLocalPreparationInputOriginal,
    (
      ClientLocalPreparationInputOriginal,
      @source_publication.PreparedPublishedQueryEnvironment,
    ),
  ],
  input : ClientLocalPreparationInputOriginal,
  quote : @execution.ExecutionCapacity,
) -> Result[Unit, @resources.PreparationCapacityIssue] {
  @client_local_host.reserve_installed_source_construction(owner, input, quote)
}

///|
#export_name("clientProgramReconcileInstalledSourceConstruction")
pub fn client_program_reconcile_installed_source_construction(
  owner : @resources.PreparationCapacity[
    ClientLocalPreparationInputOriginal,
    (
      ClientLocalPreparationInputOriginal,
      @source_publication.PreparedPublishedQueryEnvironment,
    ),
  ],
  input : ClientLocalPreparationInputOriginal,
  quote : @execution.ExecutionCapacity,
) -> Result[Unit, @resources.PreparationCapacityIssue] {
  @client_local_host.reconcile_installed_source_construction(
    owner, input, quote,
  )
}

///|
#export_name("clientProgramCompleteInstalledSourceMaterial")
pub fn client_program_complete_installed_source_material(
  owner : @resources.PreparationCapacity[
    ClientLocalPreparationInputOriginal,
    (
      ClientLocalPreparationInputOriginal,
      @source_publication.PreparedPublishedQueryEnvironment,
    ),
  ],
  input : ClientLocalPreparationInputOriginal,
  source_original : ClientLocalPreparationInputOriginal,
  environment : @source_publication.PreparedPublishedQueryEnvironment,
  quote : @execution.ExecutionCapacity,
) -> Result[Unit, @resources.PreparationCapacityIssue] {
  @client_local_host.complete_installed_source_material(
    owner, input, source_original, environment, quote,
  )
}

///|
#export_name("clientProgramBorrowInstalledSourceMaterial")
pub fn client_program_borrow_installed_source_material(
  owner : @resources.PreparationCapacity[
    ClientLocalPreparationInputOriginal,
    (
      ClientLocalPreparationInputOriginal,
      @source_publication.PreparedPublishedQueryEnvironment,
    ),
  ],
) -> Result[
  @resources.PreparationBodyBorrow[
    (
      ClientLocalPreparationInputOriginal,
      @source_publication.PreparedPublishedQueryEnvironment,
    ),
  ],
  @resources.PreparationCapacityIssue,
] {
  @resources.borrow_preparation_body(owner)
}

///|
#export_name("clientProgramReturnInstalledSourceMaterial")
pub fn client_program_return_installed_source_material(
  holder : @resources.PreparationBodyBorrow[
    (
      ClientLocalPreparationInputOriginal,
      @source_publication.PreparedPublishedQueryEnvironment,
    ),
  ],
) -> Result[Bool, @resources.PreparationCapacityIssue] {
  @resources.return_preparation_body_borrow(holder)
}

///|
#export_name("clientProgramRetireInstalledSourceMaterial")
pub fn client_program_retire_installed_source_material(
  owner : @resources.PreparationCapacity[
    ClientLocalPreparationInputOriginal,
    (
      ClientLocalPreparationInputOriginal,
      @source_publication.PreparedPublishedQueryEnvironment,
    ),
  ],
  input : ClientLocalPreparationInputOriginal,
) -> Result[Bool, @resources.PreparationCapacityIssue] {
  @client_local_host.retire_installed_source_material(owner, input)
}

///|
/// Failure before typed continuation still owns this original Unit token.
/// A Continued token refuses here; this cannot abort the Source successor.
#export_name("clientProgramAbortUncontinuedSourceMaterial")
pub fn client_program_abort_uncontinued_source_material(
  owner : @resources.PreparationCapacity[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
  input : ClientLocalPreparationInputOriginal,
) -> Result[Bool, @resources.PreparationCapacityIssue] {
  @resources.abort_preparation_capacity_after_cleanup(owner, input)
}

///|
/// The fixed Source file owner admits its actual physical operation on the
/// SAME live initialization successor. Variable input/decode memory remains
/// the separate original constructor quote. No Ledger crosses this bridge.
#export_name("clientProgramBeginInstalledSourceIo")
pub fn client_program_begin_installed_source_io(
  owner : @resources.PreparationCapacity[
    ClientLocalPreparationInputOriginal,
    (
      ClientLocalPreparationInputOriginal,
      @source_publication.PreparedPublishedQueryEnvironment,
    ),
  ],
  input : ClientLocalPreparationInputOriginal,
  transfer_bytes : Int64,
) -> Result[@resources.PreparationIo, @resources.PreparationCapacityIssue] {
  @resources.begin_preparation_io(owner, input, transfer_bytes)
}

///|
#export_name("clientProgramChargeInstalledSourceIo")
pub fn client_program_charge_installed_source_io(
  operation : @resources.PreparationIo,
  bytes : Int64,
) -> Result[Unit, @resources.PreparationCapacityIssue] {
  @resources.charge_preparation_io(operation, bytes)
}

///|
#export_name("clientProgramMarkInstalledSourceIoTransferUncertain")
pub fn client_program_mark_installed_source_io_transfer_uncertain(
  operation : @resources.PreparationIo,
) -> Result[Unit, @resources.PreparationCapacityIssue] {
  @resources.mark_preparation_io_transfer_uncertain(operation)
}

///|
/// Called only by the SAME original physical operation's cleanup owner after
/// its real acknowledgement. Unit acknowledges this operation, never the
/// separate Source successor, B's initial admission or the entire Host.
#export_name("clientProgramFinishInstalledSourceIoAfterCleanup")
pub fn client_program_finish_installed_source_io_after_cleanup(
  operation : @resources.PreparationIo,
) -> Result[Unit, @resources.PreparationCapacityIssue] {
  @resources.finish_preparation_io_after_cleanup(operation)
}
