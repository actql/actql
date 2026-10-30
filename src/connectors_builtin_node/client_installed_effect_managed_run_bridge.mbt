///|
/// Typed consumer of the same ordinary Resource supplier. An Effect owner is
/// never passed through a Pure Program ABI, nor does resource preparation
/// issue the enclosing Run's authorization or an Effect approval.
#export_name("clientProgramNodeEffectManagedRunPrepare")
pub fn client_program_node_effect_managed_run_prepare(
  original : @resources.OriginalNodeManagedRunReference,
  prepared : @publication_host.PreparedClientEffectComputation,
) -> Result[
  @resources.NodeManagedRunAdmission[
    @publication_host.PreparedClientEffectComputation,
  ],
  @resources.ImportedChildLedgerIssue,
] {
  @resources.prepare_node_managed_run_admission(original, prepared)
}

///|
#export_name("clientProgramNodeEffectLocalMockModelRunPrepare")
pub fn client_program_node_effect_local_mock_model_run_prepare(
  original : @resources.OriginalNodeManagedRunReference,
  prepared : @publication_host.PreparedClientEffectComputation,
) -> Result[
  @resources.NodeManagedRunAdmission[
    @publication_host.PreparedClientEffectComputation,
  ],
  @resources.ImportedChildLedgerIssue,
] {
  @resources.prepare_node_local_mock_model_run_admission(original, prepared)
}

///|
#export_name("clientProgramNodeEffectManagedRunCleanup")
pub fn client_program_node_effect_managed_run_cleanup(
  admission : @resources.NodeManagedRunAdmission[
    @publication_host.PreparedClientEffectComputation,
  ],
) -> Result[Unit, @resources.ImportedChildLedgerIssue] {
  @resources.cleanup_node_managed_run_admission(admission)
}

///|
#export_name("clientProgramInstalledEffectManagedRunBegin")
pub fn client_program_installed_effect_managed_run_begin(
  admission : @resources.NodeManagedRunAdmission[
    @publication_host.PreparedClientEffectComputation,
  ],
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @client_local_host.ClientInstalledManagedRun,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_installed_effect_managed_run(
    admission, prepared, request,
  )
}

///|
#export_name("clientProgramInstalledEffectMockModelManagedRunBegin")
pub fn client_program_installed_effect_mock_model_managed_run_begin(
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
  (
    @client_local_host.ClientInstalledManagedRun,
    @publication_host.ClientModelReadScope,
  ),
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_installed_effect_mock_model_managed_run(
    admission, prepared, request, compiled, compilation, definition, plan, bootstrap_retained_bytes,
    bootstrap_execution_bytes, max_reservations, max_holdings, max_delegations,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedRunCheck")
pub fn client_program_installed_effect_managed_run_check(
  value : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.check_installed_effect_managed_run(
    value, prepared, request,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedRunPrepareLedger")
pub fn client_program_installed_effect_managed_run_prepare_ledger(
  value : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  capacities : Array[@client_local_host.ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[
  @resources.Ledger,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_effect_managed_run_ledger(
    value, prepared, request, capacities, transport_bytes, transport_execution_bytes,
    installed_contracts, values_body, fragment_body, ordered_body,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedRunRequirements")
pub fn client_program_installed_effect_managed_run_requirements(
  prepared : @publication_host.PreparedClientEffectComputation,
  declarations : Array[@client_row_source_host.RowDeclaration],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[Array[Int64], @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.installed_effect_managed_run_requirements(
    prepared, declarations, query_contract_body, evidence_contract_body, transport_bytes,
    transport_execution_bytes, installed_contracts, values_body, fragment_body, ordered_body,
  )
}

///|
#export_name("clientProgramInstalledEffectMockModelManagedRunRequirements")
pub fn client_program_installed_effect_mock_model_managed_run_requirements(
  prepared : @publication_host.PreparedClientEffectComputation,
  compiled : @publication_host.ClientCompiledRun,
  compilation : @publication_host.ClientEffectCompilation,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  declarations : Array[@client_row_source_host.RowDeclaration],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[Array[Int64], @client_local_host.ClientInstalledManagedRunIssue] {
  if !@publication_host.client_compiled_run_matches_effect(
      compiled, prepared, compilation,
    ) {
    return Err(ForeignOriginal)
  }
  let selected = match
    original_composed_model_limits(compiled, definition, occurrence, graph) {
    Err(_) => return Err(ForeignOriginal)
    Ok(value) => value
  }
  let base = match
    @client_local_host.installed_effect_mock_model_run_requirements(
      prepared, declarations, query_contract_body, evidence_contract_body, transport_bytes,
      transport_execution_bytes, installed_contracts, values_body, fragment_body,
      ordered_body,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  combine_installed_mock_model_run_requirements(base, selected)
}
