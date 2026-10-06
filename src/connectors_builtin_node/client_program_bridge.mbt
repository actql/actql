///|
/// Internal JS bridge. The environment is an admitted machine-contract value,
/// and its selected pure-operation profiles are supplied by the installed
/// Host. None of these handles is a wire credential or execution authority.
#export_name("clientProgramCheckEnvironment")
pub fn client_program_check_environment(
  body : String,
  evidence_bundle_cid : String,
  text_time : Bool,
  veca : Bool,
  rela : Bool,
  sga : Bool,
  tea : Bool,
  calendar : Bool,
  text_rank : Bool,
) -> @program_check.CheckEnvironment? {
  if sga && !selected_sga_supported() {
    return None
  }
  @publication_host.admit_client_check_environment(
    body,
    evidence_bundle_cid,
    { text_time, veca, },
    { rela, sga, tea, calendar, text_rank, },
  )
}

///|
/// The installed Host opts into the exact pinned numeric profile before
/// checking a Program. An unknown CID cannot silently choose an algorithm.
#export_name("clientProgramCheckEnvironmentWithNumericProfile")
pub fn client_program_check_environment_with_numeric_profile(
  body : String,
  evidence_bundle_cid : String,
  text_time : Bool,
  veca : Bool,
  rela : Bool,
  sga : Bool,
  tea : Bool,
  calendar : Bool,
  text_rank : Bool,
  numeric_profile_cid : String,
) -> @program_check.CheckEnvironment? {
  if sga && !selected_sga_supported() {
    return None
  }
  @publication_host.admit_client_check_environment(
    body,
    evidence_bundle_cid,
    { text_time, veca, },
    { rela, sga, tea, calendar, text_rank, },
    numeric_profile_cid=Some(numeric_profile_cid),
  )
}

///|
/// Explicit installed capability for the separately identified Graph
/// subset. Existing bridge entries and their legacy SGA flag remain unchanged.
/// A law pin selects semantics, not execution authorization.
#export_name("clientProgramCheckEnvironmentWithGraphProfile")
pub fn client_program_check_environment_with_graph_profile(
  body : String,
  evidence_bundle_cid : String,
  text_time : Bool,
  veca : Bool,
  rela : Bool,
  sga : Bool,
  tea : Bool,
  calendar : Bool,
  text_rank : Bool,
  numeric_profile_cid : String,
  graph_law_cid : String,
) -> @program_check.CheckEnvironment? {
  if !selected_graph_supported() ||
    graph_law_cid != @graph_contract.law_cid() ||
    (sga && !selected_sga_supported()) {
    return None
  }
  @publication_host.admit_client_check_environment(
    body,
    evidence_bundle_cid,
    { text_time, veca, },
    { rela, sga, tea, calendar, text_rank, },
    numeric_profile_cid=Some(numeric_profile_cid),
    graph=true,
  )
}

///|
/// Preserve the shared checker's typed failure across the in-process Host bridge.
/// A wire adapter may project it to a public error, but must not recheck the
/// Program or infer missing inputs from an absent prepared handle.
pub(all) enum ClientProgramBridgeIssue {
  InvalidFormat
  SuppliedSyntax(@source.ParseError)
  SuppliedAdmission(@decode.Issue)
  Preparation(@publication_host.ClientProgramPreparationIssue)
  SourcePreparation(ClientSourcePreparationIssue)
}

///|
pub(all) enum ClientProgramBridgeOutcome {
  Prepared(@publication_host.PreparedClientProgram)
  Rejected(ClientProgramBridgeIssue)
}

///|
/// Explicit JSON or YAML only. Supplied Parameter Values are a separately
/// bounded JSON body; they never modify the checked Program document.
#export_name("clientProgramPrepareEffectFreeWithParameters")
pub fn client_program_prepare_effect_free_with_parameters(
  document : String,
  format : String,
  environment : @program_check.CheckEnvironment,
  parameters : String?,
) -> ClientProgramBridgeOutcome {
  let (selected, supplied) = match client_program_input(format, parameters) {
    Ok(value) => value
    Err(issue) => return Rejected(issue)
  }
  match
    @publication_host.prepare_effect_free_client_program(
      document,
      selected,
      environment,
      supplied,
      client_program_standard_limits(),
    ) {
    Ok(value) => Prepared(value)
    Err(issue) => Rejected(Preparation(issue))
  }
}

///|
#export_name("clientProgramPreparationReady")
pub fn client_program_preparation_ready(
  outcome : ClientProgramBridgeOutcome,
) -> @publication_host.PreparedClientProgram? {
  match outcome {
    Prepared(value) => Some(value)
    Rejected(_) => None
  }
}

///|
#export_name("clientProgramPreparationIssue")
pub fn client_program_preparation_issue(
  outcome : ClientProgramBridgeOutcome,
) -> ClientProgramBridgeIssue? {
  match outcome {
    Prepared(_) => None
    Rejected(issue) => Some(issue)
  }
}

///|
#export_name("clientProgramPreparationIssueCode")
pub fn client_program_preparation_issue_code(
  outcome : ClientProgramBridgeOutcome,
) -> String? {
  match outcome {
    Prepared(_) => None
    Rejected(issue) =>
      Some(
        match issue {
          InvalidFormat => "invalid_format"
          SourcePreparation(issue) =>
            client_source_preparation_issue_code(issue)
          SuppliedSyntax(error) =>
            match error.issue {
              @source.InputLimit | @source.NodeLimit | @source.DepthLimit =>
                "supplied_too_large"
              _ => "supplied_syntax"
            }
          SuppliedAdmission(error) =>
            match error.kind {
              @decode.BudgetExceeded => "supplied_too_large"
              _ => "supplied_admission"
            }
          Preparation(owner) =>
            match owner {
              Syntax(_) => "program_syntax"
              EffectNotSupported(_) => "effect_not_supported"
              NeedsInputs(_) => "needs_inputs"
              Check(diagnostic) =>
                match @program_check.diagnostic_category(diagnostic) {
                  @program_check.InvalidInput => "check_invalid_input"
                  @program_check.InvalidConfiguration =>
                    "check_invalid_configuration"
                  @program_check.UnsupportedImplementation =>
                    "check_unsupported"
                  @program_check.CompileLimit => "check_compile_limit"
                  @program_check.MissingInput => "check_missing_input"
                  @program_check.UnclassifiedFailure => "check_unclassified"
                }
              MissingCheckedStage(_) => "missing_checked_stage"
              MissingStageIdentity(_) => "missing_stage_identity"
              Lowering(_) => "lowering_rejected"
              Binding(_) => "binding_rejected"
              Graph(_) => "graph_rejected"
            }
        },
      )
  }
}

///|
/// Retain the original no-Parameter convenience bridge entry for existing installed
/// hosts. New submit paths must use the typed preparation entry above.
#export_name("clientProgramPrepareEffectFree")
pub fn client_program_prepare_effect_free(
  document : String,
  format : String,
  environment : @program_check.CheckEnvironment,
) -> @publication_host.PreparedClientProgram? {
  client_program_preparation_ready(
    client_program_prepare_effect_free_with_parameters(
      document,
      format,
      environment,
      None,
    ),
  )
}

///|
#export_name("clientProgramResultCount")
pub fn client_program_result_count(
  prepared : @publication_host.PreparedClientProgram,
) -> Int {
  @publication_host.prepared_client_result_count(prepared)
}

///|
#export_name("clientProgramTaskCount")
pub fn client_program_task_count(
  prepared : @publication_host.PreparedClientProgram,
) -> Int {
  @strategy.graph_task_count(@publication_host.prepared_client_graph(prepared))
}

///|
#export_name("clientProgramUsesGraphCarrier")
pub fn client_program_uses_graph_carrier(
  prepared : @publication_host.PreparedClientProgram,
) -> Bool {
  @publication_host.prepared_client_uses_graph_carrier(prepared)
}

///|
#export_name("clientProgramSemanticsCid")
pub fn client_program_semantics_cid(
  prepared : @publication_host.PreparedClientProgram,
) -> String {
  @publication_host.prepared_client_program_semantics_cid(prepared)
}

///|
#export_name("clientProgramCheckEnvironmentCid")
pub fn client_program_check_environment_cid(
  prepared : @publication_host.PreparedClientProgram,
) -> String {
  @publication_host.prepared_client_check_environment_cid(prepared)
}

///|
/// Bind publication admission to the same opaque checked Program that the
/// Host will execute. The returned handle is in-process authority, never a
/// Client wire value.
#export_name("clientProgramAdmitPublication")
pub fn client_program_admit_publication(
  prepared : @publication_host.PreparedClientProgram,
  template : @publication.RunEvidenceValue,
  invocation : @publication.RunEvidenceValue,
  authorization : @publication.RunEvidenceValue,
  plan : @publication.PublicationContract,
) -> @publication.RunPublicationAdmission? {
  match
    @publication_host.admit_prepared_client_run_publication(
      prepared, template, invocation, authorization, plan,
    ) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
/// The normal Node Host checks the exact issued Definition before writing
/// the request journal. Two individually valid Runs cannot be interchanged.
#export_name("clientProgramCheckRunBinding")
pub fn client_program_check_run_binding(
  prepared : @publication_host.PreparedClientProgram,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
) -> Bool {
  let identity = @publication_host.prepared_client_identity(prepared)
  @publication.check_run_publication_program_binding(
    admission,
    definition,
    identity.program_definition_cid,
    @publication_host.prepared_client_program_semantics_cid(prepared),
    @publication_host.prepared_client_check_environment_cid(prepared),
  )
  is Ok(_)
}

///|
#export_name("clientProgramResultName")
pub fn client_program_result_name(
  prepared : @publication_host.PreparedClientProgram,
  index : Int,
) -> String? {
  @publication_host.prepared_client_result_name(prepared, index)
}

///|
#export_name("clientProgramRequestIdentity")
pub fn client_program_request_identity(
  prepared : @publication_host.PreparedClientProgram,
  authority_scope_cid : String,
  caller_request_id : String,
  caller_input_intent_cid : String,
) -> @publication_host.ClientRequestIdentity? {
  match
    @publication_host.prepare_client_request_identity(
      prepared, authority_scope_cid, caller_request_id, caller_input_intent_cid,
    ) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
#export_name("clientProgramSourceFreeInputIntentCid")
pub fn client_program_source_free_input_intent_cid() -> String {
  @publication_host.source_free_caller_input_intent_cid()
}

///|
/// The installed Host reports an uncommitted Run through the portable
/// validator. Only a durable confirmed failure before physical dispatch may
/// make this projection terminal; missing worker observation cannot.
#export_name("clientProgramIssueUnpublishedRunState")
pub fn client_program_issue_unpublished_run_state(
  run_id : String,
  observed_at : String,
  result_names : Array[String],
  dispatch_reserved : Bool,
  pre_dispatch_failure_confirmed : Bool,
) -> String? {
  match
    @publication.issue_effect_free_unpublished_run_state_wire(
      run_id, observed_at, result_names, dispatch_reserved, pre_dispatch_failure_confirmed,
      100000, 10000, 64,
    ) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
/// The installed Host reports an uncommitted Run through the portable
/// validator. A missing live owner after a physical-start claim is unknown,
/// not a confirmed failure or permission to start again.
pub(all) suberror ClientProgramRunStateIssue {
  InvalidTerminalOutcome
  Projection(@publication.RunStateIssue)
}

///|
#export_name("clientProgramIssueControlledUnpublishedRunState")
pub fn client_program_issue_controlled_unpublished_run_state(
  run_id : String,
  observed_at : String,
  result_names : Array[String],
  dispatch_reserved : Bool,
  pre_dispatch_failure_confirmed : Bool,
  cancelled_before_start : Bool,
  observed_terminal_outcome : String,
  execution_unknown : Bool,
) -> String raise ClientProgramRunStateIssue {
  let terminal = match observed_terminal_outcome {
    "none" => None
    "failed" => Some(@publication.RunOutcomeStatus::Failed)
    "cancelled" => Some(@publication.RunOutcomeStatus::Cancelled)
    _ => raise InvalidTerminalOutcome
  }
  match
    @publication.issue_effect_free_unpublished_run_state_wire(
      run_id,
      observed_at,
      result_names,
      dispatch_reserved,
      pre_dispatch_failure_confirmed,
      100000,
      10000,
      64,
      cancelled_before_start~,
      observed_terminal_outcome=terminal,
      execution_unknown~,
    ) {
    Ok(value) => value
    Err(issue) => raise Projection(issue)
  }
}

///|
#export_name("clientRunControlObservation")
pub fn client_run_control_observation(
  revision : Int,
  cancellation_requested : Bool,
  physically_unstarted : Bool,
  pre_dispatch_failure_confirmed : Bool,
  physical_close_confirmed : Bool,
) -> String raise ClientProgramRunStateIssue {
  match
    @publication.issue_run_control_observation_wire(
      revision, cancellation_requested, physically_unstarted, pre_dispatch_failure_confirmed,
      physical_close_confirmed,
    ) {
    Ok(value) => value
    Err(issue) => raise Projection(issue)
  }
}

///|
#export_name("clientProgramIssueValuesCompiledRun")
pub fn client_program_issue_values_compiled_run(
  prepared : @publication_host.PreparedClientProgram,
  compilation : @publication_host.ClientValuesCompilation,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
) -> Result[
  @publication_host.ClientCompiledRun,
  @publication_host.ClientCompiledRunIssue,
] {
  @publication_host.issue_client_values_compiled_run(
    prepared, compilation, execution_context_cid, host_policy_cid, expires_at,
  )
}

///|
#export_name("clientProgramIssueTaskCompiledRun")
pub fn client_program_issue_task_compiled_run(
  prepared : @publication_host.PreparedClientProgram,
  compilation : @publication_host.ClientTaskCompilation,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
) -> Result[
  @publication_host.ClientCompiledRun,
  @publication_host.ClientCompiledRunIssue,
] {
  @publication_host.issue_client_task_compiled_run(
    prepared, compilation, execution_context_cid, host_policy_cid, expires_at,
  )
}

///|
#export_name("clientProgramCompiledRunTemplate")
pub fn client_program_compiled_run_template(
  value : @publication_host.ClientCompiledRun,
) -> @publication.RunEvidenceValue {
  @publication_host.client_compiled_run_template(value)
}

///|
#export_name("clientProgramCompiledRunResultTransformation")
pub fn client_program_compiled_run_result_transformation(
  value : @publication_host.ClientCompiledRun,
  prepared : @publication_host.PreparedClientProgram,
  result : Int,
) -> Result[
  @publication_host.ClientResultTransformation?,
  @publication_host.ClientCompiledRunIssue,
] {
  @publication_host.client_compiled_run_result_transformation(
    value, prepared, result,
  )
}

///|
#export_name("clientProgramCompiledRunPlan")
pub fn client_program_compiled_run_plan(
  value : @publication_host.ClientCompiledRun,
) -> @publication.PublicationContract {
  @publication_host.client_compiled_run_plan(value)
}

///|
#export_name("clientProgramCompiledRunPrepared")
pub fn client_program_compiled_run_prepared(
  value : @publication_host.ClientCompiledRun,
) -> @publication.RunEvidenceValue {
  @publication_host.client_compiled_run_prepared(value)
}

///|
#export_name("clientProgramCompiledRunAuthorization")
pub fn client_program_compiled_run_authorization(
  value : @publication_host.ClientCompiledRun,
) -> @publication.RunEvidenceValue {
  @publication_host.client_compiled_run_authorization(value)
}

///|
#export_name("clientProgramCompiledRunAdmission")
pub fn client_program_compiled_run_admission(
  value : @publication_host.ClientCompiledRun,
) -> @publication.RunPublicationAdmission {
  @publication_host.client_compiled_run_admission(value)
}

///|
#export_name("clientProgramIssueCompiledRunDefinition")
pub fn client_program_issue_compiled_run_definition(
  value : @publication_host.ClientCompiledRun,
  scope_id : String,
  run_id : String,
  created_at : String,
  valid_until : String,
) -> Result[
  @publication.PublicationContract,
  @publication_host.ClientCompiledRunIssue,
] {
  @publication_host.issue_client_compiled_run_definition(
    value, scope_id, run_id, created_at, valid_until,
  )
}

///|
#export_name("clientProgramAdmitCompiledRunDefinition")
pub fn client_program_admit_compiled_run_definition(
  value : @publication_host.ClientCompiledRun,
  wire : String,
) -> Result[
  @publication.PublicationContract,
  @publication_host.ClientCompiledRunIssue,
] {
  @publication_host.admit_client_compiled_run_definition(value, wire)
}

///|
#export_name("clientProgramIssueCompiledValuesInvocation")
pub fn client_program_issue_compiled_values_invocation(
  value : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  @publication_host.issue_client_compiled_values_invocation(
    value, definition, data_policy_cid, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramIssueCompiledSourceFreeTaskInvocation")
pub fn client_program_issue_compiled_source_free_task_invocation(
  value : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  @publication_host.issue_client_compiled_source_free_task_invocation(
    value, definition, data_policy_cid, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramIssueCompiledTaskInvocation")
pub fn client_program_issue_compiled_task_invocation(
  value : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  source_evidence_wire : String,
  input_logical_wire : String,
  source_ref : String,
  source_contract_cid : String,
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  @publication_host.issue_client_compiled_task_invocation(
    value, definition, source_evidence_wire, input_logical_wire, source_ref, source_contract_cid,
    authority_scope_cid, data_policy_cid, capture_started_at, capture_completed_at,
    max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramDefinitionCid")
pub fn client_program_definition_cid(
  prepared : @publication_host.PreparedClientProgram,
) -> String {
  @publication_host.prepared_client_identity(prepared).program_definition_cid
}

///|
#export_name("clientProgramCompiledRunMatches")
pub fn client_program_compiled_run_matches(
  value : @publication_host.ClientCompiledRun,
  prepared : @publication_host.PreparedClientProgram,
) -> Bool {
  @publication_host.client_compiled_run_matches(value, prepared)
}

///|
/// The installed Local profile applies one bounded sequence definition to
/// compiler material and the task that physically executes it.
fn client_local_sequence_limits() -> @lower.SequenceLimits {
  @publication_host.client_standard_values_sequence_limits()
}

///|
/// Private Plan material from the checked parser, without authoring metadata.
#export_name("clientProgramSemanticDocumentJson")
pub fn client_program_semantic_document_json(
  prepared : @publication_host.PreparedClientProgram,
) -> Result[String, @publication_host.ClientIdentityMaterialIssue] {
  @publication_host.emit_prepared_client_semantic_program(
    prepared, 100000, 10000, 100,
  )
}

///|
/// Expose the Definition issued by the checked owner for Local compilation.
/// Its body is private compilation material, not a public Client wire value.
#export_name("clientProgramDefinitionJson")
pub fn client_program_definition_json(
  prepared : @publication_host.PreparedClientProgram,
) -> Result[String, @publication_host.ClientIdentityMaterialIssue] {
  @publication_host.emit_prepared_client_program_definition(
    prepared, 100000, 10000, 100,
  )
}

///|
/// Expose the owner-sealed Program Semantics referenced by the Definition.
#export_name("clientProgramSemanticsJson")
pub fn client_program_semantics_json(
  prepared : @publication_host.PreparedClientProgram,
) -> Result[String, @publication_host.ClientIdentityMaterialIssue] {
  @publication_host.emit_prepared_client_program_semantics(
    prepared, 100000, 10000, 100,
  )
}

///|
/// Expose one Stage Semantics body referenced by Program Semantics.
#export_name("clientProgramStageSemanticsJson")
pub fn client_program_stage_semantics_json(
  prepared : @publication_host.PreparedClientProgram,
  stage : Int,
) -> Result[String, @publication_host.ClientIdentityMaterialIssue] {
  @publication_host.emit_prepared_client_stage_semantics(
    prepared, stage, 100000, 10000, 100,
  )
}

///|
/// Keep the checked Result row ceiling and its owner-issued witnesses intact.
#export_name("clientProgramPublicationRowsLimitJson")
pub fn client_program_publication_rows_limit_json(
  prepared : @publication_host.PreparedClientProgram,
  unit : Int,
  index : Int,
) -> Result[String, @publication_host.ClientPublicationLimitIssue] {
  @publication_host.emit_prepared_client_publication_limit(
    prepared,
    unit,
    index,
    @publication_host.Rows,
    100000,
    10000,
    100,
  )
}

///|
/// Keep the checked Result byte ceiling separate from its row ceiling.
#export_name("clientProgramPublicationBytesLimitJson")
pub fn client_program_publication_bytes_limit_json(
  prepared : @publication_host.PreparedClientProgram,
  unit : Int,
  index : Int,
) -> Result[String, @publication_host.ClientPublicationLimitIssue] {
  @publication_host.emit_prepared_client_publication_limit(
    prepared,
    unit,
    index,
    @publication_host.Bytes,
    100000,
    10000,
    100,
  )
}

///|
/// Private Plan material binds the checked Unit Result row ceiling to its port.
#export_name("clientProgramPublicationRowsBindingJson")
pub fn client_program_publication_rows_binding_json(
  prepared : @publication_host.PreparedClientProgram,
  unit : Int,
  index : Int,
) -> Result[String, @publication_host.ClientPublicationBindingIssue] {
  @publication_host.emit_prepared_client_publication_binding(
    prepared,
    unit,
    index,
    @publication_host.Rows,
    100000,
    10000,
    100,
  )
}

///|
/// Private Plan material binds the byte ceiling independently from rows.
#export_name("clientProgramPublicationBytesBindingJson")
pub fn client_program_publication_bytes_binding_json(
  prepared : @publication_host.PreparedClientProgram,
  unit : Int,
  index : Int,
) -> Result[String, @publication_host.ClientPublicationBindingIssue] {
  @publication_host.emit_prepared_client_publication_binding(
    prepared,
    unit,
    index,
    @publication_host.Bytes,
    100000,
    10000,
    100,
  )
}

///|
/// Check a saved row binding against the current checked Unit Result port.
#export_name("clientProgramAdmitPublicationRowsBinding")
pub fn client_program_admit_publication_rows_binding(
  prepared : @publication_host.PreparedClientProgram,
  unit : Int,
  index : Int,
  body : String,
) -> Result[Unit, @publication_host.ClientPublicationBindingAdmissionIssue] {
  @publication_host.admit_prepared_client_publication_binding(
    prepared,
    unit,
    index,
    @publication_host.Rows,
    body,
    100000,
    10000,
    100,
  )
}

///|
/// Check a saved byte binding independently from the row measurement.
#export_name("clientProgramAdmitPublicationBytesBinding")
pub fn client_program_admit_publication_bytes_binding(
  prepared : @publication_host.PreparedClientProgram,
  unit : Int,
  index : Int,
  body : String,
) -> Result[Unit, @publication_host.ClientPublicationBindingAdmissionIssue] {
  @publication_host.admit_prepared_client_publication_binding(
    prepared,
    unit,
    index,
    @publication_host.Bytes,
    body,
    100000,
    10000,
    100,
  )
}

///|
/// Admit every checked Unit Result row and byte binding as one complete set.
/// This is private Plan material, not a standalone Run authorization.
#export_name("clientProgramAdmitPublicationBindingSet")
pub fn client_program_admit_publication_binding_set(
  prepared : @publication_host.PreparedClientProgram,
  bodies : Array[String],
) -> Result[Unit, @publication_host.ClientPublicationBindingSetIssue] {
  @publication_host.admit_prepared_client_publication_binding_set(
    prepared, bodies, 1000, 100000, 10000, 100,
  )
}

///|
/// Admit the complete checked Result publication limits and their consumers.
#export_name("clientProgramAdmitPublicationPlanFacts")
pub fn client_program_admit_publication_plan_facts(
  prepared : @publication_host.PreparedClientProgram,
  limits : Array[String],
  bindings : Array[String],
) -> Result[Unit, @publication_host.ClientPublicationPlanFactIssue] {
  @publication_host.admit_prepared_client_publication_plan_facts(
    prepared, limits, bindings, 1000, 100000, 10000, 100,
  )
}

///|
/// Issue the checked Result-publication Plan subset for this private JS bridge.
#export_name("clientProgramIssuePublicationPlanFacts")
pub fn client_program_issue_publication_plan_facts(
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  @publication_host.ClientPublicationPlanFacts,
  @publication_host.ClientPublicationPlanFactIssue,
] {
  @publication_host.issue_prepared_client_publication_plan_facts(
    prepared, 1000, 100000, 10000, 100,
  )
}

///|
#export_name("clientProgramPublicationPlanFactLimits")
pub fn client_program_publication_plan_fact_limits(
  facts : @publication_host.ClientPublicationPlanFacts,
) -> Array[String] {
  @publication_host.client_publication_plan_fact_limits(facts)
}

///|
#export_name("clientProgramPublicationPlanFactBindings")
pub fn client_program_publication_plan_fact_bindings(
  facts : @publication_host.ClientPublicationPlanFacts,
) -> Array[String] {
  @publication_host.client_publication_plan_fact_bindings(facts)
}

///|
/// Return the checked Result-publication entries for Plan fact assembly.
#export_name("clientProgramPublicationPlanFactEntries")
pub fn client_program_publication_plan_fact_entries(
  facts : @publication_host.ClientPublicationPlanFacts,
) -> Array[String] {
  @publication_host.client_publication_plan_fact_entries(facts)
}

///|
/// The checked publication-limit witness closure is private Plan material.
#export_name("clientProgramIssuePublicationWitnesses")
pub fn client_program_issue_publication_witnesses(
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  @publication_host.ClientPublicationWitnesses,
  @publication_host.ClientPublicationWitnessIssue,
] {
  @publication_host.issue_prepared_client_publication_witnesses(
    prepared, 10000, 100000, 10000, 100,
  )
}

///|
#export_name("clientProgramPublicationWitnessBodies")
pub fn client_program_publication_witness_bodies(
  value : @publication_host.ClientPublicationWitnesses,
) -> Array[String] {
  @publication_host.client_publication_witness_bodies(value)
}

///|
#export_name("clientProgramPublicationWitnessCids")
pub fn client_program_publication_witness_cids(
  value : @publication_host.ClientPublicationWitnesses,
) -> Array[String] {
  @publication_host.client_publication_witness_cids(value)
}

///|
#export_name("clientProgramAdmitPublicationWitnesses")
pub fn client_program_admit_publication_witnesses(
  prepared : @publication_host.PreparedClientProgram,
  saved : Array[String],
) -> Result[
  @publication_host.ClientPublicationWitnesses,
  @publication_host.ClientPublicationWitnessAdmissionIssue,
] {
  @publication_host.admit_prepared_client_publication_witnesses(
    prepared, saved, 10000, 100000, 10000, 100,
  )
}

///|
/// Check saved Result-publication entries against the prepared Program.
#export_name("clientProgramAdmitPublicationFactEntries")
pub fn client_program_admit_publication_fact_entries(
  prepared : @publication_host.PreparedClientProgram,
  entries : Array[String],
) -> Result[Unit, @publication_host.ClientPublicationFactEntryIssue] {
  @publication_host.admit_prepared_client_publication_fact_entries(
    prepared, entries, 1000, 100000, 10000, 100,
  )
}

///|
/// Bind a saved manifest to the Plan's exact fact array and canonical CID.
/// The product compiler must still validate each fact and the whole Plan.
#export_name("clientProgramCheckPlanFactManifestIdentity")
pub fn client_program_check_plan_fact_manifest_identity(
  manifest_wire : String,
  plan_facts_wire : String,
) -> Result[String, @publication_host.PlanFactManifestIdentityIssue] {
  @publication_host.check_plan_fact_manifest_identity(
    manifest_wire, plan_facts_wire, 100000, 10000, 100,
  )
}

///|
/// Encode a complete fact array after its individual owners have assembled it.
#export_name("clientProgramEncodePlanFactManifestIdentity")
pub fn client_program_encode_plan_fact_manifest_identity(
  plan_facts_wire : String,
) -> Result[
  @publication_host.PlanFactManifestIdentity,
  @publication_host.PlanFactManifestIdentityIssue,
] {
  @publication_host.encode_plan_fact_manifest_identity(
    plan_facts_wire, 100000, 10000, 100,
  )
}

///|
#export_name("clientProgramPlanFactManifestWire")
pub fn client_program_plan_fact_manifest_wire(
  value : @publication_host.PlanFactManifestIdentity,
) -> String {
  @publication_host.plan_fact_manifest_identity_wire(value)
}

///|
#export_name("clientProgramPlanFactManifestCid")
pub fn client_program_plan_fact_manifest_cid(
  value : @publication_host.PlanFactManifestIdentity,
) -> String {
  @publication_host.plan_fact_manifest_identity_cid(value)
}

///|
/// In-process compiler material for this installed Local profile. The same
/// bounded sequence limits govern physical task preparation below. The output
/// is not an Executable Plan, publication authority or Client wire value.
#export_name("clientProgramLocalAoASteps")
pub fn client_program_local_aoa_steps(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
) -> Result[String, @publication_host.ClientTaskAoAStepsIssue] {
  @publication_host.emit_prepared_client_task_aoa_steps(
    prepared,
    task,
    client_local_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
/// Expose the checked one-node Values pipeline for Local Plan compilation.
/// It remains private compilation material until complete Plan admission.
#export_name("clientProgramLocalValuesPipelineJson")
pub fn client_program_local_values_pipeline_json(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
) -> Result[String, @publication_host.ClientValuesPipelineIssue] {
  @publication_host.emit_prepared_client_values_pipeline(
    prepared,
    task,
    client_local_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
/// Private compiler material, issued from the same checked Values owner.
#export_name("clientProgramIssueLocalValuesAoAIdentity")
pub fn client_program_issue_local_values_aoa_identity(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
) -> Result[
  @publication_host.ClientValuesAoAIdentity,
  @publication_host.ClientValuesAoAIdentityIssue,
] {
  @publication_host.issue_prepared_client_values_aoa_identity(
    prepared,
    task,
    client_local_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
/// Product-owned empty binding identity for a checked Program with no opaque
/// declarations. A nonempty binding requires live Host reference admission.
#export_name("clientProgramIssueEmptyInvocationBindings")
pub fn client_program_issue_empty_invocation_bindings(
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  @publication.RunEvidenceValue,
  @publication_host.ClientEmptyInvocationBindingsIssue,
] {
  @publication_host.issue_prepared_client_empty_invocation_bindings(
    prepared, 100000, 10000, 100,
  )
}

///|
#export_name("clientProgramLocalValuesAoAWire")
pub fn client_program_local_values_aoa_wire(
  value : @publication_host.ClientValuesAoAIdentity,
) -> String {
  @publication_host.client_values_aoa_identity_wire(value)
}

///|
#export_name("clientProgramIssueEffectValuesFragment")
pub fn client_program_issue_effect_values_fragment(
  prepared : @publication_host.PreparedClientEffectComputation,
  task : Int,
) -> Result[
  @publication_host.ClientValuesFragmentNode,
  @publication_host.ClientValuesFragmentIssue,
] {
  @publication_host.issue_prepared_client_effect_values_fragment(
    prepared,
    task,
    client_local_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
#export_name("clientProgramValuesFragmentLogicalCid")
pub fn client_program_values_fragment_logical_cid(
  fragment : @publication_host.ClientValuesFragmentNode,
) -> String {
  @publication_host.client_values_fragment_logical_cid(fragment)
}

///|
#export_name("clientProgramLocalValuesAoACid")
pub fn client_program_local_values_aoa_cid(
  value : @publication_host.ClientValuesAoAIdentity,
) -> String {
  @publication_host.client_values_aoa_identity_cid(value)
}

///|
/// Unit-form source for the checked single-stage Values compilation path.
/// The Host must still bind the complete Executable Plan and authorization.
#export_name("clientProgramLocalValuesUnitSourceJson")
pub fn client_program_local_values_unit_source_json(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
) -> Result[String, @publication_host.ClientValuesUnitSourceIssue] {
  @publication_host.emit_prepared_client_values_unit_source(
    prepared,
    task,
    client_local_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
/// Checked output schema for the same Values task and AoA identity.
#export_name("clientProgramIssueLocalValuesOutputSchema")
pub fn client_program_issue_local_values_output_schema(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
) -> Result[
  @execution.RelationSchemaIdentity,
  @publication_host.ClientValuesOutputSchemaIssue,
] {
  @publication_host.issue_prepared_client_values_output_schema(
    prepared,
    task,
    client_local_sequence_limits(),
    { max_fields: 100, max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    100000,
    10000,
    100,
  )
}

///|
#export_name("clientProgramLocalValuesOutputSchemaWire")
pub fn client_program_local_values_output_schema_wire(
  value : @execution.RelationSchemaIdentity,
) -> String {
  @execution.relation_schema_wire(value)
}

///|
#export_name("clientProgramLocalValuesOutputSchemaCid")
pub fn client_program_local_values_output_schema_cid(
  value : @execution.RelationSchemaIdentity,
) -> String {
  @execution.relation_schema_cid(value)
}

///|
/// The checked Values AoA Fragment node and full output row contract.
/// Neither this node nor its type CID is an Executable Plan.
#export_name("clientProgramIssueLocalValuesFragment")
pub fn client_program_issue_local_values_fragment(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
) -> Result[
  @publication_host.ClientValuesFragmentNode,
  @publication_host.ClientValuesFragmentIssue,
] {
  @publication_host.issue_prepared_client_values_fragment(
    prepared,
    task,
    client_local_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
/// Replan saved private Fragment bytes against the checked Program owner.
#export_name("clientProgramAdmitLocalValuesFragment")
pub fn client_program_admit_local_values_fragment(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  saved_wire : String,
) -> Result[
  @publication_host.ClientValuesFragmentNode,
  @publication_host.ClientValuesFragmentAdmissionIssue,
] {
  @publication_host.admit_prepared_client_values_fragment(
    prepared,
    task,
    saved_wire,
    client_local_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
#export_name("clientProgramLocalValuesFragmentWire")
pub fn client_program_local_values_fragment_wire(
  value : @publication_host.ClientValuesFragmentNode,
) -> String {
  @publication_host.client_values_fragment_wire(value)
}

///|
#export_name("clientProgramLocalValuesFragmentOutputContractCid")
pub fn client_program_local_values_fragment_output_contract_cid(
  value : @publication_host.ClientValuesFragmentNode,
) -> String {
  @publication_host.client_values_fragment_output_contract_cid(value)
}

///|
#export_name("clientProgramLocalValuesFragmentOutputContractWire")
pub fn client_program_local_values_fragment_output_contract_wire(
  value : @publication_host.ClientValuesFragmentNode,
) -> String {
  @publication_host.client_values_fragment_output_contract_wire(value)
}

///|
/// Checked graph material for the installed source-free Values profile.
/// Other Plan evidence and Host authorization remain separate.
#export_name("clientProgramIssueLocalValuesPlanGraph")
pub fn client_program_issue_local_values_plan_graph(
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  @publication_host.ClientValuesPlanGraph,
  @publication_host.ClientValuesPlanGraphIssue,
] {
  @publication_host.issue_prepared_client_values_plan_graph(
    prepared,
    client_local_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
#export_name("clientProgramAdmitLocalValuesPlanGraph")
pub fn client_program_admit_local_values_plan_graph(
  prepared : @publication_host.PreparedClientProgram,
  saved_wire : String,
) -> Result[
  @publication_host.ClientValuesPlanGraph,
  @publication_host.ClientValuesPlanGraphAdmissionIssue,
] {
  @publication_host.admit_prepared_client_values_plan_graph(
    prepared,
    saved_wire,
    client_local_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
#export_name("clientProgramLocalValuesPlanGraphWire")
pub fn client_program_local_values_plan_graph_wire(
  value : @publication_host.ClientValuesPlanGraph,
) -> String {
  @publication_host.client_values_plan_graph_wire(value)
}

///|
pub(all) enum ClientProgramValuesPlanBridgeIssue {
  Manifests(@publication_host.ClientCompilationManifestIssue)
  Plan(@publication_host.ClientValuesExecutablePlanIssue)
}

///|
/// Issue the complete private Plan for the installed direct Values profile.
/// The pinned manifest bodies are admitted before compilation; this operation
/// does not grant Host Run authority or expose Plan material on public wire.
#export_name("clientProgramIssueLocalValuesExecutablePlan")
pub fn client_program_issue_local_values_executable_plan(
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  @publication_host.ClientValuesExecutablePlan,
  ClientProgramValuesPlanBridgeIssue,
] {
  let manifests = match
    @publication_host.admit_client_compilation_manifests(
      @check_environment.compiler_grammar_manifest_wire(),
      @check_environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    ) {
    Ok(manifests) => manifests
    Err(issue) => return Err(Manifests(issue))
  }
  match
    @publication_host.issue_prepared_client_values_executable_plan(
      prepared,
      manifests,
      client_local_sequence_limits(),
      1000,
      10000,
      1000000,
      100000,
      100,
    ) {
    Ok(plan) => Ok(plan)
    Err(issue) => Err(Plan(issue))
  }
}

///|
#export_name("clientProgramLocalValuesExecutablePlanWire")
pub fn client_program_local_values_executable_plan_wire(
  value : @publication_host.ClientValuesExecutablePlan,
) -> String {
  @publication_host.client_values_executable_plan_wire(value)
}

///|
#export_name("clientProgramLocalValuesExecutablePlanCid")
pub fn client_program_local_values_executable_plan_cid(
  value : @publication_host.ClientValuesExecutablePlan,
) -> String {
  @publication_host.client_values_executable_plan_cid(value)
}

///|
#export_name("clientProgramLocalValuesPlanFactManifestWire")
pub fn client_program_local_values_plan_fact_manifest_wire(
  value : @publication_host.ClientValuesExecutablePlan,
) -> String {
  @publication_host.client_values_executable_plan_fact_manifest_wire(value)
}

///|
pub(all) enum ClientProgramValuesCompilationBridgeIssue {
  Manifests(@publication_host.ClientCompilationManifestIssue)
  Compilation(@publication_host.ClientValuesCompilationIssue)
}

///|
/// Compile the installed direct Values profile through the shared MoonBit
/// owner. The returned handles are private Host material, not public wire.
#export_name("clientProgramCompileLocalValues")
pub fn client_program_compile_local_values(
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  @publication_host.ClientValuesCompilation,
  ClientProgramValuesCompilationBridgeIssue,
] {
  let manifests = match
    @publication_host.admit_client_compilation_manifests(
      @check_environment.compiler_grammar_manifest_wire(),
      @check_environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    ) {
    Ok(manifests) => manifests
    Err(issue) => return Err(Manifests(issue))
  }
  match
    @publication_host.issue_prepared_client_values_compilation(
      prepared,
      manifests,
      client_local_sequence_limits(),
      1000,
      10000,
      1000000,
      100000,
      100,
    ) {
    Ok(compiled) => Ok(compiled)
    Err(issue) => Err(Compilation(issue))
  }
}

///|
pub(all) enum ClientProgramTaskPlanBridgeIssue {
  Manifests(@publication_host.ClientCompilationManifestIssue)
  Plan(@publication_host.ClientValuesExecutablePlanIssue)
}

///|
#export_name("clientProgramIssueTaskExecutablePlan")
pub fn client_program_issue_task_executable_plan(
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  @publication_host.ClientTaskExecutablePlan,
  ClientProgramTaskPlanBridgeIssue,
] {
  let manifests = match
    @publication_host.admit_client_compilation_manifests(
      @check_environment.compiler_grammar_manifest_wire(),
      @check_environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    ) {
    Ok(manifests) => manifests
    Err(issue) => return Err(Manifests(issue))
  }
  @publication_host.issue_prepared_client_task_executable_plan(
    prepared,
    manifests,
    client_local_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
  ).map_err(issue => Plan(issue))
}

///|
#export_name("clientProgramTaskExecutablePlanWire")
pub fn client_program_task_executable_plan_wire(
  value : @publication_host.ClientTaskExecutablePlan,
) -> String {
  @publication_host.client_task_executable_plan_wire(value)
}

///|
pub(all) enum ClientProgramTaskCompilationBridgeIssue {
  Manifests(@publication_host.ClientCompilationManifestIssue)
  Compilation(@publication_host.ClientTaskCompilationIssue)
}

///|
#export_name("clientProgramCompileLocalTasks")
pub fn client_program_compile_local_tasks(
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  @publication_host.ClientTaskCompilation,
  ClientProgramTaskCompilationBridgeIssue,
] {
  let manifests = match
    @publication_host.admit_client_compilation_manifests(
      @check_environment.compiler_grammar_manifest_wire(),
      @check_environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    ) {
    Ok(manifests) => manifests
    Err(issue) => return Err(Manifests(issue))
  }
  @publication_host.issue_prepared_client_task_compilation(
    prepared,
    manifests,
    client_local_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
  ).map_err(issue => Compilation(issue))
}

///|
#export_name("clientProgramTaskCompilationPlanWire")
pub fn client_program_task_compilation_plan_wire(
  value : @publication_host.ClientTaskCompilation,
) -> String {
  @publication_host.client_task_executable_plan_wire(
    @publication_host.client_task_compilation_plan(value),
  )
}

///|
#export_name("clientProgramTaskCompilationTemplateWire")
pub fn client_program_task_compilation_template_wire(
  value : @publication_host.ClientTaskCompilation,
) -> String {
  @publication.run_evidence_value_json(
    @publication_host.client_task_compilation_template(value),
  )
}

///|
#export_name("clientProgramTaskCompilationCompiledPlanWire")
pub fn client_program_task_compilation_compiled_plan_wire(
  value : @publication_host.ClientTaskCompilation,
) -> String {
  @publication.publication_contract_json(
    @publication_host.client_task_compilation_compiled_plan(value),
  )
}

///|
/// Host-internal projection of one checked task's AoA pipeline. It does not
/// authorize source acquisition or stand in for a complete Executable Plan.
#export_name("clientProgramTaskPipelineWire")
pub fn client_program_task_pipeline_wire(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
) -> Result[String, @publication_host.ClientTaskPipelineIssue] {
  @publication_host.emit_prepared_client_task_pipeline(
    prepared,
    task,
    client_local_sequence_limits(),
    1000000,
    100000,
    100,
  )
}

///|
#export_name("clientProgramIssueTaskFragment")
pub fn client_program_issue_task_fragment(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
) -> Result[
  @publication_host.ClientTaskFragmentNode,
  @publication_host.ClientTaskFragmentIssue,
] {
  @publication_host.issue_prepared_client_task_fragment(
    prepared,
    task,
    client_local_sequence_limits(),
    1000000,
    100000,
    100,
  )
}

///|
#export_name("clientProgramTaskFragmentWire")
pub fn client_program_task_fragment_wire(
  value : @publication_host.ClientTaskFragmentNode,
) -> String {
  @publication_host.client_task_fragment_wire(value)
}

///|
#export_name("clientProgramIssueTaskPlanGraph")
pub fn client_program_issue_task_plan_graph(
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  @publication_host.ClientTaskPlanGraph,
  @publication_host.ClientTaskPlanGraphIssue,
] {
  @publication_host.issue_prepared_client_task_plan_graph(
    prepared,
    client_local_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
#export_name("clientProgramTaskPlanGraphWire")
pub fn client_program_task_plan_graph_wire(
  value : @publication_host.ClientTaskPlanGraph,
) -> String {
  @publication_host.client_task_plan_graph_wire(value)
}

///|
/// Expose the checked acquisition to the installed physical adapter without
/// accepting caller-supplied source requests or a parallel Program graph.
#export_name("clientProgramPrepareQueryAcquisition")
pub fn client_program_prepare_query_acquisition(
  prepared : @publication_host.PreparedClientProgram,
  stage : Int,
  source_index : Int,
) -> Result[
  @acquisition.QueryAcquisition,
  @publication_host.ClientAcquisitionIssue,
] {
  @publication_host.prepare_client_query_acquisition(
    prepared, stage, source_index,
  )
}

///|
#export_name("clientProgramEffectPrepareQueryAcquisition")
pub fn client_program_effect_prepare_query_acquisition(
  prepared : @publication_host.PreparedClientEffectComputation,
  stage : Int,
  source_index : Int,
) -> Result[
  @acquisition.QueryAcquisition,
  @publication_host.ClientAcquisitionIssue,
] {
  @publication_host.prepare_client_effect_query_acquisition(
    prepared, stage, source_index,
  )
}

///|
#export_name("clientProgramQueryAcquisitionSourceIndex")
pub fn client_program_query_acquisition_source_index(
  acquisition : @acquisition.QueryAcquisition,
) -> Int {
  @acquisition.query_acquisition_source_index(acquisition)
}

///|
#export_name("clientProgramPrepareLocalQueryRequirement")
pub fn client_program_prepare_local_query_requirement(
  prepared : @publication_host.PreparedClientProgram,
  stage : Int,
  source_index : Int,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[
  @planning.QueryRequirement,
  @client_local_host.ClientLocalQueryIssue,
] {
  @client_local_host.prepare_local_query_requirement(
    prepared, stage, source_index, registry_body, values_body, fragment_body, ordered_body,
  )
}

///|
#export_name("clientProgramEffectPrepareLocalQueryRequirement")
pub fn client_program_effect_prepare_local_query_requirement(
  prepared : @publication_host.PreparedClientEffectComputation,
  stage : Int,
  source_index : Int,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[
  @planning.QueryRequirement,
  @client_local_host.ClientLocalQueryIssue,
] {
  @client_local_host.prepare_effect_local_query_requirement(
    prepared, stage, source_index, registry_body, values_body, fragment_body, ordered_body,
  )
}

///|
#export_name("clientProgramQueryRequirementCid")
pub fn client_program_query_requirement_cid(
  requirement : @planning.QueryRequirement,
) -> String {
  @planning.query_requirement_cid(requirement)
}

///|
#export_name("clientProgramQueryRequirementSourceRef")
pub fn client_program_query_requirement_source_ref(
  requirement : @planning.QueryRequirement,
) -> String {
  @planning.query_requirement_source(requirement).0
}

///|
#export_name("clientProgramQueryRequirementSourceContractCid")
pub fn client_program_query_requirement_source_contract_cid(
  requirement : @planning.QueryRequirement,
) -> String {
  @planning.query_requirement_source(requirement).1
}

///|
#export_name("clientProgramQueryRequirementInputContractCid")
pub fn client_program_query_requirement_input_contract_cid(
  requirement : @planning.QueryRequirement,
) -> String {
  @planning.query_requirement_contracts(requirement).0
}

///|
#export_name("clientProgramQueryRequirementOutputContractCid")
pub fn client_program_query_requirement_output_contract_cid(
  requirement : @planning.QueryRequirement,
) -> String {
  @planning.query_requirement_contracts(requirement).1
}

///|
/// The checked SourceView's contract and policy facts. Physical observation,
/// capability and current authorization remain Host responsibilities.
#export_name("clientProgramQueryRequirementSourceEvidenceFacts")
pub fn client_program_query_requirement_source_evidence_facts(
  requirement : @planning.QueryRequirement,
) -> Result[Array[String], String] {
  match @planning.query_requirement_source_evidence_facts(requirement) {
    Some(facts) => Ok(@planning.query_source_evidence_fact_values(facts))
    None => Err("CheckedSourceEvidenceFactsUnavailable")
  }
}

///|
#export_name("clientProgramPrepareDuckDBAcquisition")
pub fn client_program_prepare_duckdb_acquisition(
  requirement : @planning.QueryRequirement,
  database_schema : String,
  table : String,
  query_contract_body : String,
  evidence_contract_body : String,
  two_receipt_contract_body : String,
) -> Result[
  @duckdb_host.NativeHostConfiguration,
  @client_local_host.ClientDuckDBAcquisitionIssue,
] {
  @client_local_host.prepare_client_duckdb_acquisition(
    requirement, database_schema, table, query_contract_body, evidence_contract_body,
    two_receipt_contract_body,
  )
}

///|
#export_name("clientProgramPrepareDuckDBBroadAcquisition")
pub fn client_program_prepare_duckdb_broad_acquisition(
  requirement : @planning.QueryRequirement,
  database_schema : String,
  table : String,
  query_contract_body : String,
  evidence_contract_body : String,
  two_receipt_contract_body : String,
) -> Result[
  @duckdb_host.BroadHostConfiguration,
  @client_local_host.ClientDuckDBAcquisitionIssue,
] {
  @client_local_host.prepare_client_duckdb_broad_acquisition(
    requirement, database_schema, table, query_contract_body, evidence_contract_body,
    two_receipt_contract_body,
  )
}

///|
#export_name("clientProgramDuckDBAcquisitionEstimate")
pub fn client_program_duckdb_acquisition_estimate(
  work_slots : Array[Array[Int]],
  milliseconds : Array[Int64?],
  quantities : Array[Int64?],
) -> Result[
  @client_local_host.ClientDuckDBAcquisitionEstimate,
  @client_local_host.ClientDuckDBAcquisitionIssue,
] {
  @client_local_host.client_duckdb_acquisition_estimate(
    work_slots, milliseconds, quantities,
  )
}

///|
#export_name("clientProgramSelectDuckDBAcquisition")
pub fn client_program_select_duckdb_acquisition(
  requirement : @planning.QueryRequirement,
  database_schema : String,
  table : String,
  query_contract_body : String,
  evidence_contract_body : String,
  two_receipt_contract_body : String,
  native_estimate : @client_local_host.ClientDuckDBAcquisitionEstimate,
  broad_estimate : @client_local_host.ClientDuckDBAcquisitionEstimate,
  priority : Array[String],
) -> Result[
  @client_local_host.ClientDuckDBAcquisitionSelection,
  @client_local_host.ClientDuckDBAcquisitionIssue,
] {
  @client_local_host.select_client_duckdb_acquisition(
    requirement,
    database_schema,
    table,
    query_contract_body,
    evidence_contract_body,
    two_receipt_contract_body,
    native_estimate,
    broad_estimate,
    host_priority=if priority.is_empty() { None } else { Some(priority) },
  )
}

///|
#export_name("clientProgramDuckDBSelectionNative")
pub fn client_program_duckdb_selection_native(
  selected : @client_local_host.ClientDuckDBAcquisitionSelection,
) -> @duckdb_host.NativeHostConfiguration? {
  @client_local_host.client_duckdb_selection_native(selected)
}

///|
#export_name("clientProgramDuckDBSelectionBroad")
pub fn client_program_duckdb_selection_broad(
  selected : @client_local_host.ClientDuckDBAcquisitionSelection,
) -> @duckdb_host.BroadHostConfiguration? {
  @client_local_host.client_duckdb_selection_broad(selected)
}

///|
#export_name("clientProgramDuckDBSelectionDocument")
pub fn client_program_duckdb_selection_document(
  selected : @client_local_host.ClientDuckDBAcquisitionSelection,
) -> String {
  @client_local_host.client_duckdb_selection_document(selected)
}

///|
#export_name("clientProgramDuckDBNativeCandidateUnavailable")
pub fn client_program_duckdb_native_candidate_unavailable(
  outcome : Result[
    @duckdb_host.NativeHostConfiguration,
    @client_local_host.ClientDuckDBAcquisitionIssue,
  ],
) -> Bool {
  outcome is Err(@client_local_host.Candidate)
}

///|
#export_name("clientProgramCapturedSourceMatches")
pub fn client_program_captured_source_matches(
  prepared : @publication_host.PreparedClientProgram,
  source : @query.CapturedInputSource,
) -> Bool {
  captured_source_matches_graph(
    @publication_host.prepared_client_graph(prepared),
    source,
  )
}

///|
#export_name("clientProgramEffectCapturedSourceMatches")
pub fn client_program_effect_captured_source_matches(
  prepared : @publication_host.PreparedClientEffectComputation,
  source : @query.CapturedInputSource,
) -> Bool {
  captured_source_matches_graph(
    @strategy.checked_effect_computation_graph(
      @publication_host.prepared_client_effect_computation_graph(prepared),
    ),
    source,
  )
}

///|
#export_name("clientProgramEffectCapturedSourceMatchesAt")
pub fn client_program_effect_captured_source_matches_at(
  prepared : @publication_host.PreparedClientEffectComputation,
  source : @query.CapturedInputSource,
  task : Int,
) -> Bool {
  captured_source_matches_graph(
    @strategy.checked_effect_computation_graph(
      @publication_host.prepared_client_effect_computation_graph(prepared),
    ),
    source,
    task~,
  )
}

///|
fn captured_source_matches_graph(
  graph : @strategy.CheckedDAG,
  source : @query.CapturedInputSource,
  task? : Int = 0,
) -> Bool {
  if task < 0 || task >= @strategy.graph_captured_prefix(graph) {
    return false
  }
  guard @strategy.graph_task_owner(graph, task) is Some(owner) else {
    return false
  }
  @query.captured_source_matches(
    source,
    @program_check.source_identity(@strategy.graph_program(graph)),
    owner,
  )
}

///|
/// Installed Local bounds match the standard Result export profile. The
/// identity is computed while the physical acquisition issuer remains live.
#export_name("clientProgramIdentifyCapturedSourceRelation")
pub fn client_program_identify_captured_source_relation(
  source : @query.CapturedInputSource,
) -> Result[@query.CapturedSourceRelationIdentity, @query.CapturedSourceIssue] {
  identify_installed_captured_source(source, 0)
}

///|
#export_name("clientProgramIdentifyCapturedEffectSourceRelation")
pub fn client_program_identify_captured_effect_source_relation(
  source : @query.CapturedInputSource,
) -> Result[@query.CapturedSourceRelationIdentity, @query.CapturedSourceIssue] {
  identify_installed_captured_source(source, 16777216)
}

///|
/// Installed, on-demand identity for a file-represented acquisition. The same
/// standard export profile applies without materializing the complete source.
#export_name("clientProgramPrepareCapturedSourceIdentityScan")
pub fn client_program_prepare_captured_source_identity_scan(
  source : @query.CapturedInputSource,
) -> Result[
  @query.CapturedSourceIdentityScan,
  @query.CapturedSourceIdentityScanIssue,
] {
  @query.prepare_captured_source_identity_scan(
    source,
    10000,
    100000,
    10000,
    {
      max_nodes: 1000000,
      max_text_bytes: 10000000,
      max_depth: 64,
      max_work: 1000000,
    },
    {
      max_columns: 100,
      max_order_work: 1000000,
      max_bytes: 10000000,
      max_nodes: 1000000,
      max_depth: 64,
    },
    {
      max_columns: 100,
      max_order_work: 1000000,
      max_bytes: 10000000,
      max_nodes: 1000003,
      max_depth: 66,
    },
    { max_fields: 100, max_bytes: 100000, max_nodes: 10000, max_depth: 64, },
    65536,
  )
}

///|
#export_name("clientProgramCapturedSourceIdentityScanStorage")
pub fn client_program_captured_source_identity_scan_storage(
  scan : @query.CapturedSourceIdentityScan,
) -> @execution.ProducerStorage? {
  @query.captured_source_identity_scan_storage(scan)
}

///|
#export_name("clientProgramAppendCapturedSourceIdentityScan")
pub fn client_program_append_captured_source_identity_scan(
  scan : @query.CapturedSourceIdentityScan,
  row : String,
) -> Result[Unit, @query.CapturedSourceIdentityScanIssue] {
  @query.append_captured_source_identity_scan(scan, row, {
    max_bytes: 65536,
    max_nodes: 1000000,
    max_depth: 64,
    max_text_bytes: 65536,
  })
}

///|
#export_name("clientProgramCapturedSourceIdentityScanMaterial")
pub fn client_program_captured_source_identity_scan_material(
  scan : @query.CapturedSourceIdentityScan,
) -> @execution.RetainedOutputMaterial? {
  @query.captured_source_identity_scan_storage(scan).bind(storage => {
    @execution.producer_storage_retained_material(storage)
  })
}

///|
#export_name("clientProgramFinishCapturedSourceIdentityScan")
pub fn client_program_finish_captured_source_identity_scan(
  scan : @query.CapturedSourceIdentityScan,
) -> Result[
  @query.CapturedSourceRelationIdentity,
  @query.CapturedSourceIdentityScanIssue,
] {
  @query.finish_captured_source_identity_scan(scan)
}

///|
#export_name("clientProgramCancelCapturedSourceIdentityScan")
pub fn client_program_cancel_captured_source_identity_scan(
  scan : @query.CapturedSourceIdentityScan,
) -> Bool {
  @query.cancel_captured_source_identity_scan(scan)
}

///|
#export_name("clientProgramCapturedSourceDependencyBodies")
pub fn client_program_captured_source_dependency_bodies(
  identity : @query.CapturedSourceRelationIdentity,
  source : @query.CapturedInputSource,
) -> (String, String)? {
  @query.captured_source_relation_dependency_bodies(identity, source)
}

///|
fn identify_installed_captured_source(
  source : @query.CapturedInputSource,
  retain_body_bytes : Int,
) -> Result[@query.CapturedSourceRelationIdentity, @query.CapturedSourceIssue] {
  @query.identify_captured_source_relation(
    source,
    10000,
    {
      max_nodes: 1000000,
      max_text_bytes: 10000000,
      max_depth: 64,
      max_work: 1000000,
    },
    {
      max_columns: 100,
      max_order_work: 1000000,
      max_bytes: 10000000,
      max_nodes: 1000000,
      max_depth: 64,
    },
    {
      max_columns: 100,
      max_order_work: 1000000,
      max_bytes: 10000000,
      max_nodes: 1000003,
      max_depth: 66,
    },
    { max_fields: 100, max_bytes: 100000, max_nodes: 10000, max_depth: 64, },
    65536,
    retain_body_bytes~,
  )
}

///|
#export_name("clientProgramCapturedSourceLogicalCid")
pub fn client_program_captured_source_logical_cid(
  identity : @query.CapturedSourceRelationIdentity,
) -> String {
  @query.captured_source_relation_logical_cid(identity)
}

///|
#export_name("clientProgramCapturedSourceSchemaCid")
pub fn client_program_captured_source_schema_cid(
  identity : @query.CapturedSourceRelationIdentity,
) -> String {
  @query.captured_source_relation_schema_cid(identity)
}

///|
#export_name("clientProgramCapturedSourceRowCount")
pub fn client_program_captured_source_row_count(
  identity : @query.CapturedSourceRelationIdentity,
) -> Int {
  @query.captured_source_relation_row_count(identity)
}

///|
pub(all) enum ClientCapturedSourceLogicalIssue {
  ForeignPrepared
  ForeignIdentity
  ForeignRequirement
  Encoding(@encode.EncodeFailure)
  Evidence(@publication.RunEvidenceValueIssue)
  Admission(@publication.SourceInputLogicalIssue)
}

///|
/// Issue the semantic input only after the checked capture owner completes
/// its bounded Relation traversal. The installed profile makes no source
/// ordering guarantee; observation and read authority remain separate.
#export_name("clientProgramIssueCapturedSourceLogical")
pub fn client_program_issue_captured_source_logical(
  prepared : @publication_host.PreparedClientProgram,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
) -> Result[@publication.RunEvidenceValue, ClientCapturedSourceLogicalIssue] {
  issue_captured_source_logical_graph(
    @publication_host.prepared_client_graph(prepared),
    source,
    identity,
    requirement,
  )
}

///|
#export_name("clientProgramEffectIssueCapturedSourceLogical")
pub fn client_program_effect_issue_captured_source_logical(
  prepared : @publication_host.PreparedClientEffectComputation,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
) -> Result[@publication.RunEvidenceValue, ClientCapturedSourceLogicalIssue] {
  issue_captured_source_logical_graph(
    @strategy.checked_effect_computation_graph(
      @publication_host.prepared_client_effect_computation_graph(prepared),
    ),
    source,
    identity,
    requirement,
  )
}

///|
#export_name("clientProgramEffectIssueCapturedSourceLogicalAt")
pub fn client_program_effect_issue_captured_source_logical_at(
  prepared : @publication_host.PreparedClientEffectComputation,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  task : Int,
) -> Result[@publication.RunEvidenceValue, ClientCapturedSourceLogicalIssue] {
  issue_captured_source_logical_graph(
    @strategy.checked_effect_computation_graph(
      @publication_host.prepared_client_effect_computation_graph(prepared),
    ),
    source,
    identity,
    requirement,
    task~,
  )
}

///|
fn issue_captured_source_logical_graph(
  graph : @strategy.CheckedDAG,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  task? : Int = 0,
) -> Result[@publication.RunEvidenceValue, ClientCapturedSourceLogicalIssue] {
  @publication_host.issue_captured_source_input_logical(
    graph,
    source,
    identity,
    requirement,
    task~,
  ).map_err(issue => {
    match issue {
      @publication_host.ForeignPrepared => ForeignPrepared
      @publication_host.ForeignIdentity => ForeignIdentity
      @publication_host.ForeignRequirement => ForeignRequirement
      @publication_host.Encoding(value) => Encoding(value)
      @publication_host.Evidence(value) => Evidence(value)
      @publication_host.Admission(value) => Admission(value)
    }
  })
}

///|
#export_name("clientProgramAdmitTaskPlanGraph")
pub fn client_program_admit_task_plan_graph(
  prepared : @publication_host.PreparedClientProgram,
  saved_wire : String,
) -> Result[
  @publication_host.ClientTaskPlanGraph,
  @publication_host.ClientTaskPlanGraphAdmissionIssue,
] {
  @publication_host.admit_prepared_client_task_plan_graph(
    prepared,
    saved_wire,
    client_local_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
#export_name("clientProgramCompilationExecutablePlanWire")
pub fn client_program_compilation_executable_plan_wire(
  value : @publication_host.ClientValuesCompilation,
) -> String {
  @publication_host.client_values_executable_plan_wire(
    @publication_host.client_values_compilation_plan(value),
  )
}

///|
#export_name("clientProgramCompilationFactManifestWire")
pub fn client_program_compilation_fact_manifest_wire(
  value : @publication_host.ClientValuesCompilation,
) -> String {
  @publication_host.client_values_executable_plan_fact_manifest_wire(
    @publication_host.client_values_compilation_plan(value),
  )
}

///|
#export_name("clientProgramCompilationTemplateWire")
pub fn client_program_compilation_template_wire(
  value : @publication_host.ClientValuesCompilation,
) -> String {
  @publication.run_evidence_value_json(
    @publication_host.client_values_compilation_template(value),
  )
}

///|
#export_name("clientProgramCompilationCompiledPlanWire")
pub fn client_program_compilation_compiled_plan_wire(
  value : @publication_host.ClientValuesCompilation,
) -> String {
  @publication.publication_contract_json(
    @publication_host.client_values_compilation_compiled_plan(value),
  )
}

///|
/// Checked Result row type from the exact publication port, after its
/// projection. This is private Plan material, not Run admission.
#export_name("clientProgramIssueResultRowContract")
pub fn client_program_issue_result_row_contract(
  prepared : @publication_host.PreparedClientProgram,
  unit : Int,
  index : Int,
) -> Result[
  @publication_host.ClientResultRowContractIdentity,
  @publication_host.ClientResultRowContractIssue,
] {
  @publication_host.issue_prepared_client_result_row_contract(
    prepared, unit, index, 100000, 10000, 100,
  )
}

///|
#export_name("clientProgramResultRowContractWire")
pub fn client_program_result_row_contract_wire(
  value : @publication_host.ClientResultRowContractIdentity,
) -> String {
  @publication_host.client_result_row_contract_wire(value)
}

///|
#export_name("clientProgramResultRowContractCid")
pub fn client_program_result_row_contract_cid(
  value : @publication_host.ClientResultRowContractIdentity,
) -> String {
  @publication_host.client_result_row_contract_cid(value)
}

///|
#export_name("clientProgramResultRowContractName")
pub fn client_program_result_row_contract_name(
  value : @publication_host.ClientResultRowContractIdentity,
) -> String {
  @publication_host.client_result_row_contract_name(value)
}

///|
#export_name("clientProgramResultRowContractUnitCid")
pub fn client_program_result_row_contract_unit_cid(
  value : @publication_host.ClientResultRowContractIdentity,
) -> String {
  @publication_host.client_result_row_contract_unit_cid(value)
}

///|
/// Checked Program Result identity issued by the shared MoonBit owner.
#export_name("clientProgramIssueResultPlan")
pub fn client_program_issue_result_plan(
  prepared : @publication_host.PreparedClientProgram,
  result : Int,
) -> Result[
  @publication_host.ClientResultPlanIdentity,
  @publication_host.ClientResultPlanIssue,
] {
  @publication_host.issue_prepared_client_result_plan(
    prepared, result, 100000, 10000, 100,
  )
}

///|
/// Recheck saved Result Plan bytes against the same checked export.
#export_name("clientProgramAdmitResultPlan")
pub fn client_program_admit_result_plan(
  prepared : @publication_host.PreparedClientProgram,
  result : Int,
  saved_wire : String,
) -> Result[
  @publication_host.ClientResultPlanIdentity,
  @publication_host.ClientResultPlanAdmissionIssue,
] {
  @publication_host.admit_prepared_client_result_plan(
    prepared, result, saved_wire, 100000, 10000, 100,
  )
}

///|
#export_name("clientProgramResultPlanWire")
pub fn client_program_result_plan_wire(
  value : @publication_host.ClientResultPlanIdentity,
) -> String {
  @publication_host.client_result_plan_wire(value)
}

///|
#export_name("clientProgramResultPlanCid")
pub fn client_program_result_plan_cid(
  value : @publication_host.ClientResultPlanIdentity,
) -> String {
  @publication_host.client_result_plan_cid(value)
}

///|
#export_name("clientProgramResultPlanName")
pub fn client_program_result_plan_name(
  value : @publication_host.ClientResultPlanIdentity,
) -> String {
  @publication_host.client_result_plan_name(value)
}

///|
#export_name("clientProgramResultPlanRowContractCid")
pub fn client_program_result_plan_row_contract_cid(
  value : @publication_host.ClientResultPlanIdentity,
) -> String {
  @publication_host.client_result_plan_row_contract_cid(value)
}

///|
/// A checked Result can reference a Values Fragment directly only when its
/// published row schema, projection, and order are identical to that output.
#export_name("clientProgramIssueDirectValuesResultRoot")
pub fn client_program_issue_direct_values_result_root(
  prepared : @publication_host.PreparedClientProgram,
  result : Int,
) -> Result[
  @publication_host.ClientDirectResultRoot,
  @publication_host.ClientDirectResultRootIssue,
] {
  @publication_host.issue_prepared_client_direct_values_result_root(
    prepared,
    result,
    client_local_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
#export_name("clientProgramIssueDirectTaskResultRoot")
pub fn client_program_issue_direct_task_result_root(
  prepared : @publication_host.PreparedClientProgram,
  result : Int,
) -> Result[
  @publication_host.ClientDirectResultRoot,
  @publication_host.ClientDirectResultRootIssue,
] {
  @publication_host.issue_prepared_client_direct_task_result_root(
    prepared,
    result,
    client_local_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
#export_name("clientProgramAdmitDirectValuesResultRoot")
pub fn client_program_admit_direct_values_result_root(
  prepared : @publication_host.PreparedClientProgram,
  result : Int,
  saved_wire : String,
) -> Result[
  @publication_host.ClientDirectResultRoot,
  @publication_host.ClientDirectResultRootAdmissionIssue,
] {
  @publication_host.admit_prepared_client_direct_values_result_root(
    prepared,
    result,
    saved_wire,
    client_local_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
#export_name("clientProgramDirectValuesResultRootWire")
pub fn client_program_direct_values_result_root_wire(
  value : @publication_host.ClientDirectResultRoot,
) -> String {
  @publication_host.client_direct_result_root_wire(value)
}

///|
#export_name("clientProgramDirectValuesResultRootPlanCid")
pub fn client_program_direct_values_result_root_plan_cid(
  value : @publication_host.ClientDirectResultRoot,
) -> String {
  @publication_host.client_direct_result_root_plan_cid(value)
}

///|
#export_name("clientProgramDirectValuesResultRootRowContractCid")
pub fn client_program_direct_values_result_root_row_contract_cid(
  value : @publication_host.ClientDirectResultRoot,
) -> String {
  @publication_host.client_direct_result_root_row_contract_cid(value)
}

///|
/// Saved AoA material is rechecked against the exact prepared Program.
#export_name("clientProgramAdmitLocalValuesAoAIdentity")
pub fn client_program_admit_local_values_aoa_identity(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  saved_wire : String,
  claimed_cid : String,
) -> Result[Unit, @publication_host.ClientValuesAoAAdmissionIssue] {
  @publication_host.admit_prepared_client_values_aoa_identity(
    prepared,
    task,
    saved_wire,
    claimed_cid,
    client_local_sequence_limits(),
    100000,
    10000,
    100,
  )
}

///|
/// Open the portable installed Local Host from this JS bridge.
#export_name("clientProgramOpenSourceFreeLocalHost")
pub fn client_program_open_source_free_local_host(
  prepared : @publication_host.PreparedClientProgram,
  registry_body : String,
  values_body : String,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
  fragment_body : String?,
  ordered_body : String?,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  @client_local_host.open_source_free_local_host(
    prepared,
    registry_body,
    values_body,
    fixed_ms,
    per_row_ms,
    per_wire_byte_ms,
    per_pair_ms,
    fragment_body~,
    ordered_body~,
    provider_factory=installed_client_family_providers,
  )
}

///|
/// Open the same source-free Compute owner with retained Relation output.
/// The installed Host still owns Run admission, dispatch and publication.
#export_name("clientProgramOpenSourceFreeLocalRetainedHost")
pub fn client_program_open_source_free_local_retained_host(
  prepared : @publication_host.PreparedClientProgram,
  registry_body : String,
  values_body : String,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
  fragment_body : String?,
  ordered_body : String?,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  @client_local_host.open_source_free_local_retained_host(
    prepared,
    registry_body,
    values_body,
    fixed_ms,
    per_row_ms,
    per_wire_byte_ms,
    per_pair_ms,
    fragment_body~,
    ordered_body~,
    provider_factory=installed_client_family_providers,
  )
}

///|
/// The Local compute owner consumes a verified source from the installed
/// physical acquisition adapter, preserving the checked Program graph.
#export_name("clientProgramOpenCapturedLocalHost")
pub fn client_program_open_captured_local_host(
  prepared : @publication_host.PreparedClientProgram,
  source : @query.CapturedInputSource,
  registry_body : String,
  values_body : String,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
  fragment_body : String?,
  ordered_body : String?,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  @client_local_host.open_captured_local_host(
    prepared,
    source,
    registry_body,
    values_body,
    fixed_ms,
    per_row_ms,
    per_wire_byte_ms,
    per_pair_ms,
    fragment_body~,
    ordered_body~,
    provider_factory=installed_client_family_providers,
  )
}

///|
/// The acquired source retains its exact owner while downstream Local tasks
/// use the existing retained Store completion and publication boundary.
#export_name("clientProgramOpenCapturedLocalRetainedHost")
pub fn client_program_open_captured_local_retained_host(
  prepared : @publication_host.PreparedClientProgram,
  source : @query.CapturedInputSource,
  registry_body : String,
  values_body : String,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
  fragment_body : String?,
  ordered_body : String?,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  @client_local_host.open_captured_local_retained_host(
    prepared,
    source,
    registry_body,
    values_body,
    fixed_ms,
    per_row_ms,
    per_wire_byte_ms,
    per_pair_ms,
    fragment_body~,
    ordered_body~,
    provider_factory=installed_client_family_providers,
  )
}

///|
/// Document format and Parameter Values are admitted once for either
/// computation kind. Neither branch may reinterpret the supplied JSON.
fn client_program_input(
  format : String,
  parameters : String?,
) -> Result[(@stage_syntax.Format, @decode.Cursor?), ClientProgramBridgeIssue] {
  let selected = match format {
    "json" => @stage_syntax.Json
    "yaml" => @stage_syntax.Yaml
    _ => return Err(InvalidFormat)
  }
  let supplied = match parameters {
    None => None
    Some(body) => {
      let parsed = match
        @source.parse_json_bytes(
          @utf8.encode(body),
          { max_input_bytes: 65536, max_nodes: 8192, max_depth: 64, },
          source_path="Client Parameters",
        ) {
        Ok(value) => value
        Err(issue) => return Err(SuppliedSyntax(issue))
      }
      match
        @decode.admit(parsed, {
          max_nodes: 8192,
          max_depth: 64,
          max_string_bytes: 65536,
          max_total_string_bytes: 65536,
        }) {
        Ok(value) => Some(value)
        Err(issue) => return Err(SuppliedAdmission(issue))
      }
    }
  }
  Ok((selected, supplied))
}

///|
fn client_program_standard_limits() -> @publication_host.ClientProgramPreparationLimits {
  @publication_host.client_standard_program_preparation_limits()
}

///|
/// Internal Host preparation only. A prepared Effect computation is neither
/// a checked Effect Run nor an apply permit, and the public submit adapter
/// continues to reject nonempty Effects until the complete Run path exists.
pub(all) enum ClientEffectProgramBridgeIssue {
  Input(ClientProgramBridgeIssue)
  Preparation(@publication_host.ClientEffectComputationIssue)
}

///|
pub(all) enum ClientEffectProgramBridgeOutcome {
  EffectPrepared(@publication_host.PreparedClientEffectComputation)
  EffectRejected(ClientEffectProgramBridgeIssue)
}

///|
fn client_program_effect_limits() -> @publication_host.ClientEffectComputationLimits {
  {
    program: client_program_standard_limits(),
    max_members: 1024,
    max_header_work: 1000000,
    mapping: {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 64,
      max_members: 256,
    },
    max_mapping_work: 100000,
    effects: {
      max_members: 1024,
      max_work: 1000000,
      max_admission_nodes: 100000,
      max_admission_depth: 64,
      max_admission_text_bytes: 1000000,
    },
  }
}

///|
#export_name("clientProgramPrepareEffectComputationWithParameters")
pub fn client_program_prepare_effect_computation_with_parameters(
  document : String,
  format : String,
  environment : @program_check.CheckEnvironment,
  parameters : String?,
  evidence : Array[@context.StageCapacityInput],
) -> ClientEffectProgramBridgeOutcome {
  let (selected, supplied) = match client_program_input(format, parameters) {
    Ok(value) => value
    Err(issue) => return EffectRejected(Input(issue))
  }
  match
    @publication_host.prepare_client_effect_computation(
      document,
      selected,
      environment,
      supplied,
      evidence,
      client_program_effect_limits(),
    ) {
    Ok(value) => EffectPrepared(value)
    Err(issue) => EffectRejected(Preparation(issue))
  }
}

///|
#export_name("clientProgramEffectPreparationReady")
pub fn client_program_effect_preparation_ready(
  outcome : ClientEffectProgramBridgeOutcome,
) -> @publication_host.PreparedClientEffectComputation? {
  match outcome {
    EffectPrepared(value) => Some(value)
    EffectRejected(_) => None
  }
}

///|
#export_name("clientProgramEffectPreparationIssue")
pub fn client_program_effect_preparation_issue(
  outcome : ClientEffectProgramBridgeOutcome,
) -> ClientEffectProgramBridgeIssue? {
  match outcome {
    EffectPrepared(_) => None
    EffectRejected(issue) => Some(issue)
  }
}

///|
#export_name("clientProgramEffectPreparationIssueCode")
pub fn client_program_effect_preparation_issue_code(
  outcome : ClientEffectProgramBridgeOutcome,
) -> String? {
  match outcome {
    EffectPrepared(_) => None
    EffectRejected(issue) =>
      Some(
        match issue {
          Input(InvalidFormat) => "invalid_format"
          Input(SuppliedSyntax(_)) => "supplied_syntax"
          Input(SuppliedAdmission(_)) => "supplied_admission"
          Input(Preparation(_)) => "invalid_input_owner"
          Input(SourcePreparation(_)) => "invalid_input_owner"
          Preparation(Syntax(_)) => "program_syntax"
          Preparation(Candidate(_)) => "effect_candidate_rejected"
          Preparation(Mapping(_)) => "effect_mapping_rejected"
          Preparation(Static(_)) => "effect_static_rejected"
          Preparation(Stage(_)) => "stage_rejected"
          Preparation(Graph(_)) => "graph_rejected"
        },
      )
  }
}

///|
#export_name("clientProgramEffectDefinitionCid")
pub fn client_program_effect_definition_cid(
  value : @publication_host.PreparedClientEffectComputation,
) -> String {
  @publication_host.prepared_client_effect_computation_definition_cid(value)
}

///|
#export_name("clientProgramEffectResultCount")
pub fn client_program_effect_result_count(
  value : @publication_host.PreparedClientEffectComputation,
) -> Int {
  @publication_host.prepared_client_effect_result_count(value)
}

///|
#export_name("clientProgramEffectResultName")
pub fn client_program_effect_result_name(
  value : @publication_host.PreparedClientEffectComputation,
  index : Int,
) -> String? {
  @publication_host.prepared_client_effect_result_name(value, index)
}

///|
/// One Effectful logical request before Run admission. An equal key with a
/// changed checked Effect intent conflicts; neither this identity nor a
/// prepared computation permits mutation dispatch.
#export_name("clientProgramEffectRequestIdentity")
pub fn client_program_effect_request_identity(
  prepared : @publication_host.PreparedClientEffectComputation,
  authority_scope_cid : String,
  caller_request_id : String,
  caller_input_intent_cid : String,
) -> @publication_host.ClientRequestIdentity? {
  match
    @publication_host.prepare_client_effect_request_identity(
      prepared, authority_scope_cid, caller_request_id, caller_input_intent_cid,
    ) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
#export_name("clientProgramEffectSemanticsCid")
pub fn client_program_effect_semantics_cid(
  value : @publication_host.PreparedClientEffectComputation,
) -> String {
  @publication_host.prepared_client_effect_computation_semantics_cid(value)
}

///|
#export_name("clientProgramEffectEnvironmentCid")
pub fn client_program_effect_environment_cid(
  value : @publication_host.PreparedClientEffectComputation,
) -> String {
  @publication_host.prepared_client_effect_computation_environment_cid(value)
}

///|
pub(all) enum ClientEffectPlanIdentityIssue {
  Binding(@effect_results.EffectPlanBindingIssue)
  Encoding
} derive(Debug)

///|
/// Derive one Result-correlated member's Plan identity from the checked
/// static owner before a private Preview is authored. This is neither a
/// captured input nor authority to apply the Effect.
#export_name("clientProgramEffectPlanCid")
pub fn client_program_effect_plan_cid(
  value : @publication_host.PreparedClientEffectComputation,
  member_index : Int,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String?, ClientEffectPlanIdentityIssue] {
  let candidate = @publication_host.prepared_client_effect_computation_candidate(
    value,
  )
  let effects = @program_check.effect_program_static_effects(candidate)
  let rules = @effect_results.effect_static_candidate_mapping_rules(effects)
  let terminal = match
    @effect_results.effect_plan_terminal_for_member(
      rules, member_index, max_fields, max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  match terminal {
    None => Ok(None)
    Some(terminal) =>
      Ok(
        Some(
          @effect_results.effect_plan_pipeline_cid(
            terminal, max_bytes, max_nodes, max_depth,
          ),
        ),
      ) catch {
        _ => Err(Encoding)
      }
  }
}

///|
/// Read the authored member and its resolved Mapping through the portable
/// checked owner. The Node bridge makes no independent identity decision.
#export_name("clientProgramEffectMemberDescriptor")
pub fn client_program_effect_member_descriptor(
  value : @publication_host.PreparedClientEffectComputation,
  stage_index : Int,
  effect_id : String,
  max_work : Int,
) -> Result[
  (Int, String, String, String, String, String, String?, String),
  @publication_host.ClientEffectMemberDescriptorIssue,
] {
  @publication_host.client_effect_member_descriptor(
    value, stage_index, effect_id, max_work,
  )
}

///|
/// The local semantic Invocation comes from the checked Unit owner. Its CID
/// is not the physical Run Invocation and does not authorize Effect apply.
#export_name("clientProgramIssueSourceFreeLocalEffectInvocation")
pub fn client_program_issue_source_free_local_effect_invocation(
  value : @publication_host.PreparedClientEffectComputation,
  unit : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalInvocation,
  @publication_host.ClientEffectLocalInvocationIssue,
] {
  @publication_host.issue_source_free_client_effect_local_invocation(
    value, unit, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramIssueAcquiredLocalEffectInvocation")
pub fn client_program_issue_acquired_local_effect_invocation(
  owner : @publication_host.PreparedClientEffectComputation,
  captured : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  input : @publication.RunEvidenceValue,
  observation : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalInvocation,
  @publication_host.ClientEffectLocalInvocationIssue,
] {
  @publication_host.issue_acquired_client_effect_local_invocation(
    owner, captured, identity, requirement, input, observation, authority_scope_cid,
    data_policy_cid, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramIssueCapturedEffectInputLocalInvocation")
pub fn client_program_issue_captured_effect_input_local_invocation(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalInvocation,
  @publication_host.ClientEffectLocalInvocationIssue,
] {
  @publication_host.issue_source_free_captured_client_effect_local_invocation(
    owner, inputs, member_index, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramIssueAcquiredEffectEvidence")
pub fn client_program_issue_acquired_effect_evidence(
  owner : @publication_host.PreparedClientEffectComputation,
  captured : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  input : @publication.RunEvidenceValue,
  observation : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  data_policy_cid : String,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectAcquiredEvidence,
  @publication_host.ClientEffectAcquiredEvidenceIssue,
] {
  @publication_host.issue_client_effect_acquired_evidence(
    owner, captured, identity, requirement, input, observation, authority_scope_cid,
    data_policy_cid, retention, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramIssueAcquiredEffectEvidenceAt")
pub fn client_program_issue_acquired_effect_evidence_at(
  owner : @publication_host.PreparedClientEffectComputation,
  unit : Int,
  captured : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  input : @publication.RunEvidenceValue,
  observation : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  data_policy_cid : String,
  retention : @publication.PublicationContract,
  publication_retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectAcquiredEvidence,
  @publication_host.ClientEffectAcquiredEvidenceIssue,
] {
  @publication_host.issue_client_effect_acquired_evidence(
    owner,
    captured,
    identity,
    requirement,
    input,
    observation,
    authority_scope_cid,
    data_policy_cid,
    retention,
    max_bytes,
    max_nodes,
    max_depth,
    unit~,
    publication_retention=Some(publication_retention),
  )
}

///|
#export_name("clientProgramAcquiredEffectDependencyBodies")
pub fn client_program_acquired_effect_dependency_bodies(
  value : @publication_host.ClientEffectAcquiredEvidence,
) -> Array[(String, String)] {
  @publication_host.client_effect_acquired_dependency_bodies(value)
}

///|
#export_name("clientProgramAcquiredEffectInvocation")
pub fn client_program_acquired_effect_invocation(
  value : @publication_host.ClientEffectAcquiredEvidence,
) -> @publication_host.ClientEffectLocalInvocation {
  @publication_host.client_effect_acquired_invocation(value)
}

///|
#export_name("clientProgramAcquiredEffectCatalogBodies")
pub fn client_program_acquired_effect_catalog_bodies(
  value : @publication_host.ClientEffectAcquiredEvidence,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  Array[(String, String, String)],
  @publication_host.ClientEffectAcquiredEvidenceIssue,
] {
  @publication_host.client_effect_acquired_catalog_bodies(
    value, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramAcquiredEffectRequestCid")
pub fn client_program_acquired_effect_request_cid(
  value : @publication_host.ClientEffectAcquiredEvidence,
) -> String {
  @publication_host.client_effect_acquired_request_cid(value)
}

///|
#export_name("clientProgramIssueAcquiredEffectLocalResultArtifact")
pub fn client_program_issue_acquired_effect_local_result_artifact(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  source : @publication_host.ClientEffectAcquiredEvidence,
  definition : @publication_host.ClientEffectLocalResultDefinition,
  receipt : @execution.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  run_invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  @publication_host.ClientEffectLocalResultArtifactIssue,
] {
  @publication_host.issue_acquired_client_effect_local_result_artifact(
    owner, inputs, exported, source, definition, receipt, admission, run_definition,
    run_invocation, observation, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramLocalEffectInvocationCid")
pub fn client_program_local_effect_invocation_cid(
  value : @publication_host.ClientEffectLocalInvocation,
) -> String {
  @publication_host.client_effect_local_invocation_cid(value)
}

///|
#export_name("clientProgramLocalEffectInvocationJson")
pub fn client_program_local_effect_invocation_json(
  value : @publication_host.ClientEffectLocalInvocation,
) -> String {
  @publication_host.client_effect_local_invocation_json(value)
}

///|
/// A Stage Result is resolved inside its checked local Unit, never through
/// the Program Result publication inventory.
#export_name("clientProgramIssueLocalEffectResultDefinition")
pub fn client_program_issue_local_effect_result_definition(
  value : @publication_host.PreparedClientEffectComputation,
  unit : Int,
  result_name : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultDefinition,
  @publication_host.ClientEffectLocalResultDefinitionIssue,
] {
  @publication_host.issue_client_effect_local_result_definition(
    value, unit, result_name, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Bind the definition to the exact captured Effect source pin used by the
/// product input export, not to a copied Stage name.
#export_name("clientProgramIssueCapturedEffectInputLocalResultDefinition")
pub fn client_program_issue_captured_effect_input_local_result_definition(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultDefinition,
  @publication_host.ClientEffectLocalResultDefinitionIssue,
] {
  @publication_host.issue_captured_client_effect_local_result_definition(
    owner, inputs, member_index, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramLocalEffectResultDefinitionCid")
pub fn client_program_local_effect_result_definition_cid(
  value : @publication_host.ClientEffectLocalResultDefinition,
) -> String {
  @publication_host.client_effect_local_result_definition_cid(value)
}

///|
#export_name("clientProgramLocalEffectResultDefinitionJson")
pub fn client_program_local_effect_result_definition_json(
  value : @publication_host.ClientEffectLocalResultDefinition,
) -> String {
  @publication_host.client_effect_local_result_definition_json(value)
}

///|
/// The checked source-free Unit, captured Result, and export receipt must
/// remain paired. This does not grant publication or Effect mutation.
pub(all) enum ClientEffectLocalArtifactBridgeIssue {
  ForeignExport
  Issuance(@publication_host.ClientEffectLocalResultArtifactIssue)
} derive(Eq, Debug)

///|
#export_name("clientProgramIssueSourceFreeLocalEffectResultArtifact")
pub fn client_program_issue_source_free_local_effect_result_artifact(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  importing : ClientEffectManagedInputImport,
  definition : @publication_host.ClientEffectLocalResultDefinition,
  invocation : @publication_host.ClientEffectLocalInvocation,
  receipt : @execution.CompletedRelationExportReceipt,
  retention : @publication.PublicationContract,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  run_invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  ClientEffectLocalArtifactBridgeIssue,
] {
  guard importing.preparation is Some(preparation) &&
    importing.input is Some(input) else {
    return Err(ForeignExport)
  }
  @publication_host.issue_source_free_client_effect_local_result_artifact(
    owner,
    inputs,
    member_index,
    input,
    importing.output,
    importing.bridge,
    preparation,
    definition,
    invocation,
    receipt,
    retention,
    admission,
    run_definition,
    run_invocation,
    observation,
    max_wire_bytes,
    max_nodes,
    max_depth,
  ).map_err(issue => Issuance(issue))
}

///|
#export_name("clientProgramIssueSourceFreeExportedLocalEffectResultArtifact")
pub fn client_program_issue_source_free_exported_local_effect_result_artifact(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  invocation : @publication_host.ClientEffectLocalInvocation,
  definition : @publication_host.ClientEffectLocalResultDefinition,
  receipt : @execution.CompletedRelationExportReceipt,
  retention : @publication.PublicationContract,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  run_invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  @publication_host.ClientEffectLocalResultArtifactIssue,
] {
  @publication_host.issue_source_free_exported_client_effect_local_result_artifact(
    owner, inputs, exported, definition, invocation, receipt, retention, admission,
    run_definition, run_invocation, observation, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramLocalEffectResultArtifactCid")
pub fn client_program_local_effect_result_artifact_cid(
  value : @publication_host.ClientEffectLocalResultArtifact,
) -> String {
  @publication_host.client_effect_local_result_artifact_cid(value)
}

///|
#export_name("clientProgramIssueEffectResultImportObservation")
pub fn client_program_issue_effect_result_import_observation(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  captured : @strategy.CapturedEffectResultImport,
  manifest : @publication_host.ClientEffectLocalManifest,
  artifact : @publication_host.ClientEffectLocalResultArtifact,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectResultImportObservation,
  @publication_host.ClientEffectResultImportIssue,
] {
  @publication_host.issue_client_effect_result_import_observation(
    owner, inputs, captured, manifest, artifact, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramEffectResultImportObservationJson")
pub fn client_program_effect_result_import_observation_json(
  value : @publication_host.ClientEffectResultImportObservation,
) -> String {
  @publication_host.client_effect_result_import_observation_json(value)
}

///|
/// Inventory serialization reuses the original checked computation. The
/// returned body is not an execution permit or an independently checked Run.
#export_name("clientProgramEffectLocalDependencyBody")
pub fn client_program_effect_local_dependency_body(
  owner : @publication_host.PreparedClientEffectComputation,
  unit : Int,
  kind : String,
  index : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @program_check.CheckedLocalDependencyBody,
  @program_check.LocalDependencyBodyIssue,
] {
  guard client_effect_dependency_kind(kind, index) is Some(selected) else {
    return Err(@program_check.MissingDependency)
  }
  let program = @program_check.effect_program_static_checked_computation(
    @publication_host.prepared_client_effect_computation_candidate(owner),
  )
  @program_check.checked_local_dependency_body(
    program, unit, selected, max_bytes, max_nodes, max_depth,
  )
}

///|
fn client_effect_dependency_kind(
  kind : String,
  index : Int,
) -> @program_check.LocalDependencyBodyKind? {
  match kind {
    "local_dependencies" if index == 0 => Some(UnitDefinition)
    "local_body" if index == 0 => Some(LocalBody)
    "parameter_declarations" if index == 0 => Some(ParameterDeclarations)
    "used_values" if index == 0 => Some(UsedValues)
    "local_contracts" if index == 0 => Some(LocalContracts)
    "local_policy" if index == 0 => Some(LocalPolicy)
    "result_import_interface" if index >= 0 => Some(ResultInterface(index))
    "result_import_type" if index >= 0 => Some(ResultType(index))
    "gate_requirement" if index >= 0 => Some(IncomingGate(index))
    "schema_evidence" if index >= 0 => Some(SourceSchema(index))
    "capability_evidence" if index >= 0 => Some(SourceCapability(index))
    "source_view_contract" if index >= 0 => Some(SourceViewContract(index))
    "catalog_contract" if index >= 0 => Some(RegistryContract(index))
    _ => None
  }
}

///|
#export_name("clientProgramEffectLocalStaticBodies")
pub fn client_program_effect_local_static_bodies(
  owner : @publication_host.PreparedClientEffectComputation,
  unit : Int,
  max_entries : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  Array[(String, @program_check.CheckedLocalDependencyBody)],
  @program_check.LocalDependencyBodyIssue,
] {
  let program = @program_check.effect_program_static_checked_computation(
    @publication_host.prepared_client_effect_computation_candidate(owner),
  )
  @program_check.checked_local_dependency_bodies(
    program, unit, max_entries, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramAdmitEffectDependencyBody")
pub fn client_program_admit_effect_dependency_body(
  kind : String,
  cid : String?,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  @publication.CapturedEffectDependencyIssue,
] {
  @publication.admit_captured_effect_dependency_body(
    kind, cid, wire, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramEffectDependencyBodyCid")
pub fn client_program_effect_dependency_body_cid(
  body : @publication.CapturedEffectDependencyBody,
) -> String {
  @publication.captured_effect_dependency_body_cid(body)
}

///|
#export_name("clientProgramIssueEffectDependencyInventory")
pub fn client_program_issue_effect_dependency_inventory(
  bodies : Array[@publication.CapturedEffectDependencyBody],
  artifacts : Array[@publication_host.ClientEffectLocalResultArtifact],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @publication.CapturedEffectDependencyIssue] {
  if bodies.length() > 4096 || artifacts.length() > 4096 {
    return Err(@publication.EntryLimit)
  }
  let roots : Array[@publication.CapturedEffectDependencyBody] = []
  for artifact in artifacts {
    let root = match
      @publication.admit_publication_effect_dependency_body(
        "result_artifact",
        @publication_host.client_effect_local_result_artifact_json(artifact),
        max_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    roots.push(root)
  }
  match
    @publication.issue_captured_effect_dependency_inventory(
      bodies,
      roots,
      {
        max_entries: 4096,
        max_total_bytes: Int::min(max_bytes, 16777216),
        max_depth: 64,
        max_references: 65536,
      },
      max_nodes,
      max_depth,
    ) {
    Ok(value) =>
      Ok(@publication.captured_effect_dependency_inventory_json(value))
    Err(issue) => Err(issue)
  }
}

///|
#export_name("clientProgramAdmitEffectLocalDependencyBody")
pub fn client_program_admit_effect_local_dependency_body(
  owner : @publication_host.PreparedClientEffectComputation,
  unit : Int,
  kind : String,
  index : Int,
  expected : @program_check.CheckedLocalDependencyBody,
  saved_wire : String,
) -> Result[
  @program_check.CheckedLocalDependencyBody,
  @program_check.LocalDependencyBodyIssue,
] {
  guard client_effect_dependency_kind(kind, index) is Some(selected) else {
    return Err(@program_check.MissingDependency)
  }
  let program = @program_check.effect_program_static_checked_computation(
    @publication_host.prepared_client_effect_computation_candidate(owner),
  )
  @program_check.admit_checked_local_dependency_body(
    program, unit, selected, expected, saved_wire,
  )
}

///|
#export_name("clientProgramEffectLocalDependencyBodyCid")
pub fn client_program_effect_local_dependency_body_cid(
  value : @program_check.CheckedLocalDependencyBody,
) -> String {
  @program_check.checked_local_dependency_body_cid(value)
}

///|
#export_name("clientProgramEffectLocalDependencyBodyJson")
pub fn client_program_effect_local_dependency_body_json(
  value : @program_check.CheckedLocalDependencyBody,
) -> String {
  @program_check.checked_local_dependency_body_json(value)
}

///|
#export_name("clientProgramIssueImportedLocalEffectInvocation")
pub fn client_program_issue_imported_local_effect_invocation(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  unit : Int,
  observations : Array[@publication_host.ClientEffectResultImportObservation],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalInvocation,
  @publication_host.ClientEffectLocalInvocationIssue,
] {
  @publication_host.issue_imported_client_effect_local_invocation(
    owner, inputs, unit, observations, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramLocalEffectResultArtifactJson")
pub fn client_program_local_effect_result_artifact_json(
  value : @publication_host.ClientEffectLocalResultArtifact,
) -> String {
  @publication_host.client_effect_local_result_artifact_json(value)
}

///|
#export_name("clientProgramIssueImportedEffectEvidence")
pub fn client_program_issue_imported_effect_evidence(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  unit : Int,
  observations : Array[@publication_host.ClientEffectResultImportObservation],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectImportedEvidence,
  @publication_host.ClientEffectImportedEvidenceIssue,
] {
  @publication_host.issue_client_effect_imported_evidence(
    owner, inputs, unit, observations, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramImportedEffectInvocation")
pub fn client_program_imported_effect_invocation(
  value : @publication_host.ClientEffectImportedEvidence,
) -> @publication_host.ClientEffectLocalInvocation {
  @publication_host.client_effect_imported_invocation(value)
}

///|
#export_name("clientProgramImportedEffectScopeJson")
pub fn client_program_imported_effect_scope_json(
  value : @publication_host.ClientEffectImportedEvidence,
) -> String {
  @publication_host.client_effect_imported_scope_json(value)
}

///|
#export_name("clientProgramImportedEffectRelationBodies")
pub fn client_program_imported_effect_relation_bodies(
  value : @publication_host.ClientEffectImportedEvidence,
) -> Array[String] {
  @publication_host.client_effect_imported_relation_bodies(value)
}

///|
#export_name("clientProgramIssueImportedEffectLocalResultArtifact")
pub fn client_program_issue_imported_effect_local_result_artifact(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  imported : @publication_host.ClientEffectImportedEvidence,
  definition : @publication_host.ClientEffectLocalResultDefinition,
  receipt : @execution.CompletedRelationExportReceipt,
  retention : @publication.PublicationContract,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  run_invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  @publication_host.ClientEffectLocalResultArtifactIssue,
] {
  @publication_host.issue_imported_client_effect_local_result_artifact(
    owner, inputs, exported, imported, definition, receipt, retention, admission,
    run_definition, run_invocation, observation, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramLocalEffectResultDerivationJson")
pub fn client_program_local_effect_result_derivation_json(
  value : @publication_host.ClientEffectLocalResultArtifact,
) -> String {
  @publication_host.client_effect_local_result_derivation_json(value)
}

///|
#export_name("clientProgramLocalEffectResultPayloadBinding")
pub fn client_program_local_effect_result_payload_binding(
  value : @publication_host.ClientEffectLocalResultArtifact,
  run_definition : @publication.PublicationContract,
) -> Result[
  (String, Int),
  @publication_host.ClientEffectLocalResultArtifactIssue,
] {
  @publication_host.client_effect_local_result_payload_binding(
    value, run_definition,
  )
}

///|
#export_name("clientProgramLocalEffectResultOrderingJson")
pub fn client_program_local_effect_result_ordering_json(
  value : @publication_host.ClientEffectLocalResultArtifact,
) -> String {
  @publication_host.client_effect_local_result_ordering_json(value)
}

///|
#export_name("clientProgramIssueLocalEffectResultManifest")
pub fn client_program_issue_local_effect_result_manifest(
  owner : @publication_host.PreparedClientEffectComputation,
  invocation : @publication_host.ClientEffectLocalInvocation,
  artifacts : Array[@publication_host.ClientEffectLocalResultArtifact],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalManifest,
  @publication_host.ClientEffectLocalManifestIssue,
] {
  @publication_host.issue_client_effect_local_manifest(
    owner, invocation, artifacts, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramLocalEffectResultManifestCid")
pub fn client_program_local_effect_result_manifest_cid(
  value : @publication_host.ClientEffectLocalManifest,
) -> String {
  @publication_host.client_effect_local_manifest_cid(value)
}

///|
#export_name("clientProgramLocalEffectResultManifestJson")
pub fn client_program_local_effect_result_manifest_json(
  value : @publication_host.ClientEffectLocalManifest,
) -> String {
  @publication_host.client_effect_local_manifest_json(value)
}

///|
#export_name("clientProgramLocalEffectSourceMatches")
pub fn client_program_local_effect_source_matches(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  manifest : @publication_host.ClientEffectLocalManifest,
  invocation : @publication_host.ClientEffectLocalInvocation,
  artifact : @publication_host.ClientEffectLocalResultArtifact,
  source : @publication.CapturedEffectSourceArtifact,
) -> Bool {
  @publication_host.client_effect_local_source_matches(
    owner, inputs, member_index, manifest, invocation, artifact, source,
  )
}

///|
#export_name("clientProgramAdmitLocalEffectSourceEvidence")
pub fn client_program_admit_local_effect_source_evidence(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  manifest : @publication_host.ClientEffectLocalManifest,
  invocation : @publication_host.ClientEffectLocalInvocation,
  artifact : @publication_host.ClientEffectLocalResultArtifact,
  source : @publication.CapturedEffectSourceArtifact,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.CapturedLocalEffectSourceEvidence,
  @publication.CapturedLocalEffectSourceIssue,
] {
  @publication_host.admit_client_effect_local_source_evidence(
    owner, inputs, member_index, manifest, invocation, artifact, source, max_wire_bytes,
    max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramIssueSourceFreeLocalEffectIdentity")
pub fn client_program_issue_source_free_local_effect_identity(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  artifact : @publication_host.ClientEffectLocalResultArtifact,
  max_work : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalIdentity,
  @publication_host.ClientEffectLocalIdentityIssue,
] {
  @publication_host.issue_source_free_client_effect_local_identity(
    owner, inputs, member_index, artifact, max_work, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramLocalEffectIdentityCid")
pub fn client_program_local_effect_identity_cid(
  value : @publication_host.ClientEffectLocalIdentity,
) -> String {
  @publication_host.client_effect_local_identity_cid(value)
}

///|
#export_name("clientProgramLocalEffectIdentityJson")
pub fn client_program_local_effect_identity_json(
  value : @publication_host.ClientEffectLocalIdentity,
) -> String {
  @publication_host.client_effect_local_identity_json(value)
}

///|
#export_name("clientProgramCheckSourceFreeLocalEffectPreviewIdentities")
pub fn client_program_check_source_free_local_effect_preview_identities(
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  preview_wire : String,
  run_identity_cid : String,
  authoring_context_cid : String,
  identities : Array[@publication_host.ClientEffectLocalIdentity],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, @publication_host.ClientEffectLocalIdentityIssue] {
  @publication_host.check_source_free_client_effect_preview_identities(
    owner, inputs, preview_wire, run_identity_cid, authoring_context_cid, identities,
    max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Keep the Effect closure paired with the exact admitted Run. The returned
/// owner is still compute-only: it grants neither Preview nor apply.
#export_name("clientProgramBindEffectRun")
pub fn client_program_bind_effect_run(
  prepared : @publication_host.PreparedClientEffectComputation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
) -> @publication_host.PreparedClientEffectRun? {
  match
    @publication_host.bind_prepared_client_effect_run(
      prepared, admission, definition,
    ) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
/// Keep publication admission paired with the exact checked Effect Program.
/// Generic evidence admission alone cannot substitute for this owner check.
#export_name("clientProgramAdmitEffectPublication")
pub fn client_program_admit_effect_publication(
  prepared : @publication_host.PreparedClientEffectComputation,
  template : @publication.RunEvidenceValue,
  invocation : @publication.RunEvidenceValue,
  authorization : @publication.RunEvidenceValue,
  plan : @publication.PublicationContract,
) -> @publication.RunPublicationAdmission? {
  match
    @publication_host.admit_prepared_client_effect_run_publication(
      prepared, template, invocation, authorization, plan,
    ) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
fn client_local_contracts(
  registry_body : String,
  values_body : String,
) -> @execution.RegisteredRelationContracts? {
  if registry_body.length() > 100000 || values_body.length() > 100000 {
    return None
  }
  let registry_value = @identity.from_json(
    @json.parse(registry_body),
    10000,
    100,
    100000,
  ) catch {
    _ => return None
  }
  let values_value = @identity.from_json(
    @json.parse(values_body),
    10000,
    100,
    100000,
  ) catch {
    _ => return None
  }
  match
    @execution.admit_relation_registry(registry_value, values_value, {
      max_body_bytes: 100000,
      max_body_nodes: 10000,
      max_body_depth: 100,
    }) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
fn client_program_configure_local_host(
  run : @strategy.CapturedDAG,
  graph : @strategy.CheckedDAG,
  generated : Array[@execution.GeneratedSequence],
  first_compute : Int,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
  component_providers? : Array[@local.ManagedProvider] = [],
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  let capacity : @connector.FixedComputeCapacity = {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 100,
    max_value_bytes: 10000,
    common_fragment: None,
  }
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 100,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: 100000,
    max_frames: 100,
  }
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 10000,
    max_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let providers = match
    selected_client_sga_providers(generated, execution, measurement) {
    Some(providers) => providers
    None => return reject_client_local_run(run)
  }
  for provider in component_providers {
    providers.push(provider)
  }
  let local_configuration : @local_driver.LocalComputeConfiguration = {
    sequences: generated,
    managed_providers: providers,
    managed_capacity: capacity,
    execution,
    measurement,
    max_work: 100,
  }
  let bundle : @connector.CapabilityBundle[
    Unit,
    @local_driver.LocalComputeConfiguration,
    Unit,
  ] = {
    name: "local",
    acquisition: None,
    fixed_compute: Some((_, _) => local_configuration),
    effect: None,
  }
  let installed_bundles = match @connector.install_bundles([bundle], 1, 100) {
    Ok(value) => value
    Err(_) => return reject_client_local_run(run)
  }
  let registry = @connector.installed_bundle_registry(installed_bundles)
  guard @connector.capability_registration_at(registry, 0)
    is Some(local_registration) else {
    return reject_client_local_run(run)
  }
  guard @connector.capability_implementation(
      @connector.installed_compute_implementations(installed_bundles),
      local_registration,
    )
    is Some(local_configuration) else {
    return reject_client_local_run(run)
  }
  let modules = match
    @builtin.configure_compute_modules(
      @host_driver.open_dispatch_driver(run),
      registry,
      1,
      _ => @strategy.RunIssue::ForeignCandidate,
      with_local=Some(
        (
          local_registration,
          local_configuration,
          _ => @strategy.RunIssue::ForeignCandidate,
          _ => @strategy.RunIssue::ForeignCandidate,
        ),
      ),
    ) {
    Ok(value) => value
    Err(_) => return reject_client_local_run(run)
  }
  guard @builtin.configured_local_module(modules) is Some(installed) else {
    return reject_client_local_run(run)
  }
  match
    @local_driver.configure_local_retained_inputs(
      installed,
      @client_local_host.client_local_import_limits(capacity, values),
      None,
    ) {
    Ok(_) => ()
    Err(_) => return reject_client_local_run(run)
  }
  let slots = @local_driver.local_dispatch_work_slots()
  let schedule = match
    @cost.prepare_rate_schedule(
      slots,
      [
        {
          work_slots: Array::makei(slots, index => index),
          fixed_ms: Some(fixed_ms),
          per_row_ms: Some(per_row_ms),
          per_wire_byte_ms: Some(per_wire_byte_ms),
          per_pair_ms: Some(per_pair_ms),
        },
      ],
      100,
    ) {
    Ok(value) => value
    Err(_) => return reject_client_local_run(run)
  }
  let schedules = Array::make(
    @strategy.graph_task_count(graph) - first_compute,
    schedule,
  )
  let estimate = match
    @local_driver.prepare_local_estimate_module(installed, schedules, 1000) {
    Ok(value) => value
    Err(_) => return reject_client_local_run(run)
  }
  match @local_driver.install_local_dispatch_estimates(installed, estimate) {
    Ok(_) => ()
    Err(_) => return reject_client_local_run(run)
  }
  match
    @builtin.open_configured_compute_host(
      modules, registry, capacity, 100, 10000, 1,
    ) {
    Ok(value) => Some(value)
    Err(_) => reject_client_local_run(run)
  }
}

///|
/// Keep the exact captured Effect Run beside its installed compute Host.
/// The Host cannot later reconstruct this owner from a graph or CID alone.
struct ClientLocalEffectHost {
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue]
  run : @strategy.CapturedEffectRunDAG
}

///|
#export_name("clientProgramLocalEffectHostRuntime")
pub fn client_program_local_effect_host_runtime(
  value : ClientLocalEffectHost,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  value.host
}

///|
#export_name("clientProgramLocalEffectHostRun")
pub fn client_program_local_effect_host_run(
  value : ClientLocalEffectHost,
) -> @strategy.CapturedEffectRunDAG {
  value.run
}

///|
#export_name("clientProgramLocalEffectSourceCount")
pub fn client_program_local_effect_source_count(
  value : ClientLocalEffectHost,
) -> Int {
  @strategy.captured_effect_run_source_count(value.run)
}

///|
/// Capture every checked Effect source as one consumer holding after Compute.
/// The resulting owner is input custody only, never physical apply authority.
#export_name("clientProgramPinEffectSources")
pub fn client_program_pin_effect_sources(
  value : ClientLocalEffectHost,
  max_pins : Int,
) -> Result[@strategy.CapturedEffectInputs, @strategy.RunIssue] {
  @strategy.pin_captured_effect_sources(value.run, max_pins)
}

///|
/// Revoke the ordinary task port only after its checked Effect consumer has
/// acquired custody. Existing pins keep their own charged allocation.
#export_name("clientProgramCloseEffectSourcePort")
pub fn client_program_close_effect_source_port(
  value : @strategy.CapturedEffectInputs,
  member_index : Int,
) -> Bool {
  @strategy.close_captured_effect_source_port(value, member_index)
}

///|
#export_name("clientProgramEffectInputCount")
pub fn client_program_effect_input_count(
  value : @strategy.CapturedEffectInputs,
) -> Int {
  @strategy.captured_effect_inputs_count(value)
}

///|
#export_name("clientProgramEffectLocalResultCount")
pub fn client_program_effect_local_result_count(
  value : @strategy.CapturedEffectInputs,
) -> Int {
  @strategy.captured_effect_local_result_count(value)
}

///|
#export_name("clientProgramEffectLocalResultMatchesMember")
pub fn client_program_effect_local_result_matches_member(
  inputs : @strategy.CapturedEffectInputs,
  local_index : Int,
  member_index : Int,
) -> Bool {
  @strategy.captured_effect_local_result_matches_member(
    inputs, local_index, member_index,
  )
}

///|
#export_name("clientProgramEffectResultImportCount")
pub fn client_program_effect_result_import_count(
  owner : @publication_host.PreparedClientEffectComputation,
  unit : Int,
) -> Int? {
  @program_check.unit_result_import_count(
    @program_check.effect_program_static_checked_computation(
      @publication_host.prepared_client_effect_computation_candidate(owner),
    ),
    unit,
  )
}

///|
#export_name("clientProgramEffectCaptureResultImport")
pub fn client_program_effect_capture_result_import(
  inputs : @strategy.CapturedEffectInputs,
  consumer : Int,
  index : Int,
  max_work : Int,
) -> Result[@strategy.CapturedEffectResultImport, @strategy.RunIssue] {
  @strategy.capture_effect_result_import(inputs, consumer, index, max_work)
}

///|
#export_name("clientProgramEffectResultImportMatches")
pub fn client_program_effect_result_import_matches(
  value : @strategy.CapturedEffectResultImport,
  inputs : @strategy.CapturedEffectInputs,
  consumer : Int,
  producer : @strategy.CapturedEffectLocalResult,
) -> Bool {
  @strategy.captured_effect_result_import_matches(
    value, inputs, consumer, producer,
  )
}

///|
#export_name("clientProgramEffectLocalResultAt")
pub fn client_program_effect_local_result_at(
  value : @strategy.CapturedEffectInputs,
  index : Int,
) -> @strategy.CapturedEffectLocalResult? {
  @strategy.captured_effect_local_result_at(value, index)
}

///|
#export_name("clientProgramEffectLocalResultStage")
pub fn client_program_effect_local_result_stage(
  value : @strategy.CapturedEffectLocalResult,
) -> Int {
  @strategy.captured_effect_local_result_stage(value)
}

///|
#export_name("clientProgramEffectLocalResultTask")
pub fn client_program_effect_local_result_task(
  value : @strategy.CapturedEffectLocalResult,
) -> Int {
  @strategy.captured_effect_local_result_task(value)
}

///|
#export_name("clientProgramEffectLocalResultName")
pub fn client_program_effect_local_result_name(
  value : @strategy.CapturedEffectLocalResult,
) -> String {
  @execution.managed_result_occurrence_name(
    @strategy.captured_any_result_borrow_occurrence(
      @strategy.captured_effect_local_result_borrow(value),
    ),
  )
}

///|
#export_name("clientProgramEffectInputAvailable")
pub fn client_program_effect_input_available(
  value : @strategy.CapturedEffectInputs,
  member_index : Int,
) -> Bool {
  @strategy.captured_effect_input_at(value, member_index) is Some(_)
}

///|
#export_name("clientProgramEffectInputAt")
pub fn client_program_effect_input_at(
  value : @strategy.CapturedEffectInputs,
  member_index : Int,
) -> @strategy.CapturedEffectInput? {
  @strategy.captured_effect_input_at(value, member_index)
}

///|
/// Permit one checked export to feed multiple member proposals only for the
/// same live producer and Result occurrence, not an equal serialized view.
#export_name("clientProgramEffectInputsShareView")
pub fn client_program_effect_inputs_share_view(
  value : @strategy.CapturedEffectInputs,
  first_index : Int,
  second_index : Int,
) -> Bool {
  @strategy.captured_effect_inputs_share_view(value, first_index, second_index)
}

///|
/// Physical source selection is fixed by the captured graph, not by JS.
#export_name("clientProgramEffectInputTask")
pub fn client_program_effect_input_task(
  value : @strategy.CapturedEffectInput,
) -> Int {
  @strategy.captured_effect_input_task(value)
}

///|
/// Checked Unit coordinate for grouping a complete local Result Manifest.
#export_name("clientProgramEffectInputStage")
pub fn client_program_effect_input_stage(
  value : @strategy.CapturedEffectInput,
) -> Int {
  @strategy.captured_effect_input_stage(value)
}

///|
/// Release one member holding without revoking another borrow of the Result.
#export_name("clientProgramReleaseEffectInput")
pub fn client_program_release_effect_input(
  value : @strategy.CapturedEffectInput,
) -> Bool {
  @strategy.release_captured_effect_input(value)
}

///|
/// Private bounds for binding one admitted Preview to a captured Effect Run.
/// These do not replace current authorization, payload proof, or apply.
struct ClientEffectPreviewInputLimits {
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_binding_work : Int
  max_plan_fields : Int
  max_plan_bytes : Int
  max_plan_nodes : Int
  max_plan_depth : Int
  max_footprint_members : Int
  max_footprint_targets : Int
  max_footprint_work : Int
  max_source_work : Int
}

///|
#export_name("clientProgramEffectPreviewInputLimits")
pub fn client_program_effect_preview_input_limits(
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_binding_work : Int,
  max_plan_fields : Int,
  max_plan_bytes : Int,
  max_plan_nodes : Int,
  max_plan_depth : Int,
  max_footprint_members : Int,
  max_footprint_targets : Int,
  max_footprint_work : Int,
  max_source_work : Int,
) -> ClientEffectPreviewInputLimits? {
  if max_wire_bytes < 0 ||
    max_nodes < 1 ||
    max_depth < 0 ||
    max_binding_work < 0 ||
    max_plan_fields < 0 ||
    max_plan_bytes < 0 ||
    max_plan_nodes < 1 ||
    max_plan_depth < 0 ||
    max_footprint_members < 0 ||
    max_footprint_targets < 0 ||
    max_footprint_work < 0 ||
    max_source_work < 0 {
    return None
  }
  Some({
    max_wire_bytes,
    max_nodes,
    max_depth,
    max_binding_work,
    max_plan_fields,
    max_plan_bytes,
    max_plan_nodes,
    max_plan_depth,
    max_footprint_members,
    max_footprint_targets,
    max_footprint_work,
    max_source_work,
  })
}

///|
pub(all) enum ClientEffectPreviewInputIssue {
  Identity(@publication.EffectPreviewIdentityIssue)
  Binding(@program_check.EffectProgramRunPreviewIssue)
  Footprint(@effect.EffectFootprintIssue)
  Captured(@strategy.RunIssue)
}

///|
/// Bind the private Preview to the exact execution occurrence and its live
/// Result pins before a physical input can be proposed for mutation.
#export_name("clientProgramBindEffectPreviewInputs")
pub fn client_program_bind_effect_preview_inputs(
  host : ClientLocalEffectHost,
  inputs : @strategy.CapturedEffectInputs,
  invocation : @publication.PublicationContract,
  stage_index : Int,
  preview_wire : String,
  authoring_context_cid : String,
  limits : ClientEffectPreviewInputLimits,
) -> Result[
  @strategy.CapturedEffectPreviewInputs,
  ClientEffectPreviewInputIssue,
] {
  let owner = @strategy.captured_effect_run_owner(host.run)
  let run_cid = @publication.publication_contract_identity(
    @program_check.effect_program_run_definition(owner),
  )
  let preview = match
    @publication.admit_effect_preview_identity(
      preview_wire,
      run_cid,
      authoring_context_cid,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Identity(issue))
  }
  let bound = match
    @program_check.bind_effect_program_run_preview(
      owner,
      invocation,
      stage_index,
      preview,
      limits.max_binding_work,
      {
        max_work: limits.max_binding_work,
        max_fields: limits.max_plan_fields,
        max_bytes: limits.max_plan_bytes,
        max_nodes: limits.max_plan_nodes,
        max_depth: limits.max_plan_depth,
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  match
    @program_check.check_effect_program_run_preview_footprints(
      bound,
      limits.max_footprint_members,
      limits.max_footprint_targets,
      limits.max_footprint_work,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Footprint(issue))
  }
  @strategy.bind_captured_effect_preview_inputs(
    host.run,
    inputs,
    bound,
    limits.max_source_work,
  ).map_err(issue => Captured(issue))
}

///|
/// Supply durable Effect progress with the exact private Preview retained by
/// this captured Run. Historical progress does not authorize another send.
#export_name("clientProgramEffectPreviewLedgerIdentity")
pub fn client_program_effect_preview_ledger_identity(
  value : @strategy.CapturedEffectPreviewInputs,
) -> @publication.EffectPreviewIdentity {
  @strategy.captured_effect_preview_ledger_identity(value)
}

///|
#export_name("clientProgramEffectPreviewInputAt")
pub fn client_program_effect_preview_input_at(
  value : @strategy.CapturedEffectPreviewInputs,
  preview_index : Int,
) -> @strategy.CapturedEffectInput? {
  @strategy.captured_effect_preview_input_at(value, preview_index)
}

///|
/// Return the checked Plan associated with this live Preview input. The
/// terminal is opaque to Node and cannot be replaced by a caller-authored
/// Mapping rule or an equal-CID foreign Result.
#export_name("clientProgramEffectPreviewPlanTerminal")
pub fn client_program_effect_preview_plan_terminal(
  value : @strategy.CapturedEffectPreviewInputs,
  preview_index : Int,
  max_fields : Int,
  max_work : Int,
) -> Result[
  @effect_results.EffectPlanTerminal?,
  @strategy.CapturedEffectPlanIssue,
] {
  @strategy.captured_effect_preview_plan_terminal(
    value, preview_index, max_fields, max_work,
  )
}

///|
/// The Site supplies current authorized observations for every guarded row.
/// This checks the captured Preview but never issues mutation authority.
#export_name("clientProgramCheckEffectPreviewTargetGuards")
pub fn client_program_check_effect_preview_target_guards(
  value : @strategy.CapturedEffectPreviewInputs,
  row_cids : Array[String],
  version_cids : Array[String],
  max_rows : Int,
  max_work : Int,
) -> Result[Unit, @strategy.CapturedEffectGuardIssue] {
  if max_rows < 0 ||
    max_rows > 100000 ||
    max_work < 0 ||
    max_work > 100000000 ||
    row_cids.length() != version_cids.length() {
    return Err(@strategy.CapturedEffectGuardIssue::InvalidLimits)
  }
  if row_cids.length() > max_rows {
    return Err(
      @strategy.CapturedEffectGuardIssue::Current(
        @effect.EffectPreviewTargetGuardIssue::CapacityExceeded,
      ),
    )
  }
  let observations = Array::makei(row_cids.length(), index => @effect.EffectTargetVersionObservation::{
    row_preview_cid: row_cids[index],
    version_cid: version_cids[index],
  })
  @strategy.check_captured_effect_preview_target_guards(
    value, observations, max_rows, max_work,
  )
}

///|
/// The Host supplies current, authorized source, Contract, registration, and
/// grant observations for every member. Equality with the Preview is not
/// permission to mutate or evidence that the observations are authentic.
#export_name("clientProgramCheckEffectPreviewCurrentBindings")
pub fn client_program_check_effect_preview_current_bindings(
  value : @strategy.CapturedEffectPreviewInputs,
  source_binding_cids : Array[String],
  resolved_contract_cids : Array[String],
  capability_evidence_cids : Array[String],
  authority_scope_cids : Array[String],
  max_members : Int,
  max_work : Int,
) -> Result[Unit, @strategy.CapturedEffectCurrentBindingIssue] {
  @strategy.check_captured_effect_preview_current_bindings(
    value, source_binding_cids, resolved_contract_cids, capability_evidence_cids,
    authority_scope_cids, max_members, max_work,
  )
}

///|
/// Project an already authenticated registered route observation. Raw codes
/// supplied by a caller are not proof of a Connector capability or authority.
#export_name("clientProgramEffectApplyCapabilityFromCodes")
pub fn client_program_effect_apply_capability_from_codes(
  evidence_cid : String,
  route_code : Int,
  atomicity_code : Int,
  failure_code : Int,
  row_error_identity : Bool,
  request_order_preserved : Bool,
  idempotency_code : Int,
  reconciliation_code : Int,
) -> Result[
  @effect.EffectApplyCapabilityObservation,
  @effect.EffectApplyCapabilityIssue,
] {
  @effect.prepare_effect_apply_capability_from_codes(
    evidence_cid, route_code, atomicity_code, failure_code, row_error_identity, request_order_preserved,
    idempotency_code, reconciliation_code,
  )
}

///|
#export_name("clientProgramEffectApplyCapabilityIdempotencyMode")
pub fn client_program_effect_apply_capability_idempotency_mode(
  value : @effect.EffectApplyCapabilityObservation,
) -> String {
  @effect.effect_apply_capability_idempotency_mode(value)
}

///|
#export_name("clientProgramEffectApplyCapabilityReconciliationMode")
pub fn client_program_effect_apply_capability_reconciliation_mode(
  value : @effect.EffectApplyCapabilityObservation,
) -> String {
  @effect.effect_apply_capability_reconciliation_mode(value)
}

///|
/// Verify the selected execution route of every member against the captured
/// Preview's capability evidence and authored row policy before any send.
#export_name("clientProgramCheckEffectPreviewCapabilities")
pub fn client_program_check_effect_preview_capabilities(
  value : @strategy.CapturedEffectPreviewInputs,
  observations : Array[@effect.EffectApplyCapabilityObservation],
  max_members : Int,
  max_work : Int,
) -> Result[Unit, @strategy.CapturedEffectCapabilityIssue] {
  @strategy.check_captured_effect_preview_capabilities(
    value, observations, max_members, max_work,
  )
}

///|
/// Admit the canonical 0.1 risk body. This does not authenticate its issuer.
#export_name("clientProgramAdmitEffectRiskAcceptanceBody")
pub fn client_program_admit_effect_risk_acceptance_body(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@effect.EffectRiskAcceptanceBody, @effect.EffectRiskAcceptanceIssue] {
  @effect.admit_effect_risk_acceptance_body(
    wire, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// The unsigned canonical payload CID used by detached authentication.
#export_name("clientProgramEffectRiskUnsignedPayloadCid")
pub fn client_program_effect_risk_unsigned_payload_cid(
  body : @effect.EffectRiskAcceptanceBody,
) -> String {
  @effect.effect_risk_acceptance_unsigned_payload_cid(body)
}

///|
/// Compare Host-verified risk facts with the same live captured Preview.
/// The Host must first verify their authentication and current authority.
/// `require_partial_application` is the Host-declared delegated-decision
/// policy; member count alone never requires the risk claim.
#export_name("clientProgramCheckEffectRiskAcceptanceBody")
pub fn client_program_check_effect_risk_acceptance_body(
  preview : @strategy.CapturedEffectPreviewInputs,
  body : @effect.EffectRiskAcceptanceBody,
  review_projection_cid : String,
  authority_scope_cid : String,
  policy_cid : String,
  validity_evidence_cid : String,
  issuer_evidence_cid : String,
  authentication_evidence_cid : String,
  issuer_kind : String,
  decision : String,
  require_partial_application : Bool,
) -> Result[Unit, @strategy.CapturedEffectRiskIssue] {
  @strategy.check_captured_effect_risk_acceptance_body(
    preview, body, review_projection_cid, authority_scope_cid, policy_cid, validity_evidence_cid,
    issuer_evidence_cid, authentication_evidence_cid, issuer_kind, decision, require_partial_application,
  )
}

///|
/// Verify the complete derived key inventory using this captured Preview,
/// not another reading of its transported body. No mutation is authorized.
#export_name("clientProgramCheckEffectPreviewApplyKeys")
pub fn client_program_check_effect_preview_apply_keys(
  value : @strategy.CapturedEffectPreviewInputs,
  scope : @effect.LogicalRequestScope,
  keys : Array[Array[@effect.EffectDispatchKey]],
  max_rows : Int,
  max_work : Int,
) -> Result[Unit, @strategy.CapturedEffectApplyKeyIssue] {
  @strategy.check_captured_effect_preview_apply_keys(
    value, scope, keys, max_rows, max_work,
  )
}

///|
pub(all) enum ClientEffectPreviewAuthorIssue {
  Preview(@publication.EffectPreviewIdentityIssue)
  Dispatch(@effect.EffectIdentityIssue)
  Keys(@effect.EffectPreviewApplyIdentityIssue)
  CapacityExceeded
} derive(Debug)

///|
/// Canonicalize a schema-closed draft before MoonBit seals its identities.
/// This is an encoding operation, not Preview or apply admission.
#export_name("clientProgramCanonicalEffectPreviewDraft")
pub fn client_program_canonical_effect_preview_draft(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @publication.PublicationContractIssue] {
  @publication.canonical_effect_preview_draft_wire(
    wire, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Bind Preview authoring to the authority already owned by the logical
/// request. This does not authenticate that authority or grant an apply permit.
#export_name("clientProgramEffectRequestAuthority")
pub fn client_program_effect_request_authority(
  scope : @effect.LogicalRequestScope,
) -> String {
  @effect.logical_request_scope_authority(scope)
}

///|
/// Derive the checked source Result's Preview binding from its issued
/// Artifact, not from an unowned CID supplied to the Host adapter.
#export_name("clientProgramEffectSourceArtifactPreviewBinding")
pub fn client_program_effect_source_artifact_preview_binding(
  artifact : @publication.PublicationContract,
  invocation_cid : String,
  source_result : String,
  store_authority_cid : String,
) -> Result[(String, String), @publication.EffectSourceArtifactIssue] {
  @publication.effect_source_artifact_preview_binding(
    artifact, invocation_cid, source_result, store_authority_cid,
  )
}

///|
/// Seal row, member and set identities before deriving non-semantic dispatch
/// keys. This only authors a private Preview wire; checked Run binding,
/// current authority and apply permission remain separate obligations.
#export_name("clientProgramAuthorEffectPreview")
pub fn client_program_author_effect_preview(
  template_wire : String,
  expected_run_identity_cid : String,
  expected_authoring_context_cid : String,
  request_scope : @effect.LogicalRequestScope,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_members : Int,
  max_rows : Int,
  max_key_bytes : Int,
  max_key_nodes : Int,
  max_key_depth : Int,
) -> Result[
  (String, Array[Array[@effect.EffectDispatchKey]]),
  ClientEffectPreviewAuthorIssue,
] {
  let (semantic_wire, identity) = match
    @publication.author_effect_preview_semantic_wire(
      template_wire, expected_run_identity_cid, expected_authoring_context_cid, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preview(issue))
  }
  let count = @publication.effect_preview_member_count(identity)
  if max_members < 1 || max_rows < 0 || count > max_members {
    return Err(CapacityExceeded)
  }
  let preview_cid = @publication.effect_preview_semantic_identity(identity)
  let keys : Array[Array[@effect.EffectDispatchKey]] = []
  let key_cids : Array[Array[String]] = []
  let mut remaining = max_rows
  for member_index in 0..<count {
    let row_count = @publication.effect_preview_row_count(
      identity, member_index,
    ).unwrap()
    if row_count > remaining {
      return Err(CapacityExceeded)
    }
    remaining -= row_count
    let member_keys : Array[@effect.EffectDispatchKey] = []
    let member_key_cids : Array[String] = []
    for row_index in 0..<row_count {
      let correlation = @publication.effect_preview_row_correlation_wire(
        identity, member_index, row_index,
      ).unwrap()
      let key = match
        @effect.prepare_effect_dispatch_key(
          request_scope, preview_cid, correlation, max_key_bytes, max_key_nodes,
          max_key_depth,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Dispatch(issue))
      }
      member_key_cids.push(@effect.effect_dispatch_key_cid(key))
      member_keys.push(key)
    }
    keys.push(member_keys)
    key_cids.push(member_key_cids)
  }
  let wire = match
    @publication.complete_effect_preview_dispatch_keys(
      semantic_wire, key_cids, expected_run_identity_cid, expected_authoring_context_cid,
      max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preview(issue))
  }
  match
    @effect.admit_effect_preview_apply_identity(
      wire, expected_run_identity_cid, expected_authoring_context_cid, request_scope,
      keys, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => Ok((wire, keys))
    Err(issue) => Err(Keys(issue))
  }
}

///|
/// Return the common canonical create-row order and distinct correlation for
/// every source row. This does not authorize a write or read a physical body.
#export_name("clientProgramEffectCreateRowInventory")
pub fn client_program_effect_create_row_inventory(
  after_wires : Array[String],
  max_rows : Int,
  max_total_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[(Int, String)], @publication.EffectPreviewIdentityIssue] {
  @publication.derive_effect_create_row_inventory(
    after_wires, max_rows, max_total_bytes, max_nodes, max_depth,
  )
}

///|
/// Sealed Effect Set Preview identity of the live captured Preview: the
/// decision subject the Host binds at the Effect commit boundary.
#export_name("clientProgramEffectApplySubjectCid")
pub fn client_program_effect_apply_subject_cid(
  preview : @strategy.CapturedEffectPreviewInputs,
) -> String? {
  @strategy.captured_effect_preview_subject_cid(preview)
}

///|
/// Member count of the live captured Preview.
#export_name("clientProgramEffectApplyMemberCount")
pub fn client_program_effect_apply_member_count(
  preview : @strategy.CapturedEffectPreviewInputs,
) -> Int? {
  @strategy.captured_effect_preview_member_count(preview)
}

///|
/// Check the complete semantic preflight on one captured Preview owner.
/// The Host must independently authenticate all current facts and claim the
/// physical send through its durable Effect ledger before any mutation.
/// `risk` is absent (`undefined`) when the Host holds no risk-acceptance
/// body; it is required only under `require_partial_application`.
#export_name("clientProgramCheckEffectApplyPreflight")
pub fn client_program_check_effect_apply_preflight(
  preview : @strategy.CapturedEffectPreviewInputs,
  proofs : Array[@strategy.CapturedEffectPlanProof],
  source_binding_cids : Array[String],
  resolved_contract_cids : Array[String],
  capability_evidence_cids : Array[String],
  authority_scope_cids : Array[String],
  guard_row_cids : Array[String],
  guard_version_cids : Array[String],
  routes : Array[@effect.EffectApplyCapabilityObservation],
  risk : @effect.EffectRiskAcceptanceBody?,
  require_partial_application : Bool,
  review_projection_cid : String,
  risk_authority_scope_cid : String,
  policy_cid : String,
  validity_evidence_cid : String,
  issuer_evidence_cid : String,
  authentication_evidence_cid : String,
  issuer_kind : String,
  decision : String,
  request_scope : @effect.LogicalRequestScope,
  keys : Array[Array[@effect.EffectDispatchKey]],
  max_members : Int,
  max_rows : Int,
  max_targets : Int,
  max_work : Int,
) -> Result[Unit, @strategy.CapturedEffectApplyPreflightIssue] {
  if guard_row_cids.length() != guard_version_cids.length() ||
    guard_row_cids.length() > max_rows {
    return Err(
      @strategy.CapturedEffectApplyPreflightIssue::Guard(
        @strategy.CapturedEffectGuardIssue::InvalidLimits,
      ),
    )
  }
  let guards = Array::makei(guard_row_cids.length(), index => @effect.EffectTargetVersionObservation::{
    row_preview_cid: guard_row_cids[index],
    version_cid: guard_version_cids[index],
  })
  @strategy.check_captured_effect_apply_preflight(
    preview, proofs, source_binding_cids, resolved_contract_cids, capability_evidence_cids,
    authority_scope_cids, guards, routes, risk, require_partial_application, review_projection_cid,
    risk_authority_scope_cid, policy_cid, validity_evidence_cid, issuer_evidence_cid,
    authentication_evidence_cid, issuer_kind, decision, request_scope, keys, max_members,
    max_rows, max_targets, max_work,
  )
}

///|
/// Apply the same semantic checks to an admitted recovered Preview. The
/// recovered capture, prior Plan proof, current Store holding, and Site
/// authority must be established separately before any physical send.
#export_name("clientProgramCheckRecoveredEffectApplySemantics")
pub fn client_program_check_recovered_effect_apply_semantics(
  preview : @publication.EffectPreviewIdentity,
  recovered_guards : @effect.RecoveredEffectTargetGuards,
  source_binding_cids : Array[String],
  resolved_contract_cids : Array[String],
  capability_evidence_cids : Array[String],
  authority_scope_cids : Array[String],
  guard_row_cids : Array[String],
  guard_version_cids : Array[String],
  routes : Array[@effect.EffectApplyCapabilityObservation],
  risk : @effect.EffectRiskAcceptanceBody?,
  require_partial_application : Bool,
  review_projection_cid : String,
  risk_authority_scope_cid : String,
  policy_cid : String,
  validity_evidence_cid : String,
  issuer_evidence_cid : String,
  authentication_evidence_cid : String,
  issuer_kind : String,
  decision : String,
  request_scope : @effect.LogicalRequestScope,
  keys : Array[Array[@effect.EffectDispatchKey]],
  max_members : Int,
  max_rows : Int,
  max_targets : Int,
  max_work : Int,
) -> Result[Unit, @strategy.CapturedEffectApplyPreflightIssue] {
  if guard_row_cids.length() != guard_version_cids.length() ||
    guard_row_cids.length() > max_rows {
    return Err(
      @strategy.CapturedEffectApplyPreflightIssue::Guard(
        @strategy.CapturedEffectGuardIssue::InvalidLimits,
      ),
    )
  }
  let guards = Array::makei(guard_row_cids.length(), index => @effect.EffectTargetVersionObservation::{
    row_preview_cid: guard_row_cids[index],
    version_cid: guard_version_cids[index],
  })
  @strategy.check_effect_preview_apply_semantics(
    preview,
    source_binding_cids,
    resolved_contract_cids,
    capability_evidence_cids,
    authority_scope_cids,
    guards,
    routes,
    risk,
    require_partial_application,
    review_projection_cid,
    risk_authority_scope_cid,
    policy_cid,
    validity_evidence_cid,
    issuer_evidence_cid,
    authentication_evidence_cid,
    issuer_kind,
    decision,
    request_scope,
    keys,
    max_members,
    max_rows,
    max_targets,
    max_work,
    recovery_guards=recovered_guards,
  )
}

///|
#export_name("clientProgramRecoverEffectTargetGuards")
pub fn client_program_recover_effect_target_guards(
  preview : @publication.EffectPreviewIdentity,
  scopes : Array[Array[@effect.LogicalRequestScope]],
  locators : Array[Array[@effect.LogicalItemLocator]],
  keys : Array[Array[@effect.EffectDispatchKey]],
  bases : Array[Array[@effect.EffectLedgerBasis]],
  heads : Array[Array[@effect.EffectLedgerEntry?]],
  active_owners : Array[Array[Bool]],
  max_members : Int,
  max_rows : Int,
  max_work : Int,
) -> Result[@effect.RecoveredEffectTargetGuards, @effect.EffectSetProgressIssue] {
  @effect.recover_effect_target_guards(
    preview, scopes, locators, keys, bases, heads, active_owners, max_members, max_rows,
    max_work,
  )
}

///|
/// Exact Host limits for the checked Effect input stream, shared by cell and
/// resident representations. These limits do not grant access or apply.
#export_name("clientProgramEffectInputExportLimits")
pub fn client_program_effect_input_export_limits(
  max_result_fields : Int,
  max_result_mapping_work : Int,
  max_result_order_work : Int,
  max_result_workspace_entries : Int,
  max_rows : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
  max_value_depth : Int,
  max_value_work : Int,
  max_wire_bytes : Int,
  max_wire_nodes : Int,
  max_wire_depth : Int,
  max_columns : Int,
  max_order_work : Int,
  max_logical_wire_bytes : Int,
  max_logical_wire_nodes : Int,
  max_logical_wire_depth : Int,
  max_schema_fields : Int,
  max_schema_bytes : Int,
  max_schema_nodes : Int,
  max_schema_depth : Int,
  max_batch_bytes : Int,
) -> @publication_host.PublicationOutputExportLimits? {
  if max_result_fields < 0 ||
    max_result_mapping_work < 0 ||
    max_result_order_work < 0 ||
    max_result_workspace_entries < 0 ||
    max_rows < 0 ||
    max_value_nodes < 0 ||
    max_value_text_bytes < 0 ||
    max_value_depth < 0 ||
    max_value_work < 0 ||
    max_wire_bytes < 0 ||
    max_wire_nodes < 0 ||
    max_wire_depth < 0 ||
    max_columns < 0 ||
    max_order_work < 0 ||
    max_logical_wire_bytes < 0 ||
    max_logical_wire_nodes < 0 ||
    max_logical_wire_depth < 0 ||
    max_schema_fields < 0 ||
    max_schema_bytes < 0 ||
    max_schema_nodes < 0 ||
    max_schema_depth < 0 ||
    max_batch_bytes < 0 {
    return None
  }
  Some({
    max_result_fields,
    max_result_mapping_work,
    max_result_order_work,
    max_result_workspace_entries,
    max_rows,
    values: {
      max_nodes: max_value_nodes,
      max_text_bytes: max_value_text_bytes,
      max_depth: max_value_depth,
      max_work: max_value_work,
    },
    payload_wire: {
      max_columns,
      max_order_work,
      max_bytes: max_wire_bytes,
      max_nodes: max_wire_nodes,
      max_depth: max_wire_depth,
    },
    logical_wire: {
      max_columns,
      max_order_work,
      max_bytes: max_logical_wire_bytes,
      max_nodes: max_logical_wire_nodes,
      max_depth: max_logical_wire_depth,
    },
    schema: {
      max_fields: max_schema_fields,
      max_bytes: max_schema_bytes,
      max_nodes: max_schema_nodes,
      max_depth: max_schema_depth,
    },
    max_batch_bytes,
  })
}

///|
/// Start the common bounded checked Result view. No caller-supplied rows,
/// projection, order, or payload can replace this retained Effect source.
#export_name("clientProgramEffectInputExportStart")
pub fn client_program_effect_input_export_start(
  input : @strategy.CapturedEffectInput,
  limits : @publication_host.PublicationOutputExportLimits,
) -> Result[
  @execution.CompletedResultRelationExportPreparation,
  @execution.CompletedExportIssue,
] {
  @strategy.start_captured_effect_input_export(
    input,
    {
      max_fields: limits.max_result_fields,
      max_mapping_work: limits.max_result_mapping_work,
      max_order_work: limits.max_result_order_work,
      max_workspace_entries: limits.max_result_workspace_entries,
    },
    limits.max_rows,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  )
}

///|
#export_name("clientProgramEffectLocalResultExportStart")
pub fn client_program_effect_local_result_export_start(
  inputs : @strategy.CapturedEffectInputs,
  index : Int,
  limits : @publication_host.PublicationOutputExportLimits,
) -> Result[
  @strategy.CapturedEffectLocalResultExport,
  @strategy.CapturedEffectLocalResultExportIssue,
] {
  let limits = client_program_own_effect_export_limits(limits)
  @strategy.start_captured_effect_local_result_export(
    inputs,
    index,
    {
      max_fields: limits.max_result_fields,
      max_mapping_work: limits.max_result_mapping_work,
      max_order_work: limits.max_result_order_work,
      max_workspace_entries: limits.max_result_workspace_entries,
    },
    limits.max_rows,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  )
}

///|
#export_name("clientProgramEffectLocalResultExportPreparation")
pub fn client_program_effect_local_result_export_preparation(
  value : @strategy.CapturedEffectLocalResultExport,
) -> @execution.CompletedResultRelationExportPreparation {
  @strategy.captured_effect_local_result_export_preparation(value)
}

///|
#export_name("clientProgramEffectLocalResultExportMatchesReceipt")
pub fn client_program_effect_local_result_export_matches_receipt(
  inputs : @strategy.CapturedEffectInputs,
  value : @strategy.CapturedEffectLocalResultExport,
  receipt : @execution.CompletedRelationExportReceipt,
) -> Bool {
  @strategy.captured_effect_local_result_export_matches_receipt(
    inputs, value, receipt,
  )
}

///|
/// The installed Site supplies the exact resident generation and bounded row
/// stream. This owner keeps its checked Effect pin and managed import paired.
struct ClientEffectManagedInputImport {
  input : @strategy.CapturedEffectInput?
  borrow : @strategy.CapturedAnyResultBorrow
  output : @execution.ManagedCompletedOutput[Int]
  bridge : @execution.ManagedPublicationBridge[Int]
  limits : @publication_host.PublicationOutputExportLimits
  mut preparation : @execution.CompletedResultRelationExportPreparation?
  mut open : Bool
}

///|
/// Own scalar limits before the physical reader can await or call back.
fn client_program_own_effect_export_limits(
  limits : @publication_host.PublicationOutputExportLimits,
) -> @publication_host.PublicationOutputExportLimits {
  {
    max_result_fields: limits.max_result_fields,
    max_result_mapping_work: limits.max_result_mapping_work,
    max_result_order_work: limits.max_result_order_work,
    max_result_workspace_entries: limits.max_result_workspace_entries,
    max_rows: limits.max_rows,
    values: {
      max_nodes: limits.values.max_nodes,
      max_text_bytes: limits.values.max_text_bytes,
      max_depth: limits.values.max_depth,
      max_work: limits.values.max_work,
    },
    payload_wire: {
      max_columns: limits.payload_wire.max_columns,
      max_order_work: limits.payload_wire.max_order_work,
      max_bytes: limits.payload_wire.max_bytes,
      max_nodes: limits.payload_wire.max_nodes,
      max_depth: limits.payload_wire.max_depth,
    },
    logical_wire: {
      max_columns: limits.logical_wire.max_columns,
      max_order_work: limits.logical_wire.max_order_work,
      max_bytes: limits.logical_wire.max_bytes,
      max_nodes: limits.logical_wire.max_nodes,
      max_depth: limits.logical_wire.max_depth,
    },
    schema: {
      max_fields: limits.schema.max_fields,
      max_bytes: limits.schema.max_bytes,
      max_nodes: limits.schema.max_nodes,
      max_depth: limits.schema.max_depth,
    },
    max_batch_bytes: limits.max_batch_bytes,
  }
}

///|
pub(all) enum ClientEffectManagedInputIssue {
  ForeignOutput
  Closed
  Bridge(@execution.ManagedProducerBridgeIssue)
  Export(@execution.CompletedExportIssue)
}

///|
#export_name("clientProgramEffectManagedInputBegin")
pub fn client_program_effect_managed_input_begin(
  input : @strategy.CapturedEffectInput,
  output : @execution.ManagedCompletedOutput[Int],
  material : @execution.ManagedRetainedOutput[Int],
  limits : @publication_host.PublicationOutputExportLimits,
) -> Result[ClientEffectManagedInputImport, ClientEffectManagedInputIssue] {
  begin_client_effect_result_import(
    Some(input),
    @strategy.captured_effect_input_borrow(input),
    output,
    material,
    limits,
  )
}

///|
#export_name("clientProgramEffectLocalManagedInputBegin")
pub fn client_program_effect_local_managed_input_begin(
  inputs : @strategy.CapturedEffectInputs,
  index : Int,
  output : @execution.ManagedCompletedOutput[Int],
  material : @execution.ManagedRetainedOutput[Int],
  limits : @publication_host.PublicationOutputExportLimits,
) -> Result[ClientEffectManagedInputImport, ClientEffectManagedInputIssue] {
  guard @strategy.captured_effect_local_result_at(inputs, index) is Some(result) else {
    return Err(ForeignOutput)
  }
  begin_client_effect_result_import(
    None,
    @strategy.captured_effect_local_result_borrow(result),
    output,
    material,
    limits,
  )
}

///|
fn begin_client_effect_result_import(
  input : @strategy.CapturedEffectInput?,
  borrow : @strategy.CapturedAnyResultBorrow,
  output : @execution.ManagedCompletedOutput[Int],
  material : @execution.ManagedRetainedOutput[Int],
  limits : @publication_host.PublicationOutputExportLimits,
) -> Result[ClientEffectManagedInputImport, ClientEffectManagedInputIssue] {
  if !@strategy.captured_any_result_borrow_matches_managed(borrow, output) {
    return Err(ForeignOutput)
  }
  let limits = client_program_own_effect_export_limits(limits)
  let bridge = match
    @execution.prepare_managed_publication_bridge(
      output,
      material,
      limits.max_rows,
      limits.values,
      limits.max_result_workspace_entries,
      limits.schema.max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Bridge(issue))
  }
  Ok({ input, borrow, output, bridge, limits, preparation: None, open: true, })
}

///|
#export_name("clientProgramEffectLocalManagedExportOwner")
pub fn client_program_effect_local_managed_export_owner(
  inputs : @strategy.CapturedEffectInputs,
  index : Int,
  value : ClientEffectManagedInputImport,
) -> Result[
  @strategy.CapturedEffectLocalResultExport,
  @strategy.CapturedEffectLocalResultExportIssue,
] {
  guard value.preparation is Some(preparation) else {
    return Err(ForeignOutput)
  }
  @strategy.bind_captured_effect_local_result_managed_export(
    inputs,
    index,
    value.output,
    value.bridge,
    preparation,
  )
}

///|
#export_name("clientProgramEffectManagedInputAppend")
pub fn client_program_effect_managed_input_append(
  value : ClientEffectManagedInputImport,
  row : String,
) -> Result[Unit, ClientEffectManagedInputIssue] {
  if !value.open {
    return Err(Closed)
  }
  if !@strategy.captured_any_result_borrow_matches_managed(
      value.borrow,
      value.output,
    ) {
    return Err(ForeignOutput)
  }
  @execution.append_managed_publication_bridge_wire(value.bridge, row, {
    max_bytes: value.limits.payload_wire.max_bytes,
    max_nodes: value.limits.payload_wire.max_nodes,
    max_depth: value.limits.payload_wire.max_depth,
    max_text_bytes: value.limits.values.max_text_bytes,
  }).map_err(issue => Bridge(issue))
}

///|
#export_name("clientProgramEffectManagedInputFinish")
pub fn client_program_effect_managed_input_finish(
  value : ClientEffectManagedInputImport,
) -> Result[
  @execution.CompletedResultRelationExportPreparation,
  ClientEffectManagedInputIssue,
] {
  if !value.open {
    return Err(Closed)
  }
  value.open = false
  if !@strategy.captured_any_result_borrow_matches_managed(
      value.borrow,
      value.output,
    ) {
    @execution.close_managed_publication_bridge(value.bridge)
    return Err(ForeignOutput)
  }
  let output = match
    @execution.finish_managed_publication_bridge(value.bridge) {
    Ok(value) => value
    Err(issue) => {
      @execution.close_managed_publication_bridge(value.bridge)
      return Err(Bridge(issue))
    }
  }
  match
    @execution.start_completed_result_relation_export(
      output,
      @strategy.captured_any_result_borrow_occurrence(value.borrow),
      {
        max_fields: value.limits.max_result_fields,
        max_mapping_work: value.limits.max_result_mapping_work,
        max_order_work: value.limits.max_result_order_work,
        max_workspace_entries: value.limits.max_result_workspace_entries,
      },
      value.limits.max_rows,
      value.limits.values,
      value.limits.payload_wire,
      value.limits.logical_wire,
      value.limits.schema,
      value.limits.max_batch_bytes,
    ) {
    Ok(preparation) => {
      value.preparation = Some(preparation)
      Ok(preparation)
    }
    Err(issue) => {
      @execution.close_managed_publication_bridge(value.bridge)
      Err(Export(issue))
    }
  }
}

///|
#export_name("clientProgramEffectManagedInputCancel")
pub fn client_program_effect_managed_input_cancel(
  value : ClientEffectManagedInputImport,
) -> Unit {
  value.open = false
  value.preparation = None
  @execution.close_managed_publication_bridge(value.bridge)
}

///|
#export_name("clientProgramEffectInputExportAdvance")
pub fn client_program_effect_input_export_advance(
  value : @execution.CompletedResultRelationExportPreparation,
  quantum : Int,
) -> Result[(Bool, Int), @execution.CompletedExportIssue] {
  @execution.advance_completed_result_relation_export(value, quantum)
}

///|
#export_name("clientProgramEffectInputExportReady")
pub fn client_program_effect_input_export_ready(
  value : @execution.CompletedResultRelationExportPreparation,
) -> Result[@execution.CompletedOutputExport, @execution.CompletedExportIssue] {
  @execution.finish_completed_result_relation_export_preparation(value)
}

///|
#export_name("clientProgramEffectInputExportNext")
pub fn client_program_effect_input_export_next(
  value : @execution.CompletedOutputExport,
) -> Result[String?, @execution.CompletedExportIssue] {
  @execution.next_completed_output_export(value)
}

///|
/// Return one canonical checked Result row alongside the export's original
/// bytes. The physical adapter must not reconstruct a separate row view.
#export_name("clientProgramEffectInputExportNextCanonicalRow")
pub fn client_program_effect_input_export_next_canonical_row(
  value : @execution.CompletedOutputExport,
  max_nodes : Int,
  max_depth : Int,
  max_utf16_units : Int,
) -> Result[
  (Int, String, @identity.CanonicalValue)?,
  @execution.CompletedExportIssue,
] {
  @execution.next_completed_output_export_canonical_row(
    value, max_nodes, max_depth, max_utf16_units,
  )
}

///|
/// Select one checked member Plan before authoring a private Preview. The
/// caller must feed its canonical rows from the same bounded Result export.
#export_name("clientProgramEffectProposalBegin")
pub fn client_program_effect_proposal_begin(
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  max_fields : Int,
  max_work : Int,
) -> Result[
  @strategy.CapturedEffectProposalPlan,
  @strategy.CapturedEffectProposalIssue,
] {
  @strategy.prepare_captured_effect_proposal_plan(
    inputs, member_index, max_fields, max_work,
  )
}

///|
/// The returned selector and changes are proposals, not a payload proof or
/// Effect send permit; Preview binding later verifies the captured input.
#export_name("clientProgramEffectProposalRow")
pub fn client_program_effect_proposal_row(
  value : @strategy.CapturedEffectProposalPlan,
  row : @identity.CanonicalValue,
  row_index : Int,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(String, String), @strategy.CapturedEffectProposalIssue] {
  @strategy.project_captured_effect_proposal_row(
    value, row, row_index, max_fields, max_work, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramEffectProposalFinish")
pub fn client_program_effect_proposal_finish(
  value : @strategy.CapturedEffectProposalPlan,
  row_count : Int,
) -> Result[Unit, @strategy.CapturedEffectProposalIssue] {
  @strategy.finish_captured_effect_proposal_plan(value, row_count)
}

///|
#export_name("clientProgramEffectProposalCancel")
pub fn client_program_effect_proposal_cancel(
  value : @strategy.CapturedEffectProposalPlan,
) -> Unit {
  @strategy.cancel_captured_effect_proposal_plan(value)
}

///|
#export_name("clientProgramEffectInputExportFinish")
pub fn client_program_effect_input_export_finish(
  value : @execution.CompletedOutputExport,
) -> Result[
  (@execution.CompletedRelationExportReceipt, String),
  @execution.CompletedExportIssue,
] {
  @execution.finish_completed_relation_export(value)
}

///|
#export_name("clientProgramEffectInputExportLogicalCid")
pub fn client_program_effect_input_export_logical_cid(
  receipt : @execution.CompletedRelationExportReceipt,
) -> String {
  @execution.logical_relation_cid(
    @execution.completed_relation_export_identity(receipt),
  )
}

///|
#export_name("clientProgramEffectInputExportFields")
pub fn client_program_effect_input_export_fields(
  receipt : @execution.CompletedRelationExportReceipt,
) -> Array[String] {
  @execution.completed_relation_export_field_names(receipt)
}

///|
#export_name("clientProgramEffectInputExportSchemaCid")
pub fn client_program_effect_input_export_schema_cid(
  receipt : @execution.CompletedRelationExportReceipt,
) -> String {
  @execution.relation_schema_cid(
    @execution.completed_relation_export_schema_identity(receipt),
  )
}

///|
#export_name("clientProgramEffectInputExportRowCount")
pub fn client_program_effect_input_export_row_count(
  receipt : @execution.CompletedRelationExportReceipt,
) -> Int {
  @execution.completed_relation_export_measurement(receipt).row_count
}

///|
#export_name("clientProgramEffectInputExportSchemaWire")
pub fn client_program_effect_input_export_schema_wire(
  receipt : @execution.CompletedRelationExportReceipt,
) -> String {
  @execution.relation_schema_wire(
    @execution.completed_relation_export_schema_identity(receipt),
  )
}

///|
/// Issue source evidence from the pinned checked occurrence and the completed
/// export receipt. Store custody is still a separate adapter obligation.
#export_name("clientProgramIssueEffectSourceArtifact")
pub fn client_program_issue_effect_source_artifact(
  input : @strategy.CapturedEffectInput,
  receipt : @execution.CompletedRelationExportReceipt,
  invocation : @publication.PublicationContract,
  retention : @publication.PublicationContract,
  source_binding_cid : String,
  store_authority_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  @publication.EffectSourceArtifactIssue,
] {
  @publication.issue_effect_source_artifact(
    invocation,
    retention,
    @execution.managed_result_occurrence_name(
      @strategy.captured_effect_input_occurrence(input),
    ),
    source_binding_cid,
    store_authority_cid,
    client_program_effect_input_export_logical_cid(receipt),
    client_program_effect_input_export_schema_cid(receipt),
    client_program_effect_input_export_row_count(receipt),
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
#export_name("clientProgramEffectInputExportReleaseReceipt")
pub fn client_program_effect_input_export_release_receipt(
  receipt : @execution.CompletedRelationExportReceipt,
) -> Unit {
  @execution.cancel_completed_relation_export_receipt(receipt)
}

///|
#export_name("clientProgramEffectInputExportCancelPreparation")
pub fn client_program_effect_input_export_cancel_preparation(
  value : @execution.CompletedResultRelationExportPreparation,
) -> Bool {
  @execution.cancel_completed_result_relation_export(value)
}

///|
#export_name("clientProgramEffectInputExportCancel")
pub fn client_program_effect_input_export_cancel(
  value : @execution.CompletedOutputExport,
) -> Unit {
  @execution.cancel_completed_output_export(value)
}

///|
/// Keep the private Preview, checked Plan, and managed Result import under one
/// owner. Physical rows enter through the same generation-checked bridge as
/// publication. This owner cannot authorize an Effect send.
struct ClientEffectPlanImport {
  preview : @strategy.CapturedEffectPreviewInputs
  preview_index : Int
  verifier : @strategy.CapturedEffectPlanVerifier
  importing : ClientEffectManagedInputImport
  mut open : Bool
}

///|
struct ClientEffectPlanPreparation {
  owner : ClientEffectPlanImport
  preparation : @execution.CompletedResultRelationExportPreparation
}

///|
struct ClientEffectPlanCursor {
  owner : ClientEffectPlanImport
  stream : @execution.CompletedOutputExport
  mut exhausted : Bool
  mut closed : Bool
}

///|
fn client_effect_plan_poison(value : ClientEffectPlanCursor) -> Unit {
  value.closed = true
  @strategy.cancel_captured_effect_plan_verifier(value.owner.verifier)
  @execution.cancel_completed_output_export(value.stream)
  client_program_effect_managed_input_cancel(value.owner.importing)
}

///|
pub(all) enum ClientEffectPlanStreamIssue {
  InvalidMember
  NotReady
  Closed
  Plan(@strategy.CapturedEffectPlanVerifyIssue)
  Import(ClientEffectManagedInputIssue)
  Export(@execution.CompletedExportIssue)
}

///|
/// A caller may choose which admitted Preview member to inspect, but cannot
/// substitute a Plan, source Result, or physical generation.
#export_name("clientProgramEffectPlanImportBegin")
pub fn client_program_effect_plan_import_begin(
  preview : @strategy.CapturedEffectPreviewInputs,
  preview_index : Int,
  output : @execution.ManagedCompletedOutput[Int],
  material : @execution.ManagedRetainedOutput[Int],
  limits : @publication_host.PublicationOutputExportLimits,
  max_fields : Int,
  max_work : Int,
) -> Result[ClientEffectPlanImport, ClientEffectPlanStreamIssue] {
  guard @strategy.captured_effect_preview_input_at(preview, preview_index)
    is Some(input) else {
    return Err(InvalidMember)
  }
  let verifier = match
    @strategy.prepare_captured_effect_plan_verifier(
      preview, preview_index, max_fields, max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Plan(issue))
  }
  let importing = match
    client_program_effect_managed_input_begin(input, output, material, limits) {
    Ok(value) => value
    Err(issue) => return Err(Import(issue))
  }
  Ok({ preview, preview_index, verifier, importing, open: true, })
}

///|
#export_name("clientProgramEffectPlanImportAppend")
pub fn client_program_effect_plan_import_append(
  value : ClientEffectPlanImport,
  row : String,
) -> Result[Unit, ClientEffectPlanStreamIssue] {
  if !value.open {
    return Err(Closed)
  }
  client_program_effect_managed_input_append(value.importing, row).map_err(issue => {
    Import(issue)
  })
}

///|
#export_name("clientProgramEffectPlanImportFinish")
pub fn client_program_effect_plan_import_finish(
  value : ClientEffectPlanImport,
) -> Result[ClientEffectPlanPreparation, ClientEffectPlanStreamIssue] {
  if !value.open {
    return Err(Closed)
  }
  value.open = false
  client_program_effect_managed_input_finish(value.importing)
  .map(preparation => { owner: value, preparation, })
  .map_err(issue => Import(issue))
}

///|
#export_name("clientProgramEffectPlanAdvance")
pub fn client_program_effect_plan_advance(
  value : ClientEffectPlanPreparation,
  quantum : Int,
) -> Result[(Bool, Int), ClientEffectPlanStreamIssue] {
  @execution.advance_completed_result_relation_export(
    value.preparation,
    quantum,
  ).map_err(issue => Export(issue))
}

///|
#export_name("clientProgramEffectPlanReady")
pub fn client_program_effect_plan_ready(
  value : ClientEffectPlanPreparation,
) -> Result[ClientEffectPlanCursor, ClientEffectPlanStreamIssue] {
  let stream = match
    @execution.finish_completed_result_relation_export_preparation(
      value.preparation,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Export(issue))
  }
  Ok({ owner: value.owner, stream, exhausted: false, closed: false, })
}

///|
/// Return publication bytes only after their checked Plan changes match the
/// private Preview at the same source-row position. The cursor consumes one
/// bounded canonical row at a time; Node never rebuilds the full Relation.
#export_name("clientProgramEffectPlanNext")
pub fn client_program_effect_plan_next(
  value : ClientEffectPlanCursor,
  max_nodes : Int,
  max_depth : Int,
  max_utf16_units : Int,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
) -> Result[String?, ClientEffectPlanStreamIssue] {
  if value.closed || value.exhausted {
    return Err(Closed)
  }
  if @strategy.captured_effect_preview_input_at(
      value.owner.preview,
      value.owner.preview_index,
    )
    is None {
    client_effect_plan_poison(value)
    return Err(NotReady)
  }
  let next = match
    @execution.next_completed_output_export_canonical_row(
      value.stream,
      max_nodes,
      max_depth,
      max_utf16_units,
    ) {
    Ok(Some(row)) => row
    Ok(None) => {
      value.exhausted = true
      return Ok(None)
    }
    Err(issue) => {
      client_effect_plan_poison(value)
      return Err(Export(issue))
    }
  }
  let (index, batch, row) = next
  match
    @strategy.check_captured_effect_plan_row(
      value.owner.verifier,
      row,
      index,
      max_fields,
      max_work,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => {
      client_effect_plan_poison(value)
      return Err(Plan(issue))
    }
  }
  Ok(Some(batch))
}

///|
/// Exhaustion and exact row count are required before a relation receipt can
/// be returned. Target correlation, current guards, and apply remain separate.
#export_name("clientProgramEffectPlanFinish")
pub fn client_program_effect_plan_finish(
  value : ClientEffectPlanCursor,
) -> Result[
  (
    @execution.CompletedRelationExportReceipt,
    String,
    @strategy.CapturedEffectPlanProof,
  ),
  ClientEffectPlanStreamIssue,
] {
  if value.closed || !value.exhausted {
    return Err(Closed)
  }
  if @strategy.captured_effect_preview_input_at(
      value.owner.preview,
      value.owner.preview_index,
    )
    is None {
    client_effect_plan_poison(value)
    return Err(NotReady)
  }
  let proof = match
    @strategy.finish_captured_effect_plan_verifier(value.owner.verifier) {
    Ok(proof) => proof
    Err(issue) => {
      client_effect_plan_poison(value)
      return Err(Plan(issue))
    }
  }
  let pair = match @execution.finish_completed_relation_export(value.stream) {
    Ok(pair) => pair
    Err(issue) => {
      client_effect_plan_poison(value)
      return Err(Export(issue))
    }
  }
  value.closed = true
  guard @strategy.captured_effect_preview_input_at(
      value.owner.preview,
      value.owner.preview_index,
    )
    is Some(_) else {
    @execution.cancel_completed_relation_export_receipt(pair.0)
    return Err(NotReady)
  }
  Ok((pair.0, pair.1, proof))
}

///|
#export_name("clientProgramEffectPlanProofMatches")
pub fn client_program_effect_plan_proof_matches(
  proof : @strategy.CapturedEffectPlanProof,
  preview : @strategy.CapturedEffectPreviewInputs,
  preview_index : Int,
) -> Bool {
  @strategy.captured_effect_plan_proof_matches(proof, preview, preview_index)
}

///|
#export_name("clientProgramCheckEffectPlanProofs")
pub fn client_program_check_effect_plan_proofs(
  preview : @strategy.CapturedEffectPreviewInputs,
  proofs : Array[@strategy.CapturedEffectPlanProof],
  max_members : Int,
  max_work : Int,
) -> Result[Unit, @strategy.CapturedEffectPlanInventoryIssue] {
  @strategy.check_captured_effect_plan_proofs(
    preview, proofs, max_members, max_work,
  )
}

///|
#export_name("clientProgramEffectPlanCancel")
pub fn client_program_effect_plan_cancel(
  value : ClientEffectPlanCursor,
) -> Unit {
  client_effect_plan_poison(value)
}

///|
#export_name("clientProgramEffectPlanCancelPreparation")
pub fn client_program_effect_plan_cancel_preparation(
  value : ClientEffectPlanPreparation,
) -> Bool {
  @strategy.cancel_captured_effect_plan_verifier(value.owner.verifier)
  client_program_effect_managed_input_cancel(value.owner.importing)
  @execution.cancel_completed_result_relation_export(value.preparation)
}

///|
#export_name("clientProgramEffectPlanCancelImport")
pub fn client_program_effect_plan_cancel_import(
  value : ClientEffectPlanImport,
) -> Unit {
  value.open = false
  @strategy.cancel_captured_effect_plan_verifier(value.verifier)
  client_program_effect_managed_input_cancel(value.importing)
}

///|
#export_name("clientProgramReleaseEffectInputs")
pub fn client_program_release_effect_inputs(
  value : @strategy.CapturedEffectInputs,
) -> Bool {
  @strategy.release_captured_effect_inputs(value)
}

///|
/// Compute-only opening for an admitted source-free Effect Run. It preserves
/// the captured Effect owner; physical mutation still requires Preview and
/// apply admission after the checked computation settles.
#export_name("clientProgramOpenSourceFreeLocalEffectHost")
pub fn client_program_open_source_free_local_effect_host(
  prepared : @publication_host.PreparedClientEffectRun,
  registry_body : String,
  values_body : String,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
) -> ClientLocalEffectHost? {
  open_client_local_effect_host(
    prepared,
    None,
    registry_body,
    values_body,
    fixed_ms,
    per_row_ms,
    per_wire_byte_ms,
    per_pair_ms,
  )
}

///|
/// The captured source is checked against the bound Effect Run before the
/// acquisition root can feed any Local task. The physical source owner stays
/// with the Host and is not reconstructed from an equal relation value.
#export_name("clientProgramOpenCapturedLocalEffectHost")
pub fn client_program_open_captured_local_effect_host(
  prepared : @publication_host.PreparedClientEffectRun,
  source : @query.CapturedInputSource,
  registry_body : String,
  values_body : String,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
  fragment_body : String?,
  ordered_body : String?,
) -> ClientLocalEffectHost? {
  open_client_local_effect_host(
    prepared,
    Some(source),
    registry_body,
    values_body,
    fixed_ms,
    per_row_ms,
    per_wire_byte_ms,
    per_pair_ms,
    fragment_body~,
    ordered_body~,
  )
}

///|
fn open_client_local_effect_host(
  prepared : @publication_host.PreparedClientEffectRun,
  source : @query.CapturedInputSource?,
  registry_body : String,
  values_body : String,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
  captured_sources? : Array[(Int, @query.CapturedInputSource)] = [],
  acquisition_ledger? : @resources.Ledger? = None,
  component_providers? : Array[@local.ManagedProvider] = [],
) -> ClientLocalEffectHost? {
  if fixed_ms < 0L ||
    per_row_ms < 0L ||
    per_wire_byte_ms < 0L ||
    per_pair_ms < 0L {
    return None
  }
  guard client_local_contracts(registry_body, values_body) is Some(contracts) else {
    return None
  }
  let multiple = !captured_sources.is_empty()
  if multiple &&
    (
      source is Some(_) ||
      captured_sources.length() != 2 ||
      acquisition_ledger is None
    ) {
    return None
  }
  let computation = @publication_host.prepared_client_effect_run_computation(
    prepared,
  )
  let opened = if multiple {
    @publication_host.open_prepared_multi_captured_client_effect_run(
      prepared,
      captured_sources,
      acquisition_ledger.unwrap(),
    )
  } else {
    guard @client_local_host.client_effect_local_ledger_limits(
        computation, registry_body, values_body, fragment_body, ordered_body,
      )
      is Some(limits) else {
      return None
    }
    match source {
      None =>
        @publication_host.open_prepared_source_free_client_effect_run(
          prepared, limits,
        )
      Some(captured) =>
        @publication_host.open_prepared_captured_client_effect_run(
          prepared, captured, limits,
        )
    }
  }
  let run = match opened {
    Ok(value) => value
    Err(_) => return None
  }
  let captured = @strategy.captured_effect_run_dag(run)
  let graph = @strategy.checked_effect_run_graph(
    @publication_host.prepared_client_effect_run_graph(prepared),
  )
  let first_compute = if multiple { 2 } else if source is None { 0 } else { 1 }
  let generated = []
  if first_compute > 0 || !component_providers.is_empty() {
    let sequences = match
      @client_local_host.prepare_client_effect_local_sequences(
        computation, registry_body, values_body, fragment_body, ordered_body,
      ) {
      Some(value) => value
      None => {
        ignore(reject_client_local_run(captured))
        return None
      }
    }
    for task in first_compute..<sequences.length() {
      generated.push(sequences[task])
    }
  } else {
    for task in first_compute..<@strategy.graph_task_count(graph) {
      let sequence = match
        @publication_host.prepare_client_effect_task_sequence(
          computation,
          task,
          contracts,
          [],
          client_local_sequence_limits(),
          100000,
          10000,
        ) {
        Ok(value) => value
        Err(_) => {
          ignore(reject_client_local_run(captured))
          return None
        }
      }
      generated.push(sequence)
    }
  }
  match
    client_program_configure_local_host(
      captured,
      graph,
      generated,
      first_compute,
      fixed_ms,
      per_row_ms,
      per_wire_byte_ms,
      per_pair_ms,
      component_providers~,
    ) {
    Some(host) => Some({ host, run, })
    None => None
  }
}

///|
fn reject_client_local_run(
  run : @strategy.CapturedDAG,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  None
}

///|
pub(all) enum ClientProgramEffectCompilationBridgeIssue {
  Manifests(@publication_host.ClientCompilationManifestIssue)
  Compilation(@publication_host.ClientEffectCompilationIssue)
}

///|
#export_name("clientProgramCompileLocalEffects")
pub fn client_program_compile_local_effects(
  prepared : @publication_host.PreparedClientEffectComputation,
) -> Result[
  @publication_host.ClientEffectCompilation,
  ClientProgramEffectCompilationBridgeIssue,
] {
  compile_client_local_effects(prepared, None)
}

///|
fn compile_client_local_effects(
  prepared : @publication_host.PreparedClientEffectComputation,
  infer : @publication_host.ClientInferPlanGraph?,
) -> Result[
  @publication_host.ClientEffectCompilation,
  ClientProgramEffectCompilationBridgeIssue,
] {
  let manifests = match
    @publication_host.admit_client_compilation_manifests(
      @check_environment.compiler_grammar_manifest_wire(),
      @check_environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    ) {
    Ok(manifests) => manifests
    Err(issue) => return Err(Manifests(issue))
  }
  @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    client_local_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
    infer~,
  ).map_err(issue => Compilation(issue))
}

///|
/// Expose only the unsupported-profile decision to the Host. Other compiler
/// failures retain their typed cause and must not be reported as a caller's
/// unsupported Program.
#export_name("clientProgramEffectCompilationIssueCode")
pub fn client_program_effect_compilation_issue_code(
  outcome : Result[
    @publication_host.ClientEffectCompilation,
    ClientProgramEffectCompilationBridgeIssue,
  ],
) -> String? {
  match outcome {
    Err(Compilation(UnsupportedProgram)) => Some("unsupported_program")
    _ => None
  }
}

///|
#export_name("clientProgramEffectCompilationPlanWire")
pub fn client_program_effect_compilation_plan_wire(
  value : @publication_host.ClientEffectCompilation,
) -> String {
  @publication_host.client_task_executable_plan_wire(
    @publication_host.client_effect_compilation_plan(value),
  )
}

///|
#export_name("clientProgramEffectCompilationResultTransformation")
pub fn client_program_effect_compilation_result_transformation(
  value : @publication_host.ClientEffectCompilation,
  owner : @publication_host.PreparedClientEffectComputation,
  result : Int,
) -> Result[
  @publication_host.ClientResultTransformation?,
  @publication_host.ClientEffectCompilationAdmissionIssue,
] {
  @publication_host.client_effect_compilation_result_transformation(
    value, owner, result,
  )
}

///|
#export_name("clientProgramEffectCompilationFactManifestWire")
pub fn client_program_effect_compilation_fact_manifest_wire(
  value : @publication_host.ClientEffectCompilation,
) -> String {
  @publication_host.client_task_executable_plan_fact_manifest_wire(
    @publication_host.client_effect_compilation_plan(value),
  )
}

///|
#export_name("clientProgramEffectCompilationTemplateWire")
pub fn client_program_effect_compilation_template_wire(
  value : @publication_host.ClientEffectCompilation,
) -> String {
  @publication.run_evidence_value_json(
    @publication_host.client_effect_compilation_template(value),
  )
}

///|
/// Issue the source-free observation and Run Invocation from the exact
/// checked Effect compilation. The Host supplies its data-policy identity;
/// the Program cannot substitute a Template or observation body.
#export_name("clientProgramIssueEffectSourceFreeInvocation")
pub fn client_program_issue_effect_source_free_invocation(
  value : @publication_host.ClientEffectCompilation,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  @publication_host.issue_client_effect_source_free_invocation(
    value, data_policy_cid, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Issue the acquired observation and Run Invocation only from the admitted
/// Effect owner and its exact captured source.
#export_name("clientProgramIssueEffectCapturedInvocation")
pub fn client_program_issue_effect_captured_invocation(
  prepared : @publication_host.PreparedClientEffectComputation,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  source : @query.CapturedInputSource,
  source_evidence_wire : String,
  input_logical_wire : String,
  source_ref : String,
  source_contract_cid : String,
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  @publication_host.issue_client_effect_captured_invocation(
    prepared, compilation, admission, run_definition, source, source_evidence_wire,
    input_logical_wire, source_ref, source_contract_cid, authority_scope_cid, data_policy_cid,
    capture_started_at, capture_completed_at, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramEffectCompilationCompiledPlanWire")
pub fn client_program_effect_compilation_compiled_plan_wire(
  value : @publication_host.ClientEffectCompilation,
) -> String {
  @publication.publication_contract_json(
    @publication_host.client_effect_compilation_compiled_plan(value),
  )
}

///|
#export_name("clientProgramIssueAllowedEffectRun")
pub fn client_program_issue_allowed_effect_run(
  compilation : @publication_host.ClientEffectCompilation,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
) -> Result[
  @publication_host.ClientEffectAllowedRun,
  @publication_host.ClientEffectCompiledRunIssue,
] {
  @publication_host.issue_client_effect_allowed_run(
    compilation, execution_context_cid, host_policy_cid, expires_at,
  )
}

///|
#export_name("clientProgramAdmitAllowedEffectRun")
pub fn client_program_admit_allowed_effect_run(
  compilation : @publication_host.ClientEffectCompilation,
  prepared : @publication.RunEvidenceValue,
  authorization : @publication.RunEvidenceValue,
) -> Result[
  @publication_host.ClientEffectAllowedRun,
  @publication_host.ClientEffectCompiledRunIssue,
] {
  @publication_host.admit_client_effect_allowed_run(
    compilation, prepared, authorization,
  )
}

///|
#export_name("clientProgramIssueEffectRunDefinition")
pub fn client_program_issue_effect_run_definition(
  allowed : @publication_host.ClientEffectAllowedRun,
  scope_id : String,
  run_id : String,
  created_at : String,
  valid_until : String,
) -> Result[
  @publication.PublicationContract,
  @publication_host.ClientEffectCompiledRunIssue,
] {
  @publication_host.issue_client_effect_run_definition(
    allowed, scope_id, run_id, created_at, valid_until,
  )
}

///|
#export_name("clientProgramBindCompiledEffectRun")
pub fn client_program_bind_compiled_effect_run(
  owner : @publication_host.PreparedClientEffectComputation,
  allowed : @publication_host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
) -> Result[
  @publication_host.PreparedClientEffectRun,
  @publication_host.ClientEffectCompiledRunIssue,
] {
  @publication_host.bind_client_effect_compiled_run(owner, allowed, definition)
}

///|
#export_name("clientProgramEffectRunStartCurrent")
pub fn client_program_effect_run_start_current(
  allowed : @publication_host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  at : String,
) -> Bool {
  @publication_host.client_effect_run_start_current(allowed, definition, at)
}

///|
#export_name("clientProgramEffectCompilationResultNames")
pub fn client_program_effect_compilation_result_names(
  value : @publication_host.ClientEffectCompilation,
) -> Array[String] {
  @publication_host.client_effect_compilation_result_names(value)
}

///|
#export_name("clientProgramEffectCompilationUnitId")
pub fn client_program_effect_compilation_unit_id(
  value : @publication_host.ClientEffectCompilation,
) -> String {
  @publication_host.client_effect_compilation_unit_id(value)
}

///|
#export_name("clientProgramAllowedEffectRunPrepared")
pub fn client_program_allowed_effect_run_prepared(
  value : @publication_host.ClientEffectAllowedRun,
) -> @publication.RunEvidenceValue {
  @publication_host.client_effect_allowed_run_prepared(value)
}

///|
#export_name("clientProgramAllowedEffectRunAuthorization")
pub fn client_program_allowed_effect_run_authorization(
  value : @publication_host.ClientEffectAllowedRun,
) -> @publication.RunEvidenceValue {
  @publication_host.client_effect_allowed_run_authorization(value)
}

///|
#export_name("clientProgramAllowedEffectRunAdmission")
pub fn client_program_allowed_effect_run_admission(
  value : @publication_host.ClientEffectAllowedRun,
) -> @publication.RunPublicationAdmission {
  @publication_host.client_effect_allowed_run_admission(value)
}

///|
#export_name("clientProgramPrepareDuckDBSourceEvidenceContext")
pub fn client_program_prepare_duckdb_source_evidence_context(
  requirement : @planning.QueryRequirement,
) -> Result[
  @duckdb_host.NativeSourceEvidenceContext,
  @duckdb_host.NativeSourceEvidenceIssue,
] {
  @duckdb_host.prepare_native_source_evidence_context(requirement)
}

// Salesforce Site/declaration/projection codecs. Execution and capture use
// the neutral RowSource owner below. Only strings and bytes cross runtimes.

///|
#export_name("clientProgramSalesforceSite")
pub fn client_program_salesforce_site(
  namespace_id : String,
  principal : String,
  environment : String,
  connection_revision : String,
  org_id : String,
  site_key : String,
  site_generation : Int,
  resource_origin : String,
) -> Result[
  @salesforce_host.InstalledSalesforceSite,
  @salesforce_host.InstalledSalesforceIssue,
] {
  @salesforce_host.installed_salesforce_site(
    namespace_id, principal, environment, connection_revision, org_id, site_key,
    site_generation, resource_origin,
  )
}

///|
#export_name("clientProgramSalesforceRecoverObservation")
pub fn client_program_salesforce_recover_observation(
  site : @salesforce_host.InstalledSalesforceSite,
  observation_json : String,
  run_invocation_cid : String,
  dispatch_request_cid : String,
  sync_occurrence : String,
  names : Array[String],
  describe_bytes : Array[Bytes?],
  outcomes : Array[Int],
  describe_use_cids : Array[String?],
  describe_response_sha256 : Array[String?],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_fields : Int,
  max_name_units : Int,
  max_observation_bytes : Int,
  expected_run_invocation_cid : String?,
) -> Result[
  @salesforce_catalog.CatalogObservation,
  @salesforce_host.InstalledSalesforceIssue,
] {
  @salesforce_host.recover_installed_salesforce_observation(
    site,
    observation_json,
    run_invocation_cid,
    dispatch_request_cid,
    sync_occurrence,
    names,
    describe_bytes,
    outcomes,
    describe_use_cids,
    describe_response_sha256,
    { max_bytes, max_nodes, max_depth, max_fields, max_name_units, },
    max_observation_bytes,
    expected_run_invocation_cid,
  )
}

///|
#export_name("clientProgramSalesforceRestoreDeclaration")
pub fn client_program_salesforce_restore_declaration(
  site : @salesforce_host.InstalledSalesforceSite,
  observation : @salesforce_catalog.CatalogObservation,
  connector_id : String,
  catalog_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @salesforce_host.InstalledSalesforceDeclaration,
  @salesforce_host.InstalledSalesforceIssue,
] {
  @salesforce_host.restore_installed_salesforce_declaration(
    site,
    observation,
    connector_id,
    catalog_cid,
    { max_bytes, max_nodes, max_depth, },
  )
}

///|
/// The declared Resource and fields the checked source reads, as
/// `[resource, ...fields]`.
#export_name("clientProgramSalesforceSourceTarget")
pub fn client_program_salesforce_source_target(
  declaration : @salesforce_host.InstalledSalesforceDeclaration,
  requirement : @planning.QueryRequirement,
) -> Result[Array[String], @salesforce_host.InstalledSalesforceIssue] {
  @salesforce_host.installed_salesforce_source_target(declaration, requirement).map(target => {
      [target.0, ..target.1]
    },
  )
}

///|
#export_name("clientProgramPrepareSalesforceDeclaredRowAcquisition")
pub fn client_program_prepare_salesforce_declared_row_acquisition(
  declaration : @salesforce_host.InstalledSalesforceDeclaration,
  requirement : @planning.QueryRequirement,
  query_contract : String,
  evidence_contract : String,
) -> Result[
  @client_row_source_host.RowAcquisition,
  @salesforce_host.InstalledSalesforceIssue,
] {
  @salesforce_host.prepare_installed_salesforce_declared_row_acquisition(
    declaration, requirement, query_contract, evidence_contract,
  )
}

///|
#export_name("clientProgramRecheckSalesforceRowProjection")
pub fn client_program_recheck_salesforce_row_projection(
  declaration : @salesforce_host.InstalledSalesforceDeclaration,
  acquisition : @client_row_source_host.RowAcquisition,
  current : @salesforce_catalog.CatalogObservation,
  max_soql_bytes : Int,
) -> Result[
  @salesforce_catalog.ReadProjection,
  @salesforce_host.InstalledSalesforceIssue,
] {
  @salesforce_host.recheck_installed_salesforce_row_projection(
    declaration, acquisition, current, max_soql_bytes,
  )
}

///|
#export_name("clientProgramPrepareSalesforceRowAcquisition")
pub fn client_program_prepare_salesforce_row_acquisition(
  declaration : @salesforce_host.InstalledSalesforceDeclaration,
  requirement : @planning.QueryRequirement,
  current : @salesforce_catalog.CatalogObservation,
  query_contract : String,
  evidence_contract : String,
  max_soql_bytes : Int,
) -> Result[
  (@salesforce_catalog.ReadProjection, @client_row_source_host.RowAcquisition),
  @salesforce_host.InstalledSalesforceIssue,
] {
  @salesforce_host.prepare_installed_salesforce_row_acquisition(
    declaration, requirement, current, query_contract, evidence_contract, max_soql_bytes,
  )
}

///|
#export_name("clientProgramSalesforceQueryPageValues")
pub fn client_program_salesforce_query_page_values(
  page : @salesforce_catalog.QueryPage,
) -> (Array[String], Array[Array[@admitted.CheckedValue]]) {
  let columns = @salesforce_catalog.query_page_field_names(page)
  let rows = []
  for index in 0..<@salesforce_catalog.query_page_row_count(page) {
    let row = []
    for column in 0..<columns.length() {
      row.push(
        @salesforce_catalog.query_page_cell(page, index, column).unwrap(),
      )
    }
    rows.push(row)
  }
  (columns, rows)
}

///|
#export_name("clientProgramSalesforceQueryReadValueViolation")
pub fn client_program_salesforce_query_read_value_violation(
  plan : @salesforce_catalog.ReadProjection,
  issue : @salesforce_catalog.QueryReadIssue,
) -> String? {
  match issue {
    Page(issue) =>
      @salesforce_catalog.query_page_value_violation(issue, plan).map(value => {
        @salesforce_catalog.query_value_violation_json(value)
      })
    _ => None
  }
}

///|
#export_name("clientProgramRowSourceChargePage")
pub fn client_program_row_source_charge_page(
  run : @client_row_source_host.RowRun,
  body : Bytes,
) -> Result[
  @client_row_source_host.RowPageCharge,
  @client_row_source_host.RowHostIssue,
] {
  @client_row_source_host.charge_row_run_page(run, body)
}

///|
#export_name("clientProgramRowSourceAcceptChargedPage")
pub fn client_program_row_source_accept_charged_page(
  run : @client_row_source_host.RowRun,
  charge : @client_row_source_host.RowPageCharge,
  bytes : Bytes,
) -> Result[Int, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.accept_charged_row_run_page(run, charge, bytes)
}

///|
#export_name("clientProgramRowSourceAcceptChargedValues")
pub fn client_program_row_source_accept_charged_values(
  run : @client_row_source_host.RowRun,
  charge : @client_row_source_host.RowPageCharge,
  columns : Array[String],
  rows : Array[Array[@admitted.CheckedValue]],
) -> Result[Int, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.accept_charged_row_run_values(
    run, charge, columns, rows,
  )
}

///|
#export_name("clientProgramRowSourceAcceptValues")
pub fn client_program_row_source_accept_values(
  run : @client_row_source_host.RowRun,
  columns : Array[String],
  rows : Array[Array[@admitted.CheckedValue]],
) -> Result[Int, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.accept_row_run_values(run, columns, rows)
}

///|
#export_name("clientProgramSalesforceBeginQueryRead")
pub fn client_program_salesforce_begin_query_read(
  plan : @salesforce_catalog.ReadProjection,
  api_version : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_locator_units : Int,
  max_pages : Int,
  max_total_rows : Int64,
) -> Result[@salesforce_catalog.QueryRead, @salesforce_catalog.QueryReadIssue] {
  match
    @salesforce_catalog.begin_query_read(
      plan,
      api_version,
      { max_bytes, max_nodes, max_depth, max_rows, max_locator_units, },
      max_pages,
      max_total_rows,
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(issue)
  }
}

///|
#export_name("clientProgramSalesforceQueryReadNextPath")
pub fn client_program_salesforce_query_read_next_path(
  read : @salesforce_catalog.QueryRead,
) -> Result[String?, @salesforce_catalog.QueryReadIssue] {
  match @salesforce_catalog.query_read_next_path(read) {
    Ok(path) => Ok(path)
    Err(issue) => Err(issue)
  }
}

///|
#export_name("clientProgramSalesforceQueryReadAcceptPage")
pub fn client_program_salesforce_query_read_accept_page(
  read : @salesforce_catalog.QueryRead,
  path : String,
  body : Bytes,
) -> Result[@salesforce_catalog.QueryPage, @salesforce_catalog.QueryReadIssue] {
  match @salesforce_catalog.query_read_accept_page(read, path, body) {
    Ok(value) => Ok(value)
    Err(issue) => Err(issue)
  }
}

///|
#export_name("clientProgramSalesforceQueryReadAcknowledgePage")
pub fn client_program_salesforce_query_read_acknowledge_page(
  read : @salesforce_catalog.QueryRead,
  page : @salesforce_catalog.QueryPage,
) -> Result[Unit, @salesforce_catalog.QueryReadIssue] {
  match @salesforce_catalog.acknowledge_query_page(read, page) {
    Ok(_) => Ok(())
    Err(issue) => Err(issue)
  }
}

///|
#export_name("clientProgramSalesforceQueryReadInterrupt")
pub fn client_program_salesforce_query_read_interrupt(
  read : @salesforce_catalog.QueryRead,
) -> Bool {
  @salesforce_catalog.interrupt_query_read(read)
}

///|
#export_name("clientProgramSalesforceQueryReadComplete")
pub fn client_program_salesforce_query_read_complete(
  read : @salesforce_catalog.QueryRead,
) -> Bool {
  @salesforce_catalog.query_read_complete(read)
}

///|
#export_name("clientProgramSalesforceQueryReadRowCount")
pub fn client_program_salesforce_query_read_row_count(
  read : @salesforce_catalog.QueryRead,
) -> Int64 {
  @salesforce_catalog.query_read_row_count(read)
}

///|
#export_name("clientProgramSalesforceQueryPageRowCount")
pub fn client_program_salesforce_query_page_row_count(
  page : @salesforce_catalog.QueryPage,
) -> Int {
  @salesforce_catalog.query_page_row_count(page)
}

///|
#export_name("clientProgramSalesforceQueryPageResponseSha256")
pub fn client_program_salesforce_query_page_response_sha256(
  page : @salesforce_catalog.QueryPage,
) -> String {
  @salesforce_catalog.query_page_response_sha256(page)
}

///|
#export_name("clientProgramSalesforceRecheckReadProjection")
pub fn client_program_salesforce_recheck_read_projection(
  plan : @salesforce_catalog.ReadProjection,
  current : @salesforce_catalog.CatalogObservation,
) -> Result[Bool, @salesforce_catalog.ReadProjectionIssue] {
  @salesforce_catalog.recheck_read_projection(plan, current).map(_ => true)
}

///|
#export_name("clientProgramSalesforceReadProjectionScopeMatches")
pub fn client_program_salesforce_read_projection_scope_matches(
  plan : @salesforce_catalog.ReadProjection,
  namespace_id : String,
  principal : String,
  environment : String,
  site_key : String,
  site_generation : Int,
  connector_registration : String,
  connector_revision : String,
  resource_origin : String,
  run_invocation_cid : String,
  dispatch_request_cid : String,
) -> Bool {
  @salesforce_catalog.read_projection_matches_site_scope(
    plan, namespace_id, principal, environment, site_key, site_generation, connector_registration,
    connector_revision, resource_origin, run_invocation_cid, dispatch_request_cid,
  )
}

///|
#export_name("clientProgramIssueEffectMultiCapturedInvocation")
pub fn client_program_issue_effect_multi_captured_invocation(
  prepared : @publication_host.PreparedClientEffectComputation,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  captures : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  requirements : Array[@planning.QueryRequirement],
  source_evidence_wires : Array[String],
  input_logical_wires : Array[String],
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  @publication_host.issue_client_effect_multi_captured_invocation(
    prepared, compilation, admission, run_definition, captures, identities, requirements,
    source_evidence_wires, input_logical_wires, authority_scope_cid, data_policy_cid,
    capture_started_at, capture_completed_at, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramEffectPublicationDataPolicyCid")
pub fn client_program_effect_publication_data_policy_cid(
  value : @publication_host.PreparedClientEffectComputation,
) -> String? {
  @publication_host.prepared_client_effect_publication_data_policy_cid(value)
}

///|
#export_name("clientProgramEffectAcquisitionCount")
pub fn client_program_effect_acquisition_count(
  value : @publication_host.PreparedClientEffectComputation,
) -> Int {
  @strategy.graph_captured_prefix(
    @strategy.checked_effect_computation_graph(
      @publication_host.prepared_client_effect_computation_graph(value),
    ),
  )
}

///|
#export_name("clientProgramEffectPublicationPolicyBodies")
pub fn client_program_effect_publication_policy_bodies(
  value : @publication_host.PreparedClientEffectComputation,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  Array[(String, String, String)],
  @program_check.LocalDependencyBodyIssue,
] {
  @publication_host.prepared_client_effect_publication_policy_bodies(
    value, max_bytes, max_nodes, max_depth,
  )
}

// Provider-neutral installed row sources. A connector's Site driver pushes
// pages of JSON rows; declaration generation, admission, capture and Source
// Evidence are owned here, by the runtime that checked the Program. Nothing
// crosses from a provider's compiled bundle except strings and bytes, and no
// provider name appears in these entries.

///|
#export_name("clientProgramRowSourceRestoreDeclaration")
pub fn client_program_row_source_restore_declaration(
  connector_id : String,
  connector_registration : String,
  connector_version : String,
  views_json : String,
  expected_catalog_cid : String?,
) -> Result[
  @client_row_source_host.RowDeclaration,
  @client_row_source_host.RowHostIssue,
] {
  @client_row_source_host.restore_row_declaration(
    connector_id, connector_registration, connector_version, views_json, expected_catalog_cid,
  )
}

///|
/// The published parts of a declaration as one JSON text: Catalog CID,
/// Catalog, contracts, views, view bodies, manifest entry and its CID, and
/// the Check Environment evidence members.
#export_name("clientProgramRowSourceDeclarationJson")
pub fn client_program_row_source_declaration_json(
  declaration : @client_row_source_host.RowDeclaration,
) -> String {
  let (schemas, capabilities) = @client_row_source_host.row_declaration_evidence_members(
    declaration,
  ) catch {
    _ => return "null"
  }
  let views : Array[Json] = declaration.views.map(view => {
    "resource": view.resource.to_json(),
    "source_ref": view.source_ref.to_json(),
    "view_cid": view.view_cid.to_json(),
    "fields": view.fields.to_json(),
    "carrier_schema_cid": view.carrier_schema_cid.to_json(),
    "data_policy_cid": view.data_policy_cid.to_json(),
  })
  let json : Json = {
    "connector_id": declaration.connector_id.to_json(),
    "connector_registration": declaration.connector_registration.to_json(),
    "connector_version": declaration.connector_version.to_json(),
    "catalog": declaration.catalog.to_json(),
    "catalog_cid": declaration.catalog_cid.to_json(),
    "contracts": declaration.contracts.to_json(),
    "views": Json::array(views),
    "view_bodies": declaration.view_bodies.to_json(),
    "manifest_entry": declaration.manifest_entry.to_json(),
    "manifest_entry_cid": declaration.manifest_entry_cid.to_json(),
    "evidence_schemas": schemas.to_json(),
    "evidence_capabilities": capabilities.to_json(),
  }
  json.stringify()
}

///|
#export_name("clientProgramRowSourceTarget")
pub fn client_program_row_source_target(
  declaration : @client_row_source_host.RowDeclaration,
  requirement : @planning.QueryRequirement,
) -> Result[Array[String], @client_row_source_host.RowHostIssue] {
  @client_row_source_host.row_source_target(declaration, requirement).map(target => {
    [target.0, ..target.1]
  })
}

///|
#export_name("clientProgramRowSourcePrepareAcquisition")
pub fn client_program_row_source_prepare_acquisition(
  declaration : @client_row_source_host.RowDeclaration,
  requirement : @planning.QueryRequirement,
  query_contract : String,
  evidence_contract : String,
) -> Result[
  @client_row_source_host.RowAcquisition,
  @client_row_source_host.RowHostIssue,
] {
  @client_row_source_host.prepare_row_acquisition(
    declaration, requirement, query_contract, evidence_contract,
  )
}

///|
#export_name("clientProgramRowSourceColumns")
pub fn client_program_row_source_columns(
  acquisition : @client_row_source_host.RowAcquisition,
) -> Array[String] {
  @client_row_source_host.row_acquisition_columns(acquisition)
}

///|
#export_name("clientProgramRowSourceStart")
pub fn client_program_row_source_start(
  acquisition : @client_row_source_host.RowAcquisition,
  nonce : String,
  verify : (@client_row_source_host.RowAttempt) -> Bool,
) -> Result[
  @client_row_source_host.RowRun,
  @client_row_source_host.RowHostIssue,
] {
  @client_row_source_host.start_row_acquisition(acquisition, nonce, verify)
}

///|
#export_name("clientProgramRowSourceStartAccounted")
pub fn client_program_row_source_start_accounted(
  acquisition : @client_row_source_host.RowAcquisition,
  nonce : String,
  verify : (@client_row_source_host.RowAttempt) -> Bool,
  ledger : @resources.Ledger,
  transfer_bytes : Int64,
  execution_scratch : Int64,
) -> Result[
  @client_row_source_host.RowRun,
  @client_row_source_host.RowHostIssue,
] {
  @client_row_source_host.start_accounted_row_acquisition(
    acquisition, nonce, verify, ledger, transfer_bytes, execution_scratch,
  )
}

///|
#export_name("clientProgramRowSourceRetainCapturedTask")
pub fn client_program_row_source_retain_captured_task(
  capture : @client_row_source_host.RowSourceCapture,
  dag : @strategy.CapturedDAG,
  task : Int,
) -> Result[Unit, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.retain_row_capture_task(capture, dag, task)
}

///|
#export_name("clientProgramRowSourceCloseAccounted")
pub fn client_program_row_source_close_accounted(
  run : @client_row_source_host.RowRun,
) -> Result[Unit, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.close_accounted_row_run(run)
}

///|
#export_name("clientProgramRowSourceAttempt")
pub fn client_program_row_source_attempt(
  run : @client_row_source_host.RowRun,
) -> @client_row_source_host.RowAttempt {
  @client_row_source_host.row_run_attempt(run)
}

///|
#export_name("clientProgramRowSourceBegin")
pub fn client_program_row_source_begin(
  run : @client_row_source_host.RowRun,
  max_page_bytes : Int,
  max_page_rows : Int,
  max_capture_rows : Int,
) -> Result[Bool, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.begin_row_run(
    run, max_page_bytes, max_page_rows, max_capture_rows,
  ).map(_ => true)
}

///|
#export_name("clientProgramRowSourceAcceptPage")
pub fn client_program_row_source_accept_page(
  run : @client_row_source_host.RowRun,
  page : Bytes,
) -> Result[Int, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.accept_row_run_page(run, page)
}

///|
#export_name("clientProgramRowSourceFinish")
pub fn client_program_row_source_finish(
  run : @client_row_source_host.RowRun,
) -> Result[Bool, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.finish_row_run(run).map(_ => true)
}

///|
#export_name("clientProgramRowSourceClose")
pub fn client_program_row_source_close(
  run : @client_row_source_host.RowRun,
) -> Unit {
  @client_row_source_host.close_row_run(run)
}

///|
#export_name("clientProgramRowSourceCapture")
pub fn client_program_row_source_capture(
  run : @client_row_source_host.RowRun,
) -> Result[
  @client_row_source_host.RowSourceCapture,
  @client_row_source_host.RowHostIssue,
] {
  @client_row_source_host.capture_row_run(run)
}

///|
#export_name("clientProgramRowSourceCaptureSource")
pub fn client_program_row_source_capture_source(
  capture : @client_row_source_host.RowSourceCapture,
) -> Result[@query.CapturedInputSource, @query.CapturedSourceIssue] {
  @client_row_source_host.row_capture_source(capture)
}

///|
#export_name("clientProgramRowSourceIssueSourceEvidence")
pub fn client_program_row_source_issue_source_evidence(
  acquisition : @client_row_source_host.RowAcquisition,
  capture : @client_row_source_host.RowSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
  logical_input : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  effective_data_policy_cid : String,
  observed_at : String,
) -> Result[String, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.issue_row_source_evidence(
    acquisition, capture, identity, logical_input, authority_scope_cid, effective_data_policy_cid,
    observed_at,
  ).map(value => @publication.run_evidence_value_json(value))
}

///|
/// The create Mapping of `resource` from the connector's declared writes, as
/// `{"mapping_ref","mapping_cid","body","write_fields","omittable"}` or
/// `{"issue": <name>}`. `sources_json` is
/// `[{"target","field","null_behavior"}]`.
#export_name("clientProgramRowSourcePrepareMapping")
pub fn client_program_row_source_prepare_mapping(
  declaration : @client_row_source_host.RowDeclaration,
  writes_json : String,
  resource : String,
  sources_json : String,
) -> String {
  let refused = (name : String) => {
    ({ "issue": name.to_json() } : Json).stringify()
  }
  let parsed = @json.parse(sources_json) catch {
    _ => return refused("InvalidSpecification")
  }
  guard parsed is Array(items) else { return refused("InvalidSpecification") }
  let sources = []
  for item in items {
    guard item is Object(entries) &&
      entries.length() == 3 &&
      entries.get("target") is Some(String(target)) &&
      entries.get("field") is Some(String(field)) &&
      entries.get("null_behavior") is Some(String(null_behavior)) else {
      return refused("InvalidSpecification")
    }
    sources.push(
      (
        { target, field, null_behavior, } :
        @client_row_source_host.RowMappingSource),
    )
  }
  match
    @client_row_source_host.prepare_row_mapping(
      declaration, writes_json, resource, sources,
    ) {
    Ok(mapping) =>
      (
        {
          "mapping_ref": mapping.mapping_ref.to_json(),
          "mapping_cid": mapping.mapping_cid.to_json(),
          "body": mapping.body.to_json(),
          "write_fields": mapping.write_fields.to_json(),
          "omittable": mapping.omittable.to_json(),
        } : Json).stringify()
    Err(issue) => {
      let name = match issue {
        InvalidSpecification => "InvalidSpecification"
        NotWritable(_) => "NotWritable"
        EmptyWrite => "EmptyWrite"
        DuplicateField(_) => "DuplicateField"
        FieldNotWritable(_) => "FieldNotWritable"
        MissingRequiredField(_) => "MissingRequiredField"
        InvalidNullBehavior(_) => "InvalidNullBehavior"
        OutputLimit => "OutputLimit"
      }
      refused(name)
    }
  }
}
