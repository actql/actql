///|
/// Closed pre-Plan choice from the same original Prepared/Request invocation.
#export_name("clientProgramSelectInstalledSourceInput")
pub fn client_program_select_installed_source_input(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  stage : Int,
  source_index : Int,
) -> Result[
  @acquisition.SourceAcquisitionRoute,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.select_installed_source_input(
    prepared, request, stage, source_index,
  )
}

///|
#export_name("clientProgramSelectInstalledEffectSourceInput")
pub fn client_program_select_installed_effect_source_input(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  stage : Int,
  source_index : Int,
) -> Result[
  @acquisition.SourceAcquisitionRoute,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.select_installed_effect_source_input(
    prepared, request, stage, source_index,
  )
}

///|
#export_name("clientProgramPrepareWholeSourceCapacity")
pub fn client_program_prepare_whole_source_capacity(
  prepared : @publication_host.PreparedClientProgram,
  selection : @acquisition.SourceAcquisitionRoute,
  declaration : @client_row_source_host.RowDeclaration,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  provider : @execution.ExecutionCapacity?,
  max_rows : Int,
  max_page_bytes : Int,
  max_page_nodes : Int,
  max_page_depth : Int,
  max_page_rows : Int,
) -> Result[
  @client_local_host.ClientInstalledWholeSourceCapacity,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  guard selection is @acquisition.WholeInputRoute(original) else {
    return Err(@client_local_host.Unsupported)
  }
  @client_local_host.prepare_installed_whole_source_capacity(
    prepared,
    original,
    declaration,
    contracts,
    @client_local_host.installed_row_input_policy(
      max_rows, max_page_bytes, max_page_nodes, max_page_depth, max_page_rows,
    ),
    provider,
  )
}

///|
#export_name("clientProgramSelectedSourceInputKind")
pub fn client_program_selected_source_input_kind(
  selection : @acquisition.SourceAcquisitionRoute,
) -> String {
  match selection {
    @acquisition.QueryRoute(_) => "query"
    @acquisition.WholeInputRoute(_) => "whole-input"
  }
}

///|
#export_name("clientProgramSelectedSourceInputRef")
pub fn client_program_selected_source_input_ref(
  selection : @acquisition.SourceAcquisitionRoute,
) -> String? {
  let facts = match selection {
    @acquisition.QueryRoute(query) =>
      @planning.query_acquisition_source_evidence_facts(query)
    @acquisition.WholeInputRoute(original) =>
      @planning.source_acquisition_evidence_facts(original)
  }
  facts.map(value => value.source_ref)
}

///|
/// Identity DATA from the exact Program/Parameters/source occurrence. No Query
/// contract or provider snapshot is issued for an ordinary Source input.
#export_name("clientProgramWholeSourceInputIdentity")
pub fn client_program_whole_source_input_identity(
  prepared : @publication_host.PreparedClientProgram,
  original : @acquisition.SourceAcquisition,
) -> Array[String]? {
  if !@publication_host.client_source_acquisition_matches_program(
      prepared, 0, 0, original,
    ) {
    return None
  }
  let identity = @publication_host.prepared_client_identity(prepared)
  Some([identity.program_definition_cid, identity.parameter_values_cid])
}

///|
#export_name("clientProgramWholeSourceCapacityAcquisition")
pub fn client_program_whole_source_capacity_acquisition(
  capacity : @client_local_host.ClientInstalledWholeSourceCapacity,
) -> @client_row_source_host.RowInputAcquisition {
  @client_local_host.installed_whole_source_acquisition(capacity)
}

///|
#export_name("clientProgramWholeSourceCapacityMatches")
pub fn client_program_whole_source_capacity_matches(
  capacity : @client_local_host.ClientInstalledWholeSourceCapacity,
  acquisition : @client_row_source_host.RowInputAcquisition,
  provider : @execution.ExecutionCapacity,
) -> Bool {
  @client_local_host.check_installed_whole_source_capacity(
    capacity, acquisition, provider,
  )
}

///|
#export_name("clientProgramInstalledManagedSourceInputKind")
pub fn client_program_installed_managed_source_input_kind(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[String, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.installed_managed_source_input_kind(
    owner, prepared, request,
  )
}

///|
#export_name("clientProgramWholeSourceCheckComputeBinding")
pub fn client_program_whole_source_check_compute_binding(
  capture : @client_row_source_host.RowSourceCapture,
  dag : @strategy.CapturedDAG,
  task : Int,
) -> Result[Unit, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.check_row_input_compute_binding(capture, dag, task)
}

///|
#export_name("clientProgramInstalledManagedRequiresAcquisitionResultPublication")
pub fn client_program_installed_managed_requires_acquisition_result_publication(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[Bool, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.installed_managed_acquisition_result_publication(
    owner, prepared, request,
  )
}

///|
#export_name("clientProgramInstalledManagedWholeSourceLedger")
pub fn client_program_installed_managed_whole_source_ledger(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  capacity : @client_local_host.ClientInstalledWholeSourceCapacity,
  transfer : Int64,
  scratch : Int64,
) -> Result[
  @resources.Ledger,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_managed_whole_source_ledger(
    owner, prepared, request, capacity, transfer, scratch,
  )
}

///|
#export_name("clientProgramInstalledManagedPublicationSourceKind")
pub fn client_program_installed_managed_publication_source_kind(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
) -> Result[String, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.installed_managed_publication_source_kind(owner, prepared)
}

///|
#export_name("clientProgramIssueWholeSourcePublicationInvocation")
pub fn client_program_issue_whole_source_publication_invocation(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  capture : @client_row_source_host.RowSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
  source : @publication.RunEvidenceValue,
  input : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.issue_program_whole_source_publication_invocation(
    owner, prepared, compiled, definition, capture, identity, source, input, authority_scope_cid,
    data_policy_cid, capture_started_at, capture_completed_at, max_wire_bytes, max_nodes,
    max_depth,
  )
}

///|
#export_name("clientProgramWholeSourceFacts")
pub fn client_program_whole_source_facts(
  acquisition : @client_row_source_host.RowInputAcquisition,
) -> Array[String] {
  @planning.query_source_evidence_fact_values(
    @client_row_source_host.row_input_acquisition_facts(acquisition),
  )
}

///|
#export_name("clientProgramWholeSourceTarget")
pub fn client_program_whole_source_target(
  acquisition : @client_row_source_host.RowInputAcquisition,
) -> Array[String] {
  let (resource, columns) = @client_row_source_host.row_input_acquisition_target(
    acquisition,
  )
  [resource, ..columns]
}

///|
#export_name("clientProgramWholeSourceRequestWire")
pub fn client_program_whole_source_request_wire(
  acquisition : @client_row_source_host.RowInputAcquisition,
) -> Result[String, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.row_input_acquisition_request_wire(acquisition)
}

///|
#export_name("clientProgramPrepareInstalledManagedWholeSourcePlan")
pub fn client_program_prepare_installed_managed_whole_source_plan(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  capacity : @client_local_host.ClientInstalledWholeSourceCapacity,
  transfer : Int64,
  scratch : Int64,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
  retained_output : Bool,
) -> Result[
  @client_local_host.ClientInstalledManagedCapturePlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_managed_whole_source_plan(
    prepared,
    request,
    capacity,
    transfer,
    scratch,
    contracts,
    values,
    fragment,
    ordered,
    retained_output~,
    provider_factory=installed_client_family_providers,
  )
}

///|
/// The caller forwards the SAME opaque Option from the existing pre-module
/// invocation getter. Core checks all originals; no JS tuple is constructed.
#export_name("clientProgramPrepareInstalledManagedWholeSourcePlanAtQueryTime")
pub fn client_program_prepare_installed_managed_whole_source_plan_at_query_time(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  capacity : @client_local_host.ClientInstalledWholeSourceCapacity,
  transfer : Int64,
  scratch : Int64,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
  retained_output : Bool,
  invocation : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
    @publication_host.ClientCompiledRun,
    @publication.PublicationContract,
  )?,
) -> Result[
  @client_local_host.ClientInstalledManagedCapturePlan,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepare_installed_managed_whole_source_plan_at_query_time(
    prepared,
    request,
    capacity,
    transfer,
    scratch,
    contracts,
    values,
    fragment,
    ordered,
    invocation,
    retained_output~,
    provider_factory=installed_client_family_providers,
  )
}

///|
#export_name("clientProgramInstalledManagedWholeSourceRead")
pub fn client_program_installed_managed_whole_source_read(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  declaration : @client_row_source_host.RowDeclaration,
) -> Result[
  (
    @client_local_host.ClientInstalledSourceRead,
    @acquisition.SourceAcquisition,
    @client_row_source_host.RowInputAcquisition,
    @client_local_host.ClientInstalledWholeSourceCapacity,
  ),
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_installed_managed_whole_source_read(
    owner, prepared, request, declaration,
  )
}

///|
#export_name("clientProgramPreparedInstalledWholeSourceRequirements")
pub fn client_program_prepared_installed_whole_source_requirements(
  plan : @client_local_host.ClientInstalledManagedCapturePlan,
) -> Array[Int64] {
  @client_local_host.prepared_installed_managed_capture_requirements(plan)
}

///|
/// Open Compute from the same adopted Plan and its original live captures.
/// The existing Run retains the DAG before any later configuration failure.
#export_name("clientProgramOpenInstalledManagedCaptureHost")
pub fn client_program_open_installed_managed_capture_host(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  sources : Array[@query.CapturedInputSource],
) -> Result[
  @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  @client_local_host.ClientInstalledCaptureHostIssue,
] {
  @client_local_host.open_installed_managed_capture_host(
    owner, prepared, request, sources,
  ).map(value => value.0)
}

///|
#export_name("clientProgramOpenInstalledManagedKeyedCaptureHost")
pub fn client_program_open_installed_managed_keyed_capture_host(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  lookup : @publication_host.ClientKeyedLookupInput,
) -> Result[
  @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  @client_local_host.ClientInstalledCaptureHostIssue,
] {
  @client_local_host.open_installed_managed_keyed_capture_host(
    owner, prepared, request, lookup,
  ).map(value => value.0)
}

///|
#export_name("clientProgramInstalledWholeSourceReadStartRows")
pub fn client_program_installed_whole_source_read_start_rows(
  read : @client_local_host.ClientInstalledSourceRead,
  acquisition : @client_row_source_host.RowInputAcquisition,
  nonce : String,
  stop : (@client_row_source_host.RowAttempt) -> Bool,
  transfer : Int64,
  scratch : Int64,
) -> Result[
  @client_row_source_host.RowRun,
  @client_local_host.ClientInstalledSourceReadIssue,
] {
  @client_local_host.start_installed_whole_source_read_rows(
    read, acquisition, nonce, stop, transfer, scratch,
  )
}

///|
#export_name("clientProgramWholeSourceBorrowResponses")
pub fn client_program_whole_source_borrow_responses(
  run : @client_row_source_host.RowRun,
  acquisition : @client_row_source_host.RowInputAcquisition,
) -> Result[
  @client_row_source_host.RowRunResponseBorrow,
  @client_row_source_host.RowHostIssue,
] {
  @client_row_source_host.borrow_row_input_run_responses(run, acquisition)
}

///|
#export_name("clientProgramIssueWholeSourceInputLogical")
pub fn client_program_issue_whole_source_input_logical(
  prepared : @publication_host.PreparedClientProgram,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  capacity : @client_local_host.ClientInstalledWholeSourceCapacity,
) -> Result[
  @publication.RunEvidenceValue,
  @publication_host.ClientCapturedSourceLogicalIssue,
] {
  @publication_host.issue_captured_whole_source_input_logical(
    @publication_host.prepared_client_graph(prepared),
    source,
    identity,
    @client_local_host.installed_whole_source_original(capacity),
  )
}

///|
#export_name("clientProgramWholeSourceIssueSourceEvidenceOriginal")
pub fn client_program_whole_source_issue_source_evidence(
  acquisition : @client_row_source_host.RowInputAcquisition,
  capture : @client_row_source_host.RowSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
  logical : @publication.RunEvidenceValue,
  scope : String,
  policy : String,
  observed : String,
) -> Result[@publication.RunEvidenceValue, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.issue_row_input_source_evidence(
    acquisition, capture, identity, logical, scope, policy, observed,
  )
}

///|
#export_name("clientProgramWholeSourceIssueSourceEvidence")
pub fn client_program_whole_source_issue_source_evidence_wire(
  acquisition : @client_row_source_host.RowInputAcquisition,
  capture : @client_row_source_host.RowSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
  logical : @publication.RunEvidenceValue,
  scope : String,
  policy : String,
  observed : String,
) -> Result[String, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.issue_row_input_source_evidence(
    acquisition, capture, identity, logical, scope, policy, observed,
  ).map(value => @publication.run_evidence_value_json(value))
}

///|
#export_name("clientProgramEffectDirectSourceCoordinates")
pub fn client_program_effect_direct_source_coordinates(
  prepared : @publication_host.PreparedClientEffectComputation,
) -> Result[
  Array[Array[Int]],
  @publication_host.ClientDirectAcquisitionOccurrenceIssue,
] {
  @publication_host.select_client_effect_direct_acquisition_occurrences(
    prepared, 1000000,
  ).map(value => {
    Array::makei(
      @publication_host.client_direct_acquisition_occurrence_count(value),
      slot => {
        let (stage, input, task) = @publication_host.client_direct_acquisition_occurrence_at(
          value, slot,
        ).unwrap()
        [stage, input, slot, task]
      },
    )
  })
}

///|
#export_name("clientProgramEffectWholeSourceInputIdentity")
pub fn client_program_effect_whole_source_input_identity(
  prepared : @publication_host.PreparedClientEffectComputation,
  original : @acquisition.SourceAcquisition,
) -> Array[String]? {
  let source = @acquisition.mode_input(
    @acquisition.source_acquisition_mode(original),
  )
  let stage = @acquisition.declaration(source).stage_index
  if !@publication_host.client_source_acquisition_matches_effect_program(
      prepared,
      stage,
      @acquisition.source_acquisition_source_index(original),
      original,
    ) {
    return None
  }
  let identity = @publication_host.prepared_client_effect_identity(prepared)
  Some([identity.program_definition_cid, identity.parameter_values_cid])
}

///|
#export_name("clientProgramInstalledEffectManagedPlanWholeSource")
pub fn client_program_installed_effect_managed_plan_whole_source(
  plan : @client_local_host.ClientInstalledEffectManagedPlan,
  occurrence : Int,
) -> Result[
  (
    @acquisition.SourceAcquisition,
    @client_row_source_host.RowInputAcquisition,
    @client_local_host.ClientInstalledWholeSourceCapacity,
  ),
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.prepared_installed_effect_managed_whole_source(
    plan, occurrence,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedSourceInputKind")
pub fn client_program_installed_effect_managed_source_input_kind(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  occurrence : Int,
) -> Result[String, @client_local_host.ClientInstalledManagedRunIssue] {
  @client_local_host.installed_effect_managed_source_input_kind(
    owner, prepared, request, occurrence,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedWholeSourceRead")
pub fn client_program_installed_effect_managed_whole_source_read(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  declaration : @client_row_source_host.RowDeclaration,
  occurrence : Int,
) -> Result[
  (
    @client_local_host.ClientInstalledSourceRead,
    @acquisition.SourceAcquisition,
    @client_row_source_host.RowInputAcquisition,
    @client_local_host.ClientInstalledWholeSourceCapacity,
  ),
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_installed_effect_managed_whole_source_read(
    owner, prepared, request, declaration, occurrence,
  )
}

///|
#export_name("clientProgramInstalledEffectManagedSourcesLedger")
pub fn client_program_installed_effect_managed_sources_ledger(
  owner : @client_local_host.ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @resources.Ledger,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.installed_effect_managed_sources_ledger(
    owner, prepared, request,
  )
}

///|
#export_name("clientProgramIssueEffectWholeSourceInputLogical")
pub fn client_program_issue_effect_whole_source_input_logical(
  prepared : @publication_host.PreparedClientEffectComputation,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  capacity : @client_local_host.ClientInstalledWholeSourceCapacity,
) -> Result[
  @publication.RunEvidenceValue,
  @publication_host.ClientCapturedSourceLogicalIssue,
] {
  let original = @client_local_host.installed_whole_source_original(capacity)
  let stage = @acquisition.declaration(
      @acquisition.mode_input(@acquisition.source_acquisition_mode(original)),
    ).stage_index
  let graph = @strategy.checked_effect_computation_graph(
    @publication_host.prepared_client_effect_computation_graph(prepared),
  )
  guard @publication_host.client_source_acquisition_matches_effect_program(
      prepared,
      stage,
      @acquisition.source_acquisition_source_index(original),
      original,
    ) &&
    @strategy.graph_stage_operation_task(graph, stage, 0) is Some(task) else {
    return Err(@publication_host.ForeignPrepared)
  }
  @publication_host.issue_captured_whole_source_input_logical(
    graph,
    source,
    identity,
    original,
    task~,
  )
}

///|
/// Immutable policy DATA from the same installed Source constructor as Pure.
#export_name("clientProgramInstalledRowInputPolicy")
pub fn client_program_installed_row_input_policy(
  max_rows : Int,
  max_page_bytes : Int,
  max_page_nodes : Int,
  max_page_depth : Int,
  max_page_rows : Int,
) -> @client_row_source_host.RowInputLimits {
  @client_local_host.installed_row_input_policy(
    max_rows, max_page_bytes, max_page_nodes, max_page_depth, max_page_rows,
  )
}
