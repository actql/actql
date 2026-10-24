///|
// Preflight is not a start claim or Effect permission. The same adopted Host
// and independent Source read authority are rechecked by the original Work
// owner after its journal and physical boundaries.
fn NativeLocalHostConnection::check_effect_source_work(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  source_ref : String,
) -> Result[@host.PreparedClientEffectRun, NativeClientSourceWorkIssue] {
  if !native_local_source_authorized(
      self,
      crypto,
      principal,
      connection,
      @host.client_request_authority_scope_cid(request),
      source_ref,
    ) {
    return Err(AuthorizationDenied)
  }
  let prepared = @host.client_effect_compilation_owner(allowed.compilation)
  if @host.prepared_client_effect_request_scope(prepared, request) is Err(_) {
    return Err(Journal(ChangedIntent))
  }
  let checked = match
    @host.bind_client_effect_compiled_run(prepared, allowed, definition) {
    Ok(value) => value
    Err(issue) => return Err(Work(EffectRun(issue)))
  }
  if !@resident.resident_effect_source_compute_shape_supported(checked) {
    return Err(Work(UnsupportedGraph))
  }
  Ok(checked)
}

///|
/// Connect an already accepted original Effect Run to the existing acquired
/// Source/Compute/capture owner using the real adopted Local Host. Configuration
/// is projected by trusted assembly from its selected installation original.
/// This authorizes acquisition only; approval and Provider dispatch retain
/// their independent Effect and credential owners. No Site or Dispatch is made.
pub fn NativeLocalHostConnection::open_effect_source_work(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  materials : @host.ClientEffectRunMaterials,
  configuration : @resident.ResidentSourceComputeConfiguration,
  occurrence : String,
  current_time : () -> String,
  observe? : (@resident.ResidentSourceComputeEvent) -> Bool,
) -> Result[NativeClientEffectSourceWork, NativeClientSourceWorkIssue] {
  let source = configuration.source
  match
    self.check_effect_source_work(
      crypto,
      principal,
      connection,
      request,
      allowed,
      definition,
      source.source_ref,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let prepared = @host.client_effect_compilation_owner(allowed.compilation)
  let requirement = match
    @local.prepare_effect_local_query_requirement(
      prepared,
      0,
      0,
      configuration.installed_contracts,
      configuration.values_body,
      Some(source.fragment_contract_body),
      None,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Work(Source(Query(issue))))
  }
  if @planning.query_requirement_source(requirement) !=
    (source.source_ref, source.source_contract_cid) {
    return Err(Work(Source(ForeignInput)))
  }
  let scope = @host.client_request_authority_scope_cid(request)
  open_native_client_effect_source_work(
    self.journal,
    request,
    allowed,
    definition,
    materials,
    configuration,
    occurrence,
    current_time,
    () => {
      native_local_source_authorized(
        self,
        crypto,
        principal,
        connection,
        scope,
        source.source_ref,
      )
    },
    observe?,
  )
}
