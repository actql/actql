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

///|
/// The same Request owns the captured Plan and its accounted module artifact.
/// Constructor backing and the original Plan input borrow precede this call.
#export_name("clientProgramPrepareRequestCaptureModuleBody")
pub fn client_program_prepare_request_capture_module_body(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  plan : @client_local_host.ClientInstalledManagedCapturePlan,
  invocation : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
    @publication_host.ClientCompiledRun,
    @publication.PublicationContract,
  )?,
) -> Result[Unit, ClientRequestProgramModuleBridgeIssue] {
  let manifests = match client_generated_compilation_manifests() {
    Ok(value) => value
    Err(issue) => return Err(Manifests(issue))
  }
  @client_local_host.prepare_request_capture_module_body(
    parent,
    input,
    plan,
    manifests~,
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    provider_factory=installed_client_family_providers,
    invocation~,
  ).map_err(issue => Preparation(issue))
}

///|
#export_name("clientProgramInstalledManagedDuckDBCapture")
pub fn client_program_installed_managed_duckdb_capture(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  occurrence : Int,
) -> Result[
  (
    @planning.QueryRequirement,
    @client_local_host.ClientInstalledCaptureCapacity,
  ),
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_managed_duckdb_capture(
    owner, prepared, request, occurrence,
  )
}
