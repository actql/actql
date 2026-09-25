///|
/// Host-internal ABI. The environment is an admitted machine-contract value,
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
  let wire = match
    @check_environment.read(@utf8.encode(body), evidence_bundle_cid, {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 64,
      max_members: 256,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  Some(
    @program_check.checking_environment(wire, { text_time, veca, }, {
      rela,
      sga,
      tea,
      calendar,
      text_rank,
    }),
  )
}

///|
/// Preserve the shared checker's typed failure across the in-process Host ABI.
/// A wire adapter may project it to a public error, but must not recheck the
/// Program or infer missing inputs from an absent prepared handle.
pub(all) enum ClientProgramBridgeIssue {
  InvalidFormat
  SuppliedSyntax(@source.ParseError)
  SuppliedAdmission(@decode.Issue)
  Preparation(@publication_host.ClientProgramPreparationIssue)
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
  let selected = match format {
    "json" => @stage_syntax.Json
    "yaml" => @stage_syntax.Yaml
    _ => return Rejected(InvalidFormat)
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
        Err(issue) => return Rejected(SuppliedSyntax(issue))
      }
      match
        @decode.admit(parsed, {
          max_nodes: 8192,
          max_depth: 64,
          max_string_bytes: 65536,
          max_total_string_bytes: 65536,
        }) {
        Ok(value) => Some(value)
        Err(issue) => return Rejected(SuppliedAdmission(issue))
      }
    }
  }
  let limits = @publication_host.client_standard_program_preparation_limits()
  match
    @publication_host.prepare_effect_free_client_program(
      document, selected, environment, supplied, limits,
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
/// Retain the original no-Parameter convenience ABI for existing installed
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
/// Issue the checked Result-publication Plan subset for this private ABI.
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
/// Open the portable installed Local Host from this JS ABI.
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
  )
}
