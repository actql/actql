///|
/// JS-only identity erasure for the fixed ordinary producer receipt. An empty
/// record supplied by a caller is not admitted: the original Node supplier
/// checks membership and purpose before returning its one child port.
#external
type ClientLocalPreparationInputOriginal

///|
/// The fixed manager stores this unstarted admission before calling the
/// separate phase driver. A later rejection/unknown outcome must clean this
/// same original and cannot acquire another child for the same receipt.
#export_name("clientProgramPrepareLocalPreparationAdmission")
pub fn client_program_prepare_local_preparation_admission(
  original : @resources.OriginalNodeManagedRunReference,
  input : ClientLocalPreparationInputOriginal,
) -> Result[
  @resources.NodePreparationAdmission[ClientLocalPreparationInputOriginal],
  @resources.ImportedChildLedgerIssue,
] {
  @resources.prepare_node_local_preparation_admission(original, input)
}

///|
/// The original cleanup census refuses while a preparation debit or child
/// duty remains. This operation is not a replacement for phase retirement.
#export_name("clientProgramCleanupLocalPreparationAdmission")
pub fn client_program_cleanup_local_preparation_admission(
  original : @resources.NodePreparationAdmission[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[Unit, @resources.ImportedChildLedgerIssue] {
  @resources.cleanup_node_preparation_admission(original)
}

///|
#export_name("clientProgramClosedValuesInitialControl")
pub fn client_program_closed_values_initial_control(
  policy : @client_local_host.ClientLocalResourcePolicy,
) -> Array[Int64] {
  match
    @client_local_host.client_closed_values_initial_control_capacity(
      policy,
      module_containers=installed_client_module_container_units,
    ) {
    Some((retained, execution)) => [retained, execution]
    None => []
  }
}

///|
#export_name("clientProgramRequestPreparationControl")
pub fn client_program_request_preparation_control(
  policy : @client_local_host.ClientLocalResourcePolicy,
) -> Array[Int64] {
  match @client_local_host.client_request_preparation_control_capacity(policy) {
    Some((retained, execution)) => [retained, execution]
    None => []
  }
}

///|
#export_name("clientProgramBeginRequestPreparation")
pub fn client_program_begin_request_preparation(
  initial : @resources.NodePreparationAdmission[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  policy : @client_local_host.ClientLocalResourcePolicy,
) -> Result[
  @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  @client_local_host.ClientRequestPreparationIssue,
] {
  @client_local_host.begin_request_preparation(initial, input, policy)
}

///|
#export_name("clientProgramReserveRequestSnapshot")
pub fn client_program_reserve_request_snapshot(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  units : Int64,
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.reserve_request_snapshot(parent, input, units)
}

///|
#export_name("clientProgramParseRequestQuerySyntax")
pub fn client_program_parse_request_query_syntax(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  document : String,
  spelling : String,
) -> Result[
  @query_syntax.Query,
  @client_local_host.ClientRequestQuerySyntaxIssue,
] {
  let format = match @source_frontend.select_format(spelling) {
    Err(issue) =>
      return Err(
        @client_local_host.ClientRequestQuerySyntaxIssue::Frontend(issue),
      )
    Ok(value) => value
  }
  @client_local_host.parse_request_query_syntax(parent, input, document, format)
}

///|
#export_name("clientProgramLowerRequestPublishedQuery")
pub fn client_program_lower_request_published_query(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  environment : @program_check.CheckEnvironment,
  declarations : String?,
  public_primary : Bool,
) -> Result[
  (
    @source_frontend.Lowered,
    @program_check.PreparedSourceCatalog,
    @source_frontend.DiagnosticSource,
  ),
  @client_local_host.ClientRequestQueryLoweringIssue,
] {
  @client_local_host.lower_request_published_query(
    parent,
    input,
    publication,
    environment,
    declarations,
    public_primary~,
  )
}

///|
#export_name("clientProgramPreparedRequestQueryLowering")
pub fn client_program_prepared_request_query_lowering(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
) -> Result[
  (
    @source_frontend.Lowered,
    @program_check.PreparedSourceCatalog,
    @source_frontend.DiagnosticSource,
  ),
  @client_local_host.ClientRequestQueryLoweringIssue,
] {
  @client_local_host.prepared_request_query_lowering(parent, input)
}

///|
/// The existing parent retains this exact Source child on the same original input.
#export_name("clientProgramPrepareRequestProgramJson")
pub fn client_program_prepare_request_program_json(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  document : String,
  limits : @stage_syntax.Limits,
) -> Result[
  @client_local_host.ClientProgramJsonPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
  @client_local_host.ClientRequestPreparationIssue,
] {
  @client_local_host.prepare_request_program_json_preparation(
    parent, input, document, limits,
  )
}

///|
#export_name("clientProgramAdvanceProgramJsonPreparation")
pub fn client_program_advance_program_json_preparation(
  owner : @client_local_host.ClientProgramJsonPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
  quantum : Int,
) -> Result[
  @source.JsonSourcePreflightPoll,
  @client_local_host.ClientProgramJsonPreparationIssue,
] {
  @client_local_host.advance_program_json_preparation(owner, quantum)
}

///|
#export_name("clientProgramFinishProgramJsonPreparation")
pub fn client_program_finish_program_json_preparation(
  owner : @client_local_host.ClientProgramJsonPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramJsonPreparationIssue] {
  @client_local_host.finish_program_json_preparation(owner)
}

///|
#export_name("clientProgramConstructProgramJsonPreparation")
pub fn client_program_construct_program_json_preparation(
  owner : @client_local_host.ClientProgramJsonPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramJsonPreparationIssue] {
  @client_local_host.construct_program_json_preparation(owner)
}

///|
#export_name("clientProgramReconcileProgramJsonPreparationStructure")
pub fn client_program_reconcile_program_json_preparation_structure(
  owner : @client_local_host.ClientProgramJsonPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramJsonPreparationIssue] {
  @client_local_host.reconcile_program_json_preparation_structure(owner)
}

///|
/// The parent takes and retains its original Program; no capacity or replacement body escapes.
#export_name("clientProgramPrepareRequestProgramCheck")
pub fn client_program_prepare_request_program_check(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  environment : @program_check.CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : @program_check.CheckLimits,
  source_catalog : @program_check.PreparedSourceCatalog?,
  source_preparation : @stage_parameters.Source?,
) -> Result[
  @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
  @client_local_host.ClientRequestPreparationIssue,
] {
  @client_local_host.prepare_request_program_check_preparation(
    parent,
    input,
    environment,
    supplied,
    evidence,
    limits,
    source_catalog~,
    source_preparation~,
  )
}

///|
#export_name("clientProgramPrepareProgramCheckInput")
pub fn client_program_prepare_program_check_input(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.prepare_program_check_input(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckPrelude")
pub fn client_program_prepare_program_check_prelude(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckPrelude,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_prelude(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckRegistry")
pub fn client_program_prepare_program_check_registry(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckRegistry,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_registry(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckContents")
pub fn client_program_prepare_program_check_contents(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckRegistry,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_contents(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckReferences")
pub fn client_program_prepare_program_check_references(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckRegistry,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_references(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckPolicies")
pub fn client_program_prepare_program_check_policies(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckRegistry,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_policies(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckValues")
pub fn client_program_prepare_program_check_values(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckRegistry,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_values(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckViews")
pub fn client_program_prepare_program_check_views(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckRegistry,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_views(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckCarriers")
pub fn client_program_prepare_program_check_carriers(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckRegistry,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_carriers(owner)
}

///|
#export_name("clientProgramPrepareProgramCheckRequests")
pub fn client_program_prepare_program_check_requests(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[
  @program_check.ParsedCheckRegistry,
  @client_local_host.ClientProgramCheckPreparationIssue,
] {
  @client_local_host.prepare_program_check_requests(owner)
}

///|
#export_name("clientProgramReconcileProgramCheckRegistry")
pub fn client_program_reconcile_program_check_registry(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.reconcile_program_check_registry(owner)
}

///|
#export_name("clientProgramReconcileProgramCheckContents")
pub fn client_program_reconcile_program_check_contents(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.reconcile_program_check_contents(owner)
}

///|
#export_name("clientProgramReconcileProgramCheckReferences")
pub fn client_program_reconcile_program_check_references(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.reconcile_program_check_references(owner)
}

///|
#export_name("clientProgramReconcileProgramCheckPolicies")
pub fn client_program_reconcile_program_check_policies(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.reconcile_program_check_policies(owner)
}

///|
#export_name("clientProgramReconcileProgramCheckValues")
pub fn client_program_reconcile_program_check_values(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.reconcile_program_check_values(owner)
}

///|
#export_name("clientProgramReconcileProgramCheckViews")
pub fn client_program_reconcile_program_check_views(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.reconcile_program_check_views(owner)
}

///|
#export_name("clientProgramReconcileProgramCheckCarriers")
pub fn client_program_reconcile_program_check_carriers(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.reconcile_program_check_carriers(owner)
}

///|
#export_name("clientProgramReconcileProgramCheckRequests")
pub fn client_program_reconcile_program_check_requests(
  owner : @client_local_host.ClientProgramCheckPreparation[
    ClientLocalPreparationInputOriginal,
    Unit,
  ],
) -> Result[Unit, @client_local_host.ClientProgramCheckPreparationIssue] {
  @client_local_host.reconcile_program_check_requests(owner)
}

///|
#export_name("clientProgramSelectClosedValuesPreparation")
pub fn client_program_select_closed_values_preparation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
) -> Result[
  @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  @client_local_host.ClientRequestPreparationIssue,
] {
  @client_local_host.select_closed_values_preparation(
    parent,
    input,
    module_containers=installed_client_module_container_units,
  )
}

///|
#export_name("clientProgramAbortRequestPreparation")
pub fn client_program_abort_request_preparation(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[Unit, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.abort_request_preparation_after_cleanup(parent)
}

///|
#export_name("clientProgramBeginClosedValuesHeader")
pub fn client_program_begin_closed_values_header(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[
  @resources.PreparationPhaseWork,
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.begin_closed_values_header(owner)
}

///|
#export_name("clientProgramBeginClosedValuesScan")
pub fn client_program_begin_closed_values_scan(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  fields : Int,
  rows : Int,
) -> Result[
  @resources.PreparationPhaseWork,
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.begin_closed_values_scan(owner, fields, rows)
}

///|
#export_name("clientProgramSpendPreparationPhaseWork")
pub fn client_program_spend_preparation_phase_work(
  work : @resources.PreparationPhaseWork,
  amount : Int,
) -> Result[Unit, @resources.PreparationWorkIssue] {
  @resources.spend_preparation_phase_work(work, amount)
}

///|
#export_name("clientProgramFinishClosedValuesScan")
pub fn client_program_finish_closed_values_scan(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[Unit, @client_local_host.ClientClosedValuesPreparationIssue] {
  @client_local_host.finish_closed_values_scan(owner)
}

///|
#export_name("clientProgramAbortClosedValuesPreparationAfterCleanup")
pub fn client_program_abort_closed_values_preparation_after_cleanup(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[Unit, @client_local_host.ClientClosedValuesPreparationIssue] {
  @client_local_host.abort_closed_values_preparation_after_cleanup(owner)
}

///|
#export_name("clientProgramBeginClosedValuesTextCheck")
pub fn client_program_begin_closed_values_text_check(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  quoted_utf16_units : Int,
) -> Result[
  @resources.PreparationPhaseWork,
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.begin_closed_values_text_check(owner, quoted_utf16_units)
}

///|
#export_name("clientProgramFinishClosedValuesTextCheck")
pub fn client_program_finish_closed_values_text_check(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[Unit, @client_local_host.ClientClosedValuesPreparationIssue] {
  @client_local_host.finish_closed_values_text_check(owner)
}

///|
/// Private fixed Node scanner projection. The original phase owner, not these
/// numeric facts, owns capacity; JavaScript proves same-input synchronous
/// custody before this call. No caller resource budget is accepted here.
#export_name("clientProgramReserveClosedValuesSnapshot")
pub fn client_program_reserve_closed_values_snapshot(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input_bytes_upper : Int,
  node_upper : Int,
  objects : Int,
  arrays : Int,
  fields_upper : Int,
  quoted_tokens : Int,
  quoted_utf16_units : Int,
  longest_quoted_utf16 : Int,
  longest_atom_utf16 : Int,
  depth_upper : Int,
  fields : Int,
  rows : Int,
  consent_refs : Int,
) -> Result[Unit, @client_local_host.ClientClosedValuesPreparationIssue] {
  @client_local_host.reserve_closed_values_snapshot(
    owner,
    {
      input_bytes_upper,
      node_upper,
      objects,
      arrays,
      fields_upper,
      quoted_tokens,
      quoted_utf16_units,
      longest_quoted_utf16,
      longest_atom_utf16,
      depth_upper,
      fields,
      rows,
    },
    consent_refs,
  )
}

///|
#export_name("clientProgramBindClosedValuesDocument")
pub fn client_program_bind_closed_values_document(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  document : String,
) -> Result[Unit, @client_local_host.ClientClosedValuesPreparationIssue] {
  @client_local_host.bind_closed_values_document(owner, document)
}

///|
#export_name("clientProgramPrepareClosedValuesModuleBody")
pub fn client_program_prepare_closed_values_module_body(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  environment : @program_check.CheckEnvironment,
  publication_environment : @source_publication.PreparedPublishedQueryEnvironment,
  contracts : @client_local_host.ClientInstalledSequenceContracts,
  retained_output : Bool,
) -> Result[Unit, @client_local_host.ClientClosedValuesPreparationIssue] {
  // Cold compiler admission belongs to installed initialization, never to a
  // query borrowing an original under a per-request compilation quotation.
  guard client_generated_manifest_admission.val is Some(Ok(manifests)) else {
    return Err(Policy)
  }
  @client_local_host.prepare_closed_values_module_body(
    owner,
    environment,
    publication_environment,
    contracts,
    manifests,
    retained_output~,
    provider_factory=installed_client_family_providers,
    family_retained=installed_client_family_construction_retained,
    family_array=installed_client_family_construction_array,
    family_temporary=installed_client_family_construction_temporary,
  )
}

///|
#export_name("clientProgramCompleteClosedValuesBody")
pub fn client_program_complete_closed_values_body(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.complete_closed_values_body(owner)
}

///|
#export_name("clientProgramAdoptClosedValuesPreparation")
pub fn client_program_adopt_closed_values_preparation(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Result[
  @client_local_host.ClientInstalledManagedRun,
  @client_local_host.ClientInstalledManagedRunIssue,
] {
  @client_local_host.begin_closed_values_owned_run(owner, prepared, request)
}

///|
#export_name("clientProgramSeverClosedValuesBody")
pub fn client_program_sever_closed_values_body(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ],
) -> Bool {
  @client_local_host.sever_closed_values_body(owner, holder)
}

///|
/// Exact initial-owner/issued-manager-token cut witness. Not physical stop.
#export_name("clientProgramClosedValuesInitialRetirementStarted")
pub fn client_program_closed_values_initial_retirement_started(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ],
) -> Bool {
  @client_local_host.closed_values_initial_retirement_started(owner, holder)
}

///|
/// Read-only logical accounting for the exact original owner. No grant.
#export_name("clientProgramClosedValuesPreparationAccounting")
pub fn client_program_closed_values_preparation_accounting(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
) -> Result[
  (Int64, Int64, Int64, Int64, Int64, Int64),
  @client_local_host.ClientClosedValuesPreparationIssue,
] {
  @client_local_host.closed_values_preparation_accounting(owner)
}

///|
/// Immutable failure DATA only; no owner, Ledger, reservation or grant escapes.
#export_name("clientProgramPreparationCapacityRefusal")
pub fn client_program_preparation_capacity_refusal(
  issue : @client_local_host.ClientClosedValuesPreparationIssue,
) -> (String, String, Int64, Int64, Int64, Int64)? {
  @client_local_host.closed_values_preparation_capacity_refusal(issue)
}

///|
/// Fixed original-owner intent admission; no caller numeric limit or grant.
#export_name("clientProgramPrepareClosedValuesSubmittedIntent")
pub fn client_program_prepare_closed_values_submitted_intent(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  wire : String,
) -> Result[String, @client_local_host.ClientClosedValuesPreparationIssue] {
  @client_local_host.prepare_closed_values_submitted_intent(owner, wire)
}

///|
/// Borrowed exact semantic intent; fixed active handler lifetime only.
#export_name("clientProgramClosedValuesSubmittedIntentOriginal")
pub fn client_program_closed_values_submitted_intent_original(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
) -> @publication_host.ClientSubmittedIntent? {
  @client_local_host.closed_values_submitted_intent_original(owner)
}

///|
#export_name("clientProgramClosedValuesCompilationOriginal")
pub fn client_program_closed_values_compilation_original(
  owner : @client_local_host.ClientClosedValuesPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  prepared : @publication_host.PreparedClientProgram,
) -> @publication_host.ClientValuesCompilation? {
  @client_local_host.closed_values_compilation_original(owner, prepared)
}

///|
#export_name("strategyCapturedRunPreparationLimits")
pub fn strategy_captured_run_preparation_limits(
  original : @publication.CapturedRunIssuancePreparation,
) -> Array[Int]? {
  @publication.captured_run_preparation_limits(original).map(values => {
    [values.0, values.1, values.2]
  })
}

///|
#export_name("strategyBeginOriginalEffectFreeCapturedRun")
pub fn strategy_begin_original_effect_free_captured_run(
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  snapshots : Array[@publication.CapturedResultSnapshot],
  advances : Array[@publication.PendingSourceStateAdvance],
  authoring : @publication.RunEvidenceValue,
  models : Array[@publication.RunEvidenceValue],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
  content_generations : Array[@publication.BoundContentGeneration],
) -> @publication.CapturedRunIssuancePreparation {
  @publication.start_original_effect_free_captured_run(
    run_definition,
    invocation,
    definitions,
    artifacts,
    manifest,
    receipt,
    snapshots,
    advances,
    authoring,
    models,
    max_wire_bytes,
    max_nodes,
    max_depth,
    max_workspace,
    content_generations~,
  )
}
