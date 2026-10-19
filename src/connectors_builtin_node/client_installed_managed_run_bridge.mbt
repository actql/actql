///|
/// The fixed Node Root issues the original before covered preparation. This
/// private bridge retains it; no public object or Source-only child can issue
/// the separate managed-Compute admission.
#export_name("clientProgramNodeManagedRunPrepare")
pub fn client_program_node_managed_run_prepare(
  original : @resources.OriginalNodeManagedRunReference,
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  @resources.NodeManagedRunAdmission[@publication_host.PreparedClientProgram],
  @resources.ImportedChildLedgerIssue,
] {
  @resources.prepare_node_managed_run_admission(original, prepared)
}

///|
/// A separate fixed Root operation must supply the local no-I/O Mock purpose.
/// Source/Compute admission and numerical requirements cannot issue it.
#export_name("clientProgramNodeLocalMockModelRunPrepare")
pub fn client_program_node_local_mock_model_run_prepare(
  original : @resources.OriginalNodeManagedRunReference,
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  @resources.NodeManagedRunAdmission[@publication_host.PreparedClientProgram],
  @resources.ImportedChildLedgerIssue,
] {
  @resources.prepare_node_local_mock_model_run_admission(original, prepared)
}

///|
/// Install the compiler/Run Scope on that exact parent before Source children.
/// The Host retains the admission before calling, including failed begin.
#export_name("clientProgramInstalledMockModelManagedRunBegin")
pub fn client_program_installed_mock_model_managed_run_begin(
  admission : @resources.NodeManagedRunAdmission[
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  bootstrap_retained_bytes : Int64,
  bootstrap_execution_bytes : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[
  (
    @client_local_host.ClientInstalledManagedRun,
    @publication_host.ClientModelReadScope,
  ),
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_installed_mock_model_managed_run(
    admission, prepared, request, compiled, definition, plan, bootstrap_retained_bytes,
    bootstrap_execution_bytes, max_reservations, max_holdings, max_delegations,
  )
}

///|
/// Reach the same original partial carrier even when begin returned no Run.
/// Only the Resource owner may distinguish unpublished from actual usage;
/// this bridge supplies no manufactured zero report or replacement claim.
#export_name("clientProgramNodeManagedRunCleanup")
pub fn client_program_node_managed_run_cleanup(
  admission : @resources.NodeManagedRunAdmission[
    @publication_host.PreparedClientProgram,
  ],
) -> Result[Unit, @resources.ImportedChildLedgerIssue] {
  @resources.cleanup_node_managed_run_admission(admission)
}

///|
#export_name("clientProgramInstalledManagedRunBegin")
pub fn client_program_installed_managed_run_begin(
  admission : @resources.NodeManagedRunAdmission[
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @client_local_host.ClientInstalledManagedRun,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_installed_managed_run(admission, prepared, request)
}

///|
#export_name("clientProgramInstalledManagedRunCheck")
pub fn client_program_installed_managed_run_check(
  value : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.check_installed_managed_run(value, prepared, request)
}

///|
#export_name("clientProgramInstalledManagedRunSourceRead")
pub fn client_program_installed_managed_run_source_read(
  value : @client_local_host.ClientInstalledManagedRun,
  occurrence : Int,
) -> Result[
  @client_local_host.ClientInstalledSourceRead,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_installed_managed_run_source_read(value, occurrence)
}

///|
#export_name("clientProgramInstalledManagedRunRequirements")
pub fn client_program_installed_managed_run_requirements(
  prepared : @publication_host.PreparedClientProgram,
  declarations : Array[@client_row_source_host.RowDeclaration],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[Array[Int64], @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.installed_managed_run_requirements(
    prepared, declarations, query_contract_body, evidence_contract_body, transport_bytes,
    transport_execution_bytes, registry_body, values_body, fragment_body, ordered_body,
  )
}

///|
#export_name("clientProgramInstalledManagedRunPrepareLedger")
pub fn client_program_installed_managed_run_prepare_ledger(
  value : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  capacities : Array[@client_local_host.ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[
  @resources.Ledger,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_managed_run_ledger(
    value, prepared, request, capacities, transport_bytes, transport_execution_bytes,
    registry_body, values_body, fragment_body, ordered_body,
  )
}

///|
#export_name("clientProgramInstalledManagedRunRetire")
pub fn client_program_installed_managed_run_retire(
  value : @client_local_host.ClientInstalledManagedRun,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.retire_installed_managed_run(value)
}
