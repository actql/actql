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
  {
    checking: {
      input: {
        source: { max_input_bytes: 65536, max_nodes: 8192, max_depth: 64, },
        tree: {
          max_nodes: 8192,
          max_depth: 64,
          max_string_bytes: 65536,
          max_total_string_bytes: 65536,
        },
        max_stages: 32,
      },
      compilation: {
        work: 10000000,
        artifacts: { bytes: 10000000, nodes: 1000000, depth: 100, },
        structure: {
          stages: 32,
          steps: 1024,
          results: 1024,
          parameters: 1024,
          bindings: 100000,
          slots: 100000,
          references: 100000,
          requirements: 100000,
          tokens: 100000,
        },
        traversal: {
          nodes: 1000000,
          depth: 100,
          text_bytes: 10000000,
          string_bytes: 1000000,
          name_bytes: 1000000,
          pointer_units: 1000000,
          comparison_pairs: 1000000,
        },
        values: { nodes: 1000000, depth: 100, text_bytes: 1000000, },
        policy: { bytes: 1000000, nodes: 1000000, depth: 100, },
        patterns: { bytes: 1000000, nodes: 1000000, depth: 100, },
      },
    },
    lowering: {
      max_nodes: 100000,
      max_references: 100000,
      max_work: 1000000,
      max_identifier_bytes: 65536,
    },
    max_parameters: 1024,
    max_parameter_name_bytes: 65536,
    max_tasks: 32,
    max_graph_work: 1000000,
  }
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
/// The installed Local profile applies one bounded sequence definition to
/// compiler material and the task that physically executes it.
fn client_local_sequence_limits() -> @lower.SequenceLimits {
  {
    max_steps: 100,
    max_rows: 100,
    max_cells: 10000,
    max_bindings: 100,
    max_name_bytes: 10000,
    expressions: {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  }
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
fn reject_client_local_run(
  run : @strategy.CapturedDAG,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  None
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
/// Assemble an installed Local realization from the checked task owners.
/// The two registry bodies are independently validated against the selected
/// engine pins; caller-provided names or CIDs cannot install an extension.
/// This opens only an in-memory task owner. Client request and Run admission
/// must finish before the Host invokes it or starts physical work.
#export_name("clientProgramOpenSourceFreeLocalHost")
pub fn client_program_open_source_free_local_host(
  prepared : @publication_host.PreparedClientProgram,
  registry_body : String,
  values_body : String,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  if fixed_ms < 0L ||
    per_row_ms < 0L ||
    per_wire_byte_ms < 0L ||
    per_pair_ms < 0L {
    return None
  }
  guard client_local_contracts(registry_body, values_body) is Some(contracts) else {
    return None
  }
  let run = match
    @publication_host.open_prepared_source_free_client_run(prepared, {
      planning_work: 100000,
      attempts: 10,
      holdings: 10,
      transfer_bytes: 500000L,
      retained_bytes: 200000000L,
      execution_bytes: 268435456L,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  let graph = @publication_host.prepared_client_graph(prepared)
  let generated = []
  for task in 0..<@strategy.graph_task_count(graph) {
    let sequence = match
      @publication_host.prepare_client_task_sequence(
        prepared,
        task,
        contracts,
        [],
        client_local_sequence_limits(),
        100000,
        10000,
      ) {
      Ok(value) => value
      Err(_) => return reject_client_local_run(run)
    }
    generated.push(sequence)
  }
  client_program_configure_local_host(
    run, graph, generated, fixed_ms, per_row_ms, per_wire_byte_ms, per_pair_ms,
  )
}

///|
fn client_program_configure_local_host(
  run : @strategy.CapturedDAG,
  graph : @strategy.CheckedDAG,
  generated : Array[@execution.GeneratedSequence],
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
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
  let local_configuration : @local_driver.LocalComputeConfiguration = {
    sequences: generated,
    managed_providers: [],
    managed_capacity: capacity,
    execution: {
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
    },
    measurement: {
      max_work: 10000,
      max_bytes: 10000,
      max_nodes: 10000,
      max_depth: 100,
    },
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
      {
        max_rows: 100,
        values,
        wire: {
          max_columns: 10,
          max_order_work: 100,
          max_bytes: 10000,
          max_nodes: 1000,
          max_depth: 20,
        },
        row: {
          max_bytes: 100,
          max_nodes: 20,
          max_depth: 4,
          max_text_bytes: 100,
        },
        max_batch_bytes: 64,
      },
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
  let schedules = Array::make(@strategy.graph_task_count(graph), schedule)
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
  if fixed_ms < 0L ||
    per_row_ms < 0L ||
    per_wire_byte_ms < 0L ||
    per_pair_ms < 0L {
    return None
  }
  guard client_local_contracts(registry_body, values_body) is Some(contracts) else {
    return None
  }
  let run = match
    @publication_host.open_prepared_source_free_client_effect_run(prepared, {
      planning_work: 100000,
      attempts: 10,
      holdings: 10,
      transfer_bytes: 500000L,
      retained_bytes: 200000000L,
      execution_bytes: 268435456L,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  let captured = @strategy.captured_effect_run_dag(run)
  let computation = @publication_host.prepared_client_effect_run_computation(
    prepared,
  )
  let graph = @strategy.checked_effect_run_graph(
    @publication_host.prepared_client_effect_run_graph(prepared),
  )
  let generated = []
  for task in 0..<@strategy.graph_task_count(graph) {
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
  match
    client_program_configure_local_host(
      captured, graph, generated, fixed_ms, per_row_ms, per_wire_byte_ms, per_pair_ms,
    ) {
    Some(host) => Some({ host, run, })
    None => None
  }
}
