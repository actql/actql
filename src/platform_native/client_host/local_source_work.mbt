///|
// A reference and adoption do not supply Source authority. This closure is
// also used after journal/physical boundaries by the existing Work owner.
fn native_local_source_authorized(
  host : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  scope : String,
  source_ref : String,
) -> Bool {
  host.authority_scope_cid(principal, connection, crypto) is Ok(current) &&
  current == scope &&
  host.authorize({
    principal,
    connection,
    resource: "run",
    operation: "submit",
  })
  is Ok(@authorization.Allow(_)) &&
  host.authorize({
    principal,
    connection,
    resource: source_ref,
    operation: "read",
  })
  is Ok(@authorization.Allow(_))
}

///|
/// Direct Local Host assembly, without a Site, DispatchRequest, new scheduler
/// or caller-supplied authorization callback. The CLI supplies the typed
/// configuration projected from its exact adopted installation original.
/// The common query requirement must match that configured Source before a
/// durable start claim or physical I/O. Acquisition, tasks, cancellation and
/// cleanup remain with the same original Source/Compute Work owner.
pub fn NativeLocalHostConnection::open_source_work(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  configuration : @resident.ResidentSourceComputeConfiguration,
  occurrence : String,
  current_time : () -> String,
  observe? : (@resident.ResidentSourceComputeEvent) -> Bool,
) -> Result[NativeClientSourceWork, NativeClientSourceWorkIssue] {
  let source = configuration.source
  let scope = @host.client_request_authority_scope_cid(request)
  let current_authorization = () => {
    native_local_source_authorized(
      self,
      crypto,
      principal,
      connection,
      scope,
      source.source_ref,
    )
  }
  if !current_authorization() {
    return Err(AuthorizationDenied)
  }
  if !@resident.resident_source_compute_shape_supported(prepared) {
    return Err(Work(@resident.UnsupportedGraph))
  }
  let requirement = match
    @local.prepare_local_query_requirement(
      prepared,
      0,
      0,
      configuration.installed_contracts,
      configuration.values_body,
      Some(source.fragment_contract_body),
      None,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Work(@resident.Source(@resident.Query(issue))))
  }
  if @planning.query_requirement_source(requirement) !=
    (source.source_ref, source.source_contract_cid) {
    return Err(Work(@resident.Source(@resident.ForeignInput)))
  }
  open_native_client_local_source_work(
    self.journal,
    request,
    prepared,
    compiled,
    definition,
    configuration,
    occurrence,
    current_time,
    current_authorization,
    observe?,
  )
}
