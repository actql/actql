///|
/// The same installed Run owner retains a checked Effect preparation without
/// coercing it to an Effect-free Program. Resource preparation is separate
/// from the existing allowed Run, Preview and physical Effect claims.
pub fn installed_effect_managed_run_requirements(
  prepared : @publication_host.PreparedClientEffectComputation,
  declarations : Array[@row_source_host.RowDeclaration],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[Array[Int64], ClientInstalledManagedRunIssue] {
  installed_managed_run_requirements_owned(
    Effect(prepared),
    declarations,
    query_contract_body,
    evidence_contract_body,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    false,
  )
}

///|
pub fn installed_effect_mock_model_run_requirements(
  prepared : @publication_host.PreparedClientEffectComputation,
  declarations : Array[@row_source_host.RowDeclaration],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[Array[Int64], ClientInstalledManagedRunIssue] {
  installed_managed_run_requirements_owned(
    Effect(prepared),
    declarations,
    query_contract_body,
    evidence_contract_body,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    true,
  )
}

///|
fn installed_effect_managed_request_matches(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Bool {
  let identity = @publication_host.prepared_client_effect_identity(prepared)
  identity.program_definition_cid ==
  @publication_host.client_request_program_cid(request) &&
  identity.parameter_values_cid ==
  @publication_host.client_request_parameters_cid(request)
}

///|
pub fn begin_installed_effect_managed_run(
  admission : @resources.NodeManagedRunAdmission[
    @publication_host.PreparedClientEffectComputation,
  ],
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  match
    @resources.check_node_source_compute_run_preparation(admission, prepared) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  if !installed_effect_managed_request_matches(prepared, request) {
    return Err(ForeignOriginal)
  }
  if !installed_managed_owner_shape_supported(Effect(prepared), false) {
    return Err(Unsupported)
  }
  let ledger = match @resources.start_node_managed_run_admission(admission) {
    Err(issue) => return Err(Resource(issue))
    Ok(ledger) => ledger
  }
  let value = new_installed_managed_run_owned(
    EffectManaged(admission, prepared),
    request,
    ledger,
  )
  require_installed_managed_run(value).map(_ => value)
}

///|
pub fn begin_installed_effect_mock_model_managed_run(
  admission : @resources.NodeManagedRunAdmission[
    @publication_host.PreparedClientEffectComputation,
  ],
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  compilation : @publication_host.ClientEffectCompilation,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  bootstrap_retained_bytes : Int64,
  bootstrap_execution_bytes : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[
  (ClientInstalledManagedRun, @publication_host.ClientModelReadScope),
  ClientInstalledManagedRunIssue,
] {
  match
    @resources.check_node_local_mock_model_run_preparation(admission, prepared) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  if !installed_effect_managed_request_matches(prepared, request) ||
    !@publication_host.client_compiled_run_matches_effect(
      compiled, prepared, compilation,
    ) ||
    !@publication_host.client_compiled_run_has_infer(compiled, plan) ||
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Err(_) {
    return Err(ForeignOriginal)
  }
  if !installed_managed_owner_shape_supported(Effect(prepared), true) {
    return Err(Unsupported)
  }
  let ledger = match @resources.start_node_managed_run_admission(admission) {
    Err(issue) => return Err(Resource(issue))
    Ok(ledger) => ledger
  }
  let value = new_installed_managed_run_owned(
    EffectManaged(admission, prepared),
    request,
    ledger,
  )
  let bootstrap = match
    @resources.reserve_node_managed_run_read_bootstrap(
      admission, prepared, ledger, bootstrap_retained_bytes, bootstrap_execution_bytes,
    ) {
    Err(issue) => return Err(Resource(issue))
    Ok(bootstrap) => bootstrap
  }
  let scope = match
    @publication_host.begin_client_model_read_scope(
      compiled, definition, plan, ledger, bootstrap, max_reservations, max_holdings,
      max_delegations,
    ) {
    Err(issue) => return Err(ModelRead(issue))
    Ok(scope) => scope
  }
  require_installed_managed_run(value).map(_ => (value, scope))
}

///|
pub fn check_installed_effect_managed_run(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard value.preparation is Some(preparation) else { return Err(Retired) }
  guard preparation is EffectManaged(_, original) &&
    physical_equal(original, prepared) &&
    value.request == request else {
    return Err(ForeignOriginal)
  }
  require_installed_managed_run(value).map(_ => ())
}

///|
pub fn prepare_installed_effect_managed_run_ledger(
  value : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  capacities : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  match check_installed_effect_managed_run(value, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  prepare_installed_managed_run_ledger_owned(
    value, capacities, transport_bytes, transport_execution_bytes, installed_contracts,
    values_body, fragment_body, ordered_body,
  )
}
