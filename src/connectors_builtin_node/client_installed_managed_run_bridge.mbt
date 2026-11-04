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
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[Array[Int64], @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.installed_managed_run_requirements(
    prepared, declarations, query_contract_body, evidence_contract_body, transport_bytes,
    transport_execution_bytes, installed_contracts, values_body, fragment_body, ordered_body,
  )
}

///|
#export_name("clientProgramPreparedInstalledManagedSourceFreeRequirements")
pub fn client_program_prepared_installed_managed_source_free_requirements(
  original : @client_local_host.ClientInstalledManagedSourceFreePreparation,
) -> Array[Int64] {
  @client_local_host.prepared_installed_managed_source_free_requirements(
    original,
  )
}

///|
#export_name("clientProgramInstalledManagedSourceFreeBegin")
pub fn client_program_installed_managed_source_free_begin(
  admission : @resources.NodeManagedRunAdmission[
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  original : @client_local_host.ClientInstalledManagedSourceFreePreparation,
) -> Result[
  @client_local_host.ClientInstalledManagedRun,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_prepared_installed_managed_source_free_run(
    admission, prepared, request, original,
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
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[Array[Int64], @client_local_host.ClientInstalledManagedRunIssue] {
  if !@publication_host.client_compiled_run_matches(compiled, prepared) {
    return Err(ForeignOriginal)
  }
  let selected = match
    original_composed_model_limits(compiled, definition, occurrence, graph) {
    Err(_) => return Err(ForeignOriginal)
    Ok(value) => value
  }
  let base = match
    @client_local_host.installed_mock_model_run_requirements(
      prepared, declarations, query_contract_body, evidence_contract_body, transport_bytes,
      transport_execution_bytes, installed_contracts, values_body, fragment_body,
      ordered_body,
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
  // The domain has exactly the existing bootstrap/read pair. Compose their
  // immutable demands through the Ledger owner BEFORE forming any sum. No
  // intermediate multiplication or addition may wrap before admission.
  let read : @resources.LedgerLimits = {
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: read_retained,
    execution_bytes: read_execution,
  }
  guard base.length() == 6 &&
    base[0] >= 0L &&
    base[0] <= 2147483647L &&
    base[1] >= 0L &&
    base[1] <= 2147483647L &&
    base[2] >= 0L &&
    base[2] <= 2147483647L &&
    @resources.add_ledger_limits(model, read) is Some(with_bootstrap) &&
    @resources.add_ledger_limits(with_bootstrap, read) is Some(extra) &&
    @resources.add_ledger_limits(
      {
        planning_work: base[0].to_int(),
        attempts: base[1].to_int(),
        holdings: base[2].to_int(),
        transfer_bytes: base[3],
        retained_bytes: base[4],
        execution_bytes: base[5],
      },
      extra,
    )
    is Some(combined) else {
    return Err(InsufficientCapacity)
  }
  // Commit the private six-number projection only after the complete typed
  // composition succeeds. Failed arithmetic cannot leave a partially changed
  // vector for the existing consumer or its diagnostic path.
  base[0] = combined.planning_work.to_int64()
  base[1] = combined.attempts.to_int64()
  base[2] = combined.holdings.to_int64()
  base[3] = combined.transfer_bytes
  base[4] = combined.retained_bytes
  base[5] = combined.execution_bytes
  // The private tuple also carries the selected reservation/census bounds;
  // JS never reaches into compiler-owned Limits fields or invents a second
  // numeric profile. Bootstrap, read and Model remain separate same-Run tokens.
  for value in client_program_composed_infer_retained_limits(selected) {
    base.push(value)
  }
  Ok(base)
}

///|
/// Project only the already selected Limits retained by the same preparation.
/// This is the existing private requirement suffix, without recomputing the
/// Model/Source quote or consulting a Run. Bootstrap/read/Model byte pairs and
/// the three live inventory bounds keep their existing order and meaning.
/// These DATA neither reserve resources nor establish current authority.
#export_name("clientProgramComposedInferRetainedLimits")
pub fn client_program_composed_infer_retained_limits(
  selected : @infer_host.Limits,
) -> Array[Int64] {
  let retained = selected.mapping.logical.max_live_value_bytes
  let execution = selected.identity.wire.max_bytes.to_int64()
  [
    retained,
    execution,
    retained,
    execution,
    retained,
    execution,
    selected.input.rows.operation_entries.to_int64(),
    selected.input.rows.retained_entries.to_int64(),
    selected.input.rows.metadata_entries.to_int64(),
  ]
}

///|
/// The legacy suffix above describes its read allowances. A physical Request
/// Plan separately requires the SAME selected Model ledger floor. Read only
/// those stored amounts; do not select bounds, quote, reserve or issue again.
#export_name("clientProgramComposedInferModelLedgerBytes")
pub fn client_program_composed_infer_model_ledger_bytes(
  selected : @infer_host.Limits,
) -> Array[Int64] {
  [selected.model.ledger.retained_bytes, selected.model.ledger.execution_bytes]
}

///|
#export_name("clientProgramInstalledManagedCaptureRunRequirements")
pub fn client_program_installed_managed_capture_run_requirements(
  prepared : @publication_host.PreparedClientProgram,
  capacities : Array[@client_local_host.ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[Array[Int64], @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.installed_managed_capture_run_requirements(
    prepared, capacities, transport_bytes, transport_execution_bytes, installed_contracts,
    values_body, fragment_body, ordered_body,
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
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[
  @resources.Ledger,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_managed_run_ledger(
    value, prepared, request, capacities, transport_bytes, transport_execution_bytes,
    installed_contracts, values_body, fragment_body, ordered_body,
  )
}

///|
#export_name("clientProgramInstalledManagedRunRetire")
pub fn client_program_installed_managed_run_retire(
  value : @client_local_host.ClientInstalledManagedRun,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.retire_installed_managed_run(value)
}

///|
// The ordinary Content purpose is distinct from both Source-only and Mock
// Model ports. This consumes the same actual installer original; no number,
// public packet or existing Ledger can construct it.
#export_name("clientProgramNodeLocalContentRunPrepare")
pub fn client_program_node_local_content_run_prepare(
  original : @resources.OriginalNodeManagedRunReference,
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  @resources.NodeManagedRunAdmission[@publication_host.PreparedClientProgram],
  @resources.ImportedChildLedgerIssue,
] {
  @resources.prepare_node_local_content_run_admission(original, prepared)
}

///|
#export_name("clientProgramInstalledManagedKeyedContentRequirements")
pub fn client_program_installed_managed_keyed_content_requirements(
  value : @client_local_host.ClientInstalledManagedKeyedPreparation,
) -> Array[Int64] {
  @client_local_host.installed_managed_keyed_content_requirements(value)
}

///|
#export_name("clientProgramInstalledManagedKeyedContentCheckPreparation")
pub fn client_program_installed_managed_keyed_content_check_preparation(
  value : @client_local_host.ClientInstalledManagedKeyedPreparation,
  prepared : @publication_host.PreparedClientProgram,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.check_installed_managed_keyed_content_preparation(
    value, prepared,
  )
}

///|
#export_name("clientProgramInstalledManagedKeyedSourceRead")
pub fn client_program_installed_managed_keyed_source_read(
  value : @client_local_host.ClientInstalledManagedRun,
  keyed : @publication_host.ClientKeyedAcquisition,
  request : @publication_host.ClientKeyedRequest,
  declaration : @client_row_source_host.RowDeclaration,
) -> Result[
  @client_local_host.ClientInstalledKeyedSourceRead,
  @client_local_host.ClientInstalledSourceReadIssue,
] {
  @client_local_host.begin_installed_managed_keyed_source_read(
    value, keyed, request, declaration,
  )
}

///|
#export_name("clientProgramInstalledKeyedSourceReadCheckCurrent")
pub fn client_program_installed_keyed_source_read_check_current(
  value : @client_local_host.ClientInstalledKeyedSourceRead,
) -> Result[Unit, @client_local_host.ClientInstalledSourceReadIssue] {
  @client_local_host.check_installed_keyed_source_read_current(value)
}

///|
#export_name("clientProgramInstalledKeyedSourceReadCheckLedger")
pub fn client_program_installed_keyed_source_read_check_ledger(
  value : @client_local_host.ClientInstalledKeyedSourceRead,
  ledger : @resources.Ledger,
) -> Result[Unit, @client_local_host.ClientInstalledSourceReadIssue] {
  @client_local_host.check_installed_keyed_source_read_ledger(value, ledger)
}

///|
#export_name("clientProgramInstalledKeyedSourceReadAcquisition")
pub fn client_program_installed_keyed_source_read_acquisition(
  value : @client_local_host.ClientInstalledKeyedSourceRead,
) -> Result[
  @client_row_source_host.RowKeyedAcquisition,
  @client_local_host.ClientInstalledSourceReadIssue,
] {
  @client_local_host.installed_keyed_source_read_acquisition(value)
}

///|
#export_name("clientProgramInstalledKeyedSourceReadStartRows")
pub fn client_program_installed_keyed_source_read_start_rows(
  value : @client_local_host.ClientInstalledKeyedSourceRead,
  acquisition : @client_row_source_host.RowKeyedAcquisition,
  nonce : String,
  original_stop : (@client_row_source_host.RowAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_bytes : Int64,
  cleanup_confirmed : (@client_row_source_host.RowAttempt) -> Bool,
) -> Result[
  @client_row_source_host.RowRun,
  @client_local_host.ClientInstalledSourceReadIssue,
] {
  @client_local_host.start_installed_keyed_source_read_rows(
    value, acquisition, nonce, original_stop, transfer_bytes, execution_bytes, cleanup_confirmed,
  )
}

///|
#export_name("clientProgramInstalledKeyedSourceReadRetire")
pub fn client_program_installed_keyed_source_read_retire(
  value : @client_local_host.ClientInstalledKeyedSourceRead,
) -> Result[Unit, @client_local_host.ClientInstalledSourceReadIssue] {
  @client_local_host.retire_installed_keyed_source_read(value)
}

///|
/// Project only the original typed refusal. This is not evidence of journal
/// nonexecution and must be used only at the owning pre-admission boundary.
#export_name("clientProgramInstalledManagedRunIssueIsUnsupported")
pub fn client_program_installed_managed_run_issue_is_unsupported(
  issue : @client_local_host.ClientInstalledManagedRunIssue,
) -> Bool {
  match issue {
    @client_local_host.Unsupported => true
    _ => false
  }
}

///|
/// Complete only the same Run's original child/control phase. The original
/// Scope and preparation parent keep their separate cleanup obligations.
#export_name("clientProgramInstalledManagedRunQuiesce")
pub fn client_program_installed_managed_run_quiesce(
  value : @client_local_host.ClientInstalledManagedRun,
) -> Result[Unit, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.quiesce_installed_managed_run(value)
}
