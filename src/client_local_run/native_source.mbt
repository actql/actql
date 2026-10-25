///|
/// Installed physical read binding for one original checked Source occurrence.
/// This is neither a Source grant nor a durable acquisition/recovery record.
pub struct LocalNativeSourceConfiguration {
  plan : LocalRunPlan
  requirement : @planning.QueryRequirement
  setup : @acquisition_host.NativeHostConfiguration
  read_tuple : @authorization.AccessTuple
  read_context_cid : String
  read_account_id : String
}

///|
pub(all) enum LocalNativeSourceIssue {
  UnsupportedCapability
  InvalidReadBinding
  ForeignRunStart
  AuthorizationMismatch
  Requirement(@local.ClientLocalQueryIssue)
  Configuration(@local.ClientDuckDBAcquisitionIssue)
  Host(@acquisition_host.NativeHostIssue)
}

///|
/// Host-installed database/schema/table and read identity are separate from
/// authored input. The same common checked sequence issues the requirement.
/// The explicit Native-only configuration creates no physical database I/O.
pub fn configure_local_native_source(
  plan : LocalRunPlan,
  stage : Int,
  source_index : Int,
  installed_contracts : @local.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  database_schema : String,
  table : String,
  query_contract_body : String,
  evidence_contract_body : String,
  two_receipt_contract_body : String,
  read_tuple : @authorization.AccessTuple,
  read_account : @authorization.AdmittedAccountConfiguration,
  read_context_cid : String,
) -> Result[LocalNativeSourceConfiguration, LocalNativeSourceIssue] {
  if !captured_source_profile(plan.prepared) {
    return Err(UnsupportedCapability)
  }
  if read_tuple.principal != plan.tuple.principal ||
    read_tuple.connection.is_empty() ||
    read_tuple.resource.is_empty() ||
    read_tuple.operation != "read" {
    return Err(InvalidReadBinding)
  }
  let requirement = match
    @local.prepare_local_query_requirement(
      plan.prepared,
      stage,
      source_index,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Requirement(issue))
  }
  let setup = match
    @local.prepare_client_duckdb_acquisition(
      requirement, database_schema, table, query_contract_body, evidence_contract_body,
      two_receipt_contract_body,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Configuration(issue))
  }
  Ok({
    plan,
    requirement,
    setup,
    read_tuple,
    read_context_cid,
    read_account_id: read_account.account_id(),
  })
}

///|
pub fn local_native_source_requirement(
  configuration : LocalNativeSourceConfiguration,
) -> @planning.QueryRequirement {
  configuration.requirement
}

///|
pub fn local_native_source_configuration(
  configuration : LocalNativeSourceConfiguration,
) -> @acquisition_host.NativeHostConfiguration {
  configuration.setup
}

///|
/// Evaluate the current installed read account against the exact original
/// requirement and physical binding. Configuration readiness is not a permit.
pub fn authorize_local_native_source(
  configuration : LocalNativeSourceConfiguration,
  current : @authorization.AdmittedAccountConfiguration,
) -> Result[@authorization.DispatchAuthorization, LocalNativeSourceIssue] {
  if current.account_id() != configuration.read_account_id {
    return Err(AuthorizationMismatch)
  }
  @authorization.bind_dispatch_authorization(
    current,
    configuration.read_tuple,
    @authorization.Acquisition,
    @planning.query_requirement_cid(configuration.requirement),
    configuration.read_context_cid,
  ).map_err(_ => AuthorizationMismatch)
}

///|
/// Only the exact original pre-I/O Run start and a current, subject-bound
/// Acquisition authorization can enter the existing Native attempt Owner.
/// The transport callback reports actual settled read-view facts; it cannot
/// supply a logical Source completion or substitute another issued attempt.
/// The installing Host must retain the issued attempt and durably record its
/// physical invocation. This function does not infer unstarted work or retry.
pub fn start_local_native_source(
  configuration : LocalNativeSourceConfiguration,
  start : LocalRunPhysicalStart,
  permit : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  nonce : String,
  transport_matches : (@duckdb_acquisition.DuckDBNativeAttempt) -> Bool,
) -> Result[@acquisition_host.NativeHostRun, LocalNativeSourceIssue] {
  if !physical_equal(configuration.plan, start.plan) {
    return Err(ForeignRunStart)
  }
  if current.account_id() != configuration.read_account_id ||
    !@authorization.dispatch_authorization_matches(
      permit,
      current,
      configuration.read_tuple,
      @authorization.Acquisition,
      @planning.query_requirement_cid(configuration.requirement),
      configuration.read_context_cid,
    ) {
    return Err(AuthorizationMismatch)
  }
  @acquisition_host.start_configured_native_host(
    configuration.setup,
    nonce,
    transport_matches,
  ).map_err(issue => Host(issue))
}
