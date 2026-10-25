///|
/// Fixed ordinary Local dependency custody only. These operations consume
/// original Core handles; there is no numeric reservation/factory export.
#export_name("clientProgramInstalledManagedPreparationBorrow")
pub fn client_program_installed_managed_preparation_borrow(
  value : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram]?,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.borrow_installed_managed_dispatch_preparation(
    value, prepared, request,
  )
}

///|
#export_name("clientProgramPreparationBorrowRead")
pub fn client_program_preparation_borrow_read(
  value : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ],
) -> @publication_host.PreparedClientProgram? {
  @resources.preparation_body_borrow_value(value)
}

///|
#export_name("clientProgramPreparationBorrowReturn")
pub fn client_program_preparation_borrow_return(
  value : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ],
) -> Result[Bool, @resources.PreparationCapacityIssue] {
  @resources.return_preparation_body_borrow(value)
}

///|
#export_name("clientProgramInstalledPreparationPayloadSevered")
pub fn client_program_installed_preparation_payload_severed(
  value : @client_local_host.ClientInstalledManagedRun,
  request : @publication_host.ClientRequestIdentity,
) -> Bool {
  @client_local_host.installed_preparation_payload_severed(value, request)
}

///|
#export_name("clientProgramInstalledPreparationUsageIsolated")
pub fn client_program_installed_preparation_usage_isolated(
  value : @client_local_host.ClientInstalledManagedRun,
  request : @publication_host.ClientRequestIdentity,
  captured : @strategy.CapturedDAG,
) -> Bool {
  @client_local_host.installed_managed_preparation_usage_isolated(
    value, request, captured,
  )
}

///|
#export_name("clientProgramPreparationBorrowUsageIsolated")
pub fn client_program_preparation_borrow_usage_isolated(
  value : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ],
  captured : @strategy.CapturedDAG,
) -> Bool {
  @resources.preparation_body_usage_isolated(
    value,
    @strategy.captured_dag_ledger(captured),
  )
}

///|
/// Sibling dependency on the same original Core owner, not a new grant or a
/// JavaScript holder count. The fixed registry binds this before dispatch.
#export_name("clientProgramPreparationBorrowSibling")
pub fn client_program_preparation_borrow_sibling(
  value : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ],
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  @resources.PreparationCapacityIssue,
] {
  @resources.borrow_preparation_body_sibling(value)
}

///|
/// Provenance of this same original holder's retirement phase, not physical
/// quiescence or a release acknowledgement.
#export_name("clientProgramPreparationBorrowRetirementStarted")
pub fn client_program_preparation_borrow_retirement_started(
  value : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ],
) -> Bool {
  @resources.preparation_body_retirement_started(value)
}
