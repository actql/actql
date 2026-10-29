///|
/// Original Plan/Run/source borrowing, not a metadata or capacity issuer.
#export_name("clientProgramInstalledManagedCaptureSourceRead")
pub fn client_program_installed_managed_capture_source_read(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
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
  @client_local_host.begin_installed_managed_capture_source_read(
    owner, prepared, request, declaration, occurrence,
  )
}
