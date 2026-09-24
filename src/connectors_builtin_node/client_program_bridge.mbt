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
  let limits : @publication_host.ClientProgramPreparationLimits = {
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
fn reject_client_local_run(
  run : @strategy.CapturedDAG,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  None
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
  if registry_body.length() > 100000 ||
    values_body.length() > 100000 ||
    fixed_ms < 0L ||
    per_row_ms < 0L ||
    per_wire_byte_ms < 0L ||
    per_pair_ms < 0L {
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
  let contracts = match
    @execution.admit_relation_registry(registry_value, values_value, {
      max_body_bytes: 100000,
      max_body_nodes: 10000,
      max_body_depth: 100,
    }) {
    Ok(value) => value
    Err(_) => return None
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
  let registry = match
    @connector.prepare_capability_registry(
      [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
      1,
      100,
    ) {
    Ok(value) => value
    Err(_) => return reject_client_local_run(run)
  }
  guard @connector.capability_registration_at(registry, 0)
    is Some(local_registration) else {
    return reject_client_local_run(run)
  }
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
  let modules = match
    @builtin.configure_compute_modules(
      @host_driver.open_dispatch_driver(run),
      registry,
      1,
      _ => @strategy.RunIssue::ForeignCandidate,
      with_local=Some(
        (
          local_registration,
          {
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
          },
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
