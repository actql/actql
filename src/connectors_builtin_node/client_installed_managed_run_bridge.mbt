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
/// The ordinary same-Run Scope issues its original read before the input
/// component starts. No physical-layout factory or second Ledger is involved.
#export_name("clientProgramPrepareInferOriginalRead")
pub fn client_program_prepare_infer_original_read(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @publication_host.ClientInferPlanGraph,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[
  @publication_host.ClientModelReadPreparation,
  @publication_host.ClientModelReadPreparationIssue,
] {
  if !@publication_host.client_model_read_scope_live(
      scope, compiled, definition, graph,
    ) {
    return Err(ForeignRun)
  }
  @publication_host.prepare_client_model_read(
    scope, retained_bytes, execution_bytes,
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
/// Compose the existing Source/Compute limits with the separately selected
/// local Mock purpose before either Source starts. These are ordinary managed
/// limits, not a RAM reservation or an allocation-success guarantee. The
/// actual Host/Resource original still issues the distinct admission.
#export_name("clientProgramInstalledMockModelManagedRunRequirements")
pub fn client_program_installed_mock_model_managed_run_requirements(
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
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
  if !@publication_host.client_compiled_run_matches(compiled, prepared) {
    return Err(ForeignOriginal)
  }
  let selected = match
    @infer_host.original_composed_bounds(
      compiled, definition, occurrence, graph,
    ) {
    Err(_) => return Err(ForeignOriginal)
    Ok(value) => value
  }
  let base = match
    @client_local_host.installed_mock_model_run_requirements(
      prepared, declarations, query_contract_body, evidence_contract_body, transport_bytes,
      transport_execution_bytes, registry_body, values_body, fragment_body, ordered_body,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  combine_installed_mock_model_run_requirements(base, selected)
}

///|
fn combine_installed_mock_model_run_requirements(
  base : Array[Int64],
  selected : @infer_host.Limits,
) -> Result[Array[Int64], @client_local_host.ClientInstalledManagedRunIssue] {
  let model = selected.model.ledger
  // Keep the existing bounded input/read allowance separate from both the
  // Scope bootstrap and Model purpose. No alias count or byte sum issues a
  // physical supplier. The ordinary platform remains responsible for actual
  // allocation and failures, and each acquired child keeps its own cleanup.
  let read_retained = selected.mapping.logical.max_live_value_bytes
  let read_execution = selected.identity.wire.max_bytes.to_int64()
  let extra = [
    model.planning_work.to_int64(),
    model.attempts.to_int64(),
    model.holdings.to_int64(),
    model.transfer_bytes,
    model.retained_bytes + read_retained * 2L,
    model.execution_bytes + read_execution * 2L,
  ]
  for index in 0..<6 {
    let maximum = if index < 3 { 2147483647L } else { 9223372036854775807L }
    if extra[index] < 0L || base[index] > maximum - extra[index] {
      return Err(InsufficientCapacity)
    }
    base[index] += extra[index]
  }
  // The private tuple also carries the selected reservation/census bounds;
  // JS never reaches into compiler-owned Limits fields or invents a second
  // numeric profile. Bootstrap, read and Model remain separate same-Run tokens.
  for
    value in [
      read_retained,
      read_execution,
      read_retained,
      read_execution,
      read_retained,
      read_execution,
      selected.input.rows.operation_entries.to_int64(),
      selected.input.rows.retained_entries.to_int64(),
      selected.input.rows.metadata_entries.to_int64(),
    ] {
    base.push(value)
  }
  Ok(base)
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
