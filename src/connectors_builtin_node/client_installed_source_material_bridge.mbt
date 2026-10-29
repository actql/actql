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
