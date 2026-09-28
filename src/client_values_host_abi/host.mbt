///|
/// The shared checked Program and compiler owner for Host adapters. Handles
/// remain in process; serialized CIDs never serve as execution authority.
#export_name("clientValuesHostEnvironment")
pub fn client_values_host_environment(
  body : String,
  evidence_bundle_cid : String,
  text_time : Bool,
  veca : Bool,
  rela : Bool,
  sga : Bool,
  tea : Bool,
  calendar : Bool,
  text_rank : Bool,
) -> @checked.CheckEnvironment? {
  @host.admit_client_check_environment(
    body,
    evidence_bundle_cid,
    { text_time, veca, },
    { rela, sga, tea, calendar, text_rank, },
  )
}

///|
pub(all) enum ClientValuesHostPreparationIssue {
  InvalidFormat
  SuppliedSyntax(@source.ParseError)
  SuppliedAdmission(@decode.Issue)
  Program(@host.ClientProgramPreparationIssue)
}

///|
/// Parse one normal JSON/YAML Program and optional separately supplied
/// Parameter Values through the ordinary MoonBit checker.
#export_name("clientValuesHostPrepare")
pub fn client_values_host_prepare(
  document : String,
  format : String,
  environment : @checked.CheckEnvironment,
  parameters : String?,
) -> Result[@host.PreparedClientProgram, ClientValuesHostPreparationIssue] {
  let selected = match format {
    "json" => @syntax.Json
    "yaml" => @syntax.Yaml
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
  match
    @host.prepare_effect_free_client_program(
      document,
      selected,
      environment,
      supplied,
      @host.client_standard_program_preparation_limits(),
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Program(issue))
  }
}

///|
pub(all) enum ClientValuesHostCompilationIssue {
  Manifests(@host.ClientCompilationManifestIssue)
  Compilation(@host.ClientValuesCompilationIssue)
}

///|
/// Compile only the admitted direct Values profile. Other Programs stay with
/// the ordinary checker but cannot receive an unsupported Plan from this ABI.
#export_name("clientValuesHostCompile")
pub fn client_values_host_compile(
  prepared : @host.PreparedClientProgram,
) -> Result[@host.ClientValuesCompilation, ClientValuesHostCompilationIssue] {
  let manifests = match
    @host.admit_client_compilation_manifests(
      @environment.compiler_grammar_manifest_wire(),
      @environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    ) {
    Ok(manifests) => manifests
    Err(issue) => return Err(Manifests(issue))
  }
  match
    @host.issue_prepared_client_values_compilation(
      prepared,
      manifests,
      @host.client_standard_values_sequence_limits(),
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
pub(all) enum ClientValuesHostTaskCompilationIssue {
  Manifests(@host.ClientCompilationManifestIssue)
  Compilation(@host.ClientTaskCompilationIssue)
}

///|
#export_name("clientValuesHostCompileTasks")
pub fn client_values_host_compile_tasks(
  prepared : @host.PreparedClientProgram,
) -> Result[@host.ClientTaskCompilation, ClientValuesHostTaskCompilationIssue] {
  let manifests = match
    @host.admit_client_compilation_manifests(
      @environment.compiler_grammar_manifest_wire(),
      @environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    ) {
    Ok(manifests) => manifests
    Err(issue) => return Err(Manifests(issue))
  }
  @host.issue_prepared_client_task_compilation(
    prepared,
    manifests,
    @host.client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
  ).map_err(issue => Compilation(issue))
}

///|
#export_name("clientValuesHostTaskPlanWire")
pub fn client_values_host_task_plan_wire(
  value : @host.ClientTaskCompilation,
) -> String {
  @host.client_task_executable_plan_wire(
    @host.client_task_compilation_plan(value),
  )
}

///|
#export_name("clientValuesHostTaskFactManifestWire")
pub fn client_values_host_task_fact_manifest_wire(
  value : @host.ClientTaskCompilation,
) -> String {
  @host.client_task_executable_plan_fact_manifest_wire(
    @host.client_task_compilation_plan(value),
  )
}

///|
#export_name("clientValuesHostTaskTemplateWire")
pub fn client_values_host_task_template_wire(
  value : @host.ClientTaskCompilation,
) -> String {
  @publication.run_evidence_value_json(
    @host.client_task_compilation_template(value),
  )
}

///|
#export_name("clientValuesHostTaskCompiledPlanWire")
pub fn client_values_host_task_compiled_plan_wire(
  value : @host.ClientTaskCompilation,
) -> String {
  @publication.publication_contract_json(
    @host.client_task_compilation_compiled_plan(value),
  )
}

///|
#export_name("clientValuesHostTaskResultNames")
pub fn client_values_host_task_result_names(
  value : @host.ClientTaskCompilation,
) -> Array[String] {
  @host.client_task_compilation_result_names(value)
}

///|
#export_name("clientValuesHostPlanWire")
pub fn client_values_host_plan_wire(
  value : @host.ClientValuesCompilation,
) -> String {
  @host.client_values_executable_plan_wire(
    @host.client_values_compilation_plan(value),
  )
}

///|
#export_name("clientValuesHostFactManifestWire")
pub fn client_values_host_fact_manifest_wire(
  value : @host.ClientValuesCompilation,
) -> String {
  @host.client_values_executable_plan_fact_manifest_wire(
    @host.client_values_compilation_plan(value),
  )
}

///|
#export_name("clientValuesHostTemplateWire")
pub fn client_values_host_template_wire(
  value : @host.ClientValuesCompilation,
) -> String {
  @publication.run_evidence_value_json(
    @host.client_values_compilation_template(value),
  )
}

///|
#export_name("clientValuesHostCompiledPlanWire")
pub fn client_values_host_compiled_plan_wire(
  value : @host.ClientValuesCompilation,
) -> String {
  @publication.publication_contract_json(
    @host.client_values_compilation_compiled_plan(value),
  )
}

///|
/// Exact checked Compiled Plan identity for this Values compilation.
#export_name("clientValuesHostCompiledPlanCid")
pub fn client_values_host_compiled_plan_cid(
  value : @host.ClientValuesCompilation,
) -> String {
  @publication.publication_contract_identity(
    @host.client_values_compilation_compiled_plan(value),
  )
}

///|
pub(all) enum ClientValuesHostPublicationSnapshotIssue {
  InvalidObservation
  Projection(@publication.PublicationSnapshotIssue)
}

///|
/// The caller must first establish the latest admitted record and perform an
/// authoritative index query. An unknown query never means confirmed absence.
#export_name("clientValuesHostProjectPublicationSnapshot")
pub fn client_values_host_project_publication_snapshot(
  record : @publication.PublicationContract?,
  index_mode : Int,
  index : @publication.PublicationContract?,
) -> Result[Array[String], ClientValuesHostPublicationSnapshotIssue] {
  let observed = match (index_mode, index) {
    (0, None) => @publication.IndexConfirmedAbsent
    (1, None) => @publication.IndexQueryUnknown
    (2, Some(entry)) => @publication.IndexCommitted(entry)
    _ => return Err(InvalidObservation)
  }
  let snapshot = match
    @publication.project_publication_snapshot(record, observed) {
    Ok(value) => value
    Err(issue) => return Err(Projection(issue))
  }
  Ok([
    @publication.publication_snapshot_state_text(snapshot),
    @publication.publication_snapshot_evidence_cid(snapshot).unwrap_or(""),
  ])
}

///|
/// Shared Store slot identity for the one public index of an exact Run.
#export_name("clientValuesHostPublicationIndexScopeKey")
pub fn client_values_host_publication_index_scope_key(
  tenant_id : String,
  authority_scope_cid : String,
  run_definition_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @publication.PublicationCommitIssuanceIssue] {
  @publication.publication_index_scope_storage_key(
    tenant_id, authority_scope_cid, run_definition_cid, max_wire_bytes, max_nodes,
    max_depth,
  )
}

///|
/// In-process checked execution coordinates for the single Values node.
/// The Site still needs an authorized candidate, grant and Run dispatch.
#export_name("clientValuesHostPlanNodeId")
pub fn client_values_host_plan_node_id(
  value : @host.ClientValuesCompilation,
) -> String {
  @host.client_values_compilation_plan_node_id(value)
}

///|
#export_name("clientValuesHostOutputContractCid")
pub fn client_values_host_output_contract_cid(
  value : @host.ClientValuesCompilation,
) -> String {
  @host.client_values_compilation_output_contract_cid(value)
}

///|
#export_name("clientValuesHostResultNames")
pub fn client_values_host_result_names(
  value : @host.ClientValuesCompilation,
) -> Array[String] {
  @host.client_values_compilation_result_names(value)
}

///|
/// Checked schema of the direct Values output. The Host binds this to the
/// admitted compilation before permitting payload identity inspection.
#export_name("clientValuesHostResultSchema")
pub fn client_values_host_result_schema(
  prepared : @host.PreparedClientProgram,
) -> Result[Array[String], @host.ClientValuesOutputSchemaIssue] {
  let schema = match
    @host.issue_prepared_client_values_output_schema(
      prepared,
      0,
      @host.client_standard_values_sequence_limits(),
      {
        max_fields: 100,
        max_bytes: 1000000,
        max_nodes: 100000,
        max_depth: 100,
      },
      1000000,
      100000,
      100,
    ) {
    Ok(schema) => schema
    Err(issue) => return Err(issue)
  }
  let facts = [
    @execution.relation_schema_cid(schema),
    @execution.relation_schema_wire(schema),
  ]
  for field in @execution.relation_schema_field_names(schema) {
    facts.push(field)
  }
  Ok(facts)
}

///|
pub(all) enum ClientValuesHostTaskResultSchemaIssue {
  MissingResult
  Root(@host.ClientDirectResultRootIssue)
  Schema(@host.ClientTaskOutputSchemaIssue)
}

///|
#export_name("clientValuesHostTaskResultSchema")
pub fn client_values_host_task_result_schema(
  prepared : @host.PreparedClientProgram,
  result : Int,
) -> Result[Array[String], ClientValuesHostTaskResultSchemaIssue] {
  let graph = @host.prepared_client_graph(prepared)
  guard @strategy.graph_result_task(graph, result) is Some(task) else {
    return Err(MissingResult)
  }
  match
    @host.issue_prepared_client_direct_task_result_root(
      prepared,
      result,
      @host.client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Root(issue))
  }
  let schema = match
    @host.issue_prepared_client_task_output_schema(
      prepared,
      task,
      @host.client_standard_values_sequence_limits(),
      {
        max_fields: 100,
        max_bytes: 1000000,
        max_nodes: 100000,
        max_depth: 100,
      },
      1000000,
      100000,
      100,
    ) {
    Ok(schema) => schema
    Err(issue) => return Err(Schema(issue))
  }
  let facts = [
    @execution.relation_schema_cid(schema),
    @execution.relation_schema_wire(schema),
  ]
  for field in @execution.relation_schema_field_names(schema) {
    facts.push(field)
  }
  Ok(facts)
}

///|
/// The complete checked Result inventory for the single Values task. The
/// flattened triples are name, CID and canonical body in declaration order.
/// These identities do not authorize publication or payload access.
#export_name("clientValuesHostResultDefinitions")
pub fn client_values_host_result_definitions(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientValuesCompilation,
) -> Result[Array[String], @publication.PublicationInventoryIssue] {
  let names = @host.client_values_compilation_result_names(compilation)
  let tasks : Array[Int] = []
  for _ in names {
    tasks.push(0)
  }
  let inventory = match
    @publication.prepare_checked_publication_inventory(
      @host.prepared_client_identity(prepared).program_definition_cid,
      names,
      tasks,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let definitions : Array[String] = []
  for index = 0; index < names.length(); index = index + 1 {
    let name = match
      @publication.checked_publication_inventory_name(inventory, index) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let cid = match
      @publication.checked_publication_inventory_definition_cid(
        inventory, index,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let wire = match
      @publication.checked_publication_inventory_definition_json(
        inventory, index,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    definitions.push(name)
    definitions.push(cid)
    definitions.push(wire)
  }
  Ok(definitions)
}

///|
#export_name("clientValuesHostTaskResultDefinitions")
pub fn client_values_host_task_result_definitions(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientTaskCompilation,
) -> Result[Array[String], @publication.PublicationInventoryIssue] {
  let names = @host.client_task_compilation_result_names(compilation)
  let graph = @host.prepared_client_graph(prepared)
  let tasks : Array[Int] = []
  for index in 0..<names.length() {
    guard @strategy.graph_result_task(graph, index) is Some(task) else {
      return Err(@publication.PublicationInventoryIssue::InvalidTask(index))
    }
    tasks.push(task)
  }
  let inventory = match
    @publication.prepare_checked_publication_inventory(
      @host.prepared_client_identity(prepared).program_definition_cid,
      names,
      tasks,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let definitions : Array[String] = []
  for index in 0..<names.length() {
    let name = match
      @publication.checked_publication_inventory_name(inventory, index) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let cid = match
      @publication.checked_publication_inventory_definition_cid(
        inventory, index,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let wire = match
      @publication.checked_publication_inventory_definition_json(
        inventory, index,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    definitions.push(name)
    definitions.push(cid)
    definitions.push(wire)
  }
  Ok(definitions)
}

///|
/// Issue the no-external-source Observation Set for this compiled Values
/// Template and bind it into a Run Invocation. Policy is Host-issued.
#export_name("clientValuesHostIssueSourceFreeInvocation")
pub fn client_values_host_issue_source_free_invocation(
  compilation : @host.ClientValuesCompilation,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[String], @publication.RunEvidenceValueIssue] {
  let (observation, invocation) = match
    @host.issue_client_values_source_free_invocation(
      compilation, data_policy_cid, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok([
    @publication.run_evidence_value_identity(observation),
    @publication.run_evidence_value_json(observation),
    @publication.publication_contract_identity(invocation),
    @publication.publication_contract_json(invocation),
  ])
}

///|
#export_name("clientValuesHostIssueSourceFreeTaskInvocation")
pub fn client_values_host_issue_source_free_task_invocation(
  compilation : @host.ClientTaskCompilation,
  data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[String], @publication.RunEvidenceValueIssue] {
  let (observation, invocation) = match
    @host.issue_client_task_source_free_invocation(
      compilation, data_policy_cid, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok([
    @publication.run_evidence_value_identity(observation),
    @publication.run_evidence_value_json(observation),
    @publication.publication_contract_identity(invocation),
    @publication.publication_contract_json(invocation),
  ])
}

///|
/// Re-admit observed input wires in the common owner before a task Run may
/// incorporate the source into its Observation Set. The Host supplies the
/// checked source and current scope, not caller-controlled CID assertions.
#export_name("clientValuesHostAdmitCompletedSourceObservation")
pub fn client_values_host_admit_completed_source_observation(
  source_evidence_wire : String,
  input_logical_wire : String,
  source_ref : String,
  source_contract_cid : String,
  authority_scope_cid : String,
  effective_data_policy_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @publication.SourceInputObservationIssue] {
  let source = match
    @publication.admit_run_evidence_value(
      "source_evidence", source_evidence_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) =>
      return Err(@publication.SourceInputObservationIssue::WrongContract)
  }
  let input = match
    @publication.admit_run_evidence_value(
      "source_input_logical", input_logical_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) =>
      return Err(@publication.SourceInputObservationIssue::WrongContract)
  }
  @publication.admit_completed_source_observation_binding(
    source, input, source_ref, source_contract_cid, authority_scope_cid, effective_data_policy_cid,
    max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Form the acquired task Invocation from one completed, checked source
/// observation. The physical Host remains responsible for issuing the source
/// evidence from its live capture and for current provider authorization.
#export_name("clientValuesHostIssueTaskInvocation")
pub fn client_values_host_issue_task_invocation(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
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
) -> Result[Array[String], @publication.RunEvidenceValueIssue] {
  let (observation, invocation) = match
    @host.issue_client_task_invocation(
      prepared, compilation, admission, run_definition, source_evidence_wire, input_logical_wire,
      source_ref, source_contract_cid, authority_scope_cid, data_policy_cid, capture_started_at,
      capture_completed_at, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok([
    @publication.run_evidence_value_identity(observation),
    @publication.run_evidence_value_json(observation),
    @publication.publication_contract_identity(invocation),
    @publication.publication_contract_json(invocation),
  ])
}

///|
#export_name("clientValuesHostAdmitRunEvidenceValue")
pub fn client_values_host_admit_run_evidence_value(
  name : String,
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, @publication.RunEvidenceValueIssue] {
  @publication.admit_run_evidence_value(
    name, wire, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Seal a registered Run evidence body through the common owner. The body
/// excludes its identity field; this does not authorize or publish a Run.
#export_name("clientValuesHostSealRunEvidenceValue")
pub fn client_values_host_seal_run_evidence_value(
  name : String,
  body_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, @publication.RunEvidenceValueIssue] {
  @publication.seal_run_evidence_value(
    name, body_wire, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientValuesHostRunEvidenceValueIdentity")
pub fn client_values_host_run_evidence_value_identity(
  value : @publication.RunEvidenceValue,
) -> String {
  @publication.run_evidence_value_identity(value)
}

///|
#export_name("clientValuesHostRunEvidenceValueWire")
pub fn client_values_host_run_evidence_value_wire(
  value : @publication.RunEvidenceValue,
) -> String {
  @publication.run_evidence_value_json(value)
}

///|
/// The Host must first admit caller input intent and authority scope. This
/// owner then binds the checked Program and effective Parameter Values to the
/// caller request ID; neither the CID nor this handle grants authorization.
#export_name("clientValuesHostRequestIdentity")
pub fn client_values_host_request_identity(
  prepared : @host.PreparedClientProgram,
  authority_scope_cid : String,
  caller_request_id : String,
  caller_input_intent_cid : String,
) -> Result[@host.ClientRequestIdentity, @host.ClientRequestIdentityIssue] {
  @host.prepare_client_request_identity(
    prepared, authority_scope_cid, caller_request_id, caller_input_intent_cid,
  )
}

///|
#export_name("clientValuesHostSourceFreeRequestIdentity")
pub fn client_values_host_source_free_request_identity(
  prepared : @host.PreparedClientProgram,
  authority_scope_cid : String,
  caller_request_id : String,
) -> Result[@host.ClientRequestIdentity, @host.ClientRequestIdentityIssue] {
  @host.prepare_source_free_client_request_identity(
    prepared, authority_scope_cid, caller_request_id,
  )
}

///|
#export_name("clientValuesHostAdmitSourceFreeRequestIdentity")
pub fn client_values_host_admit_source_free_request_identity(
  authority_scope_cid : String,
  caller_request_id : String,
  program_definition_cid : String,
  parameter_values_cid : String,
  caller_input_intent_cid : String,
  logical_request_scope_cid : String,
  intent_fingerprint_cid : String,
) -> Result[@host.ClientRequestIdentity, @host.ClientRequestIdentityIssue] {
  @host.admit_source_free_client_request_identity_record(
    authority_scope_cid, caller_request_id, program_definition_cid, parameter_values_cid,
    caller_input_intent_cid, logical_request_scope_cid, intent_fingerprint_cid,
  )
}

///|
/// Re-admit exactly the fields retained with a durable request. Physical
/// record custody and current caller authorization remain Host duties.
#export_name("clientValuesHostAdmitRequestIdentity")
pub fn client_values_host_admit_request_identity(
  authority_scope_cid : String,
  caller_request_id : String,
  program_definition_cid : String,
  parameter_values_cid : String,
  caller_input_intent_cid : String,
  logical_request_scope_cid : String,
  intent_fingerprint_cid : String,
) -> Result[@host.ClientRequestIdentity, @host.ClientRequestIdentityIssue] {
  @host.admit_client_request_identity_record(
    authority_scope_cid, caller_request_id, program_definition_cid, parameter_values_cid,
    caller_input_intent_cid, logical_request_scope_cid, intent_fingerprint_cid,
  )
}

///|
#export_name("clientValuesHostRequestAuthorityScopeCid")
pub fn client_values_host_request_authority_scope_cid(
  identity : @host.ClientRequestIdentity,
) -> String {
  @host.client_request_authority_scope_cid(identity)
}

///|
#export_name("clientValuesHostRequestCallerId")
pub fn client_values_host_request_caller_id(
  identity : @host.ClientRequestIdentity,
) -> String {
  @host.client_request_caller_id(identity)
}

///|
#export_name("clientValuesHostRequestScopeCid")
pub fn client_values_host_request_scope_cid(
  identity : @host.ClientRequestIdentity,
) -> String {
  @host.client_request_scope_cid(identity)
}

///|
#export_name("clientValuesHostRequestIntentCid")
pub fn client_values_host_request_intent_cid(
  identity : @host.ClientRequestIdentity,
) -> String {
  @host.client_request_intent_cid(identity)
}

///|
#export_name("clientValuesHostRequestProgramCid")
pub fn client_values_host_request_program_cid(
  identity : @host.ClientRequestIdentity,
) -> String {
  @host.client_request_program_cid(identity)
}

///|
#export_name("clientValuesHostRequestParametersCid")
pub fn client_values_host_request_parameters_cid(
  identity : @host.ClientRequestIdentity,
) -> String {
  @host.client_request_parameters_cid(identity)
}

///|
#export_name("clientValuesHostRequestInputCid")
pub fn client_values_host_request_input_cid(
  identity : @host.ClientRequestIdentity,
) -> String {
  @host.client_request_input_cid(identity)
}

///|
/// Different logical key, same checked intent, and changed intent are
/// distinct outcomes. The caller never guesses from transport JSON equality.
#export_name("clientValuesHostRequestRelation")
pub fn client_values_host_request_relation(
  requested : @host.ClientRequestIdentity,
  retained : @host.ClientRequestIdentity,
) -> Int {
  match @host.client_request_identity_relation(requested, retained) {
    DifferentRequest => 0
    SameRequest => 1
    ChangedIntent => 2
  }
}

///|
pub(all) enum ClientValuesHostRunAdmissionIssue {
  Prepared(@publication.RunEvidenceValueIssue)
  Authorization(@publication.RunEvidenceValueIssue)
  Binding(@publication.RunPublicationAdmissionIssue)
}

///|
/// Host policy remains external. Once the Host has authorized this exact
/// caller, the shared owner issues and checks both linked evidence values.
pub struct ClientValuesHostAllowedRun {
  prepared_wire : String
  authorization_wire : String
  admission : @publication.RunPublicationAdmission
}

///|
#export_name("clientValuesHostIssueAllowedRun")
pub fn client_values_host_issue_allowed_run(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientValuesCompilation,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
) -> Result[ClientValuesHostAllowedRun, ClientValuesHostRunAdmissionIssue] {
  let template = @host.client_values_compilation_template(compilation)
  let plan = @host.client_values_compilation_compiled_plan(compilation)
  client_values_host_issue_allowed_run_with_compilation(
    prepared, template, plan, execution_context_cid, host_policy_cid, expires_at,
  )
}

///|
#export_name("clientValuesHostIssueAllowedTaskRun")
pub fn client_values_host_issue_allowed_task_run(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientTaskCompilation,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
) -> Result[ClientValuesHostAllowedRun, ClientValuesHostRunAdmissionIssue] {
  client_values_host_issue_allowed_run_with_compilation(
    prepared,
    @host.client_task_compilation_template(compilation),
    @host.client_task_compilation_compiled_plan(compilation),
    execution_context_cid,
    host_policy_cid,
    expires_at,
  )
}

///|
fn client_values_host_issue_allowed_run_with_compilation(
  prepared : @host.PreparedClientProgram,
  template : @publication.RunEvidenceValue,
  plan : @publication.PublicationContract,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
) -> Result[ClientValuesHostAllowedRun, ClientValuesHostRunAdmissionIssue] {
  let (prepared_value, authorization) = match
    @host.issue_client_allowed_run_evidence(
      template, plan, execution_context_cid, host_policy_cid, expires_at,
    ) {
    Ok(values) => values
    Err(Prepared(issue)) => return Err(Prepared(issue))
    Err(Authorization(issue)) => return Err(Authorization(issue))
  }
  let admission = match
    @host.admit_prepared_client_run_publication(
      prepared, template, prepared_value, authorization, plan,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  Ok({
    prepared_wire: @publication.run_evidence_value_json(prepared_value),
    authorization_wire: @publication.run_evidence_value_json(authorization),
    admission,
  })
}

///|
#export_name("clientValuesHostAllowedRunPreparedWire")
pub fn client_values_host_allowed_run_prepared_wire(
  value : ClientValuesHostAllowedRun,
) -> String {
  value.prepared_wire
}

///|
#export_name("clientValuesHostAllowedRunAuthorizationWire")
pub fn client_values_host_allowed_run_authorization_wire(
  value : ClientValuesHostAllowedRun,
) -> String {
  value.authorization_wire
}

///|
#export_name("clientValuesHostAllowedRunAdmission")
pub fn client_values_host_allowed_run_admission(
  value : ClientValuesHostAllowedRun,
) -> @publication.RunPublicationAdmission {
  value.admission
}

///|
/// The Host supplies current policy and authorization evidence. The common
/// owner admits those values against this exact checked Program and compiler
/// output before any durable Run Definition can be issued.
#export_name("clientValuesHostAdmitRun")
pub fn client_values_host_admit_run(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientValuesCompilation,
  prepared_invocation_wire : String,
  authorization_wire : String,
) -> Result[
  @publication.RunPublicationAdmission,
  ClientValuesHostRunAdmissionIssue,
] {
  let admitted_prepared = match
    @publication.admit_run_evidence_value(
      "prepared_invocation", prepared_invocation_wire, 100000, 10000, 100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Prepared(issue))
  }
  let admitted_authorization = match
    @publication.admit_run_evidence_value(
      "run_authorization", authorization_wire, 100000, 10000, 100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Authorization(issue))
  }
  match
    @host.admit_prepared_client_run_publication(
      prepared,
      @host.client_values_compilation_template(compilation),
      admitted_prepared,
      admitted_authorization,
      @host.client_values_compilation_compiled_plan(compilation),
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Binding(issue))
  }
}

///|
#export_name("clientValuesHostAdmitTaskRun")
pub fn client_values_host_admit_task_run(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientTaskCompilation,
  prepared_invocation_wire : String,
  authorization_wire : String,
) -> Result[
  @publication.RunPublicationAdmission,
  ClientValuesHostRunAdmissionIssue,
] {
  let admitted_prepared = match
    @publication.admit_run_evidence_value(
      "prepared_invocation", prepared_invocation_wire, 100000, 10000, 100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Prepared(issue))
  }
  let admitted_authorization = match
    @publication.admit_run_evidence_value(
      "run_authorization", authorization_wire, 100000, 10000, 100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Authorization(issue))
  }
  @host.admit_prepared_client_run_publication(
    prepared,
    @host.client_task_compilation_template(compilation),
    admitted_prepared,
    admitted_authorization,
    @host.client_task_compilation_compiled_plan(compilation),
  ).map_err(issue => Binding(issue))
}

///|
/// The issued Definition remains private Host material until atomically bound
/// to one retained request. A Definition CID alone grants no start authority.
#export_name("clientValuesHostIssueRunDefinition")
pub fn client_values_host_issue_run_definition(
  admission : @publication.RunPublicationAdmission,
  scope_id : String,
  run_id : String,
  input_artifact_set_cid : String,
  created_at : String,
  valid_until : String,
) -> Result[
  @publication.PublicationContract,
  @publication.RunPublicationAdmissionIssue,
] {
  @publication.issue_run_definition(
    admission, scope_id, run_id, input_artifact_set_cid, created_at, valid_until,
    100000, 10000, 100,
  )
}

///|
pub(all) enum ClientValuesHostSourceFreeDefinitionIssue {
  Definition(@publication.RunPublicationAdmissionIssue)
  Binding(@host.ClientValuesRunBindingIssue)
}

///|
/// Issue only when the checked Program has no captured Run-start inputs.
#export_name("clientValuesHostIssueSourceFreeRunDefinition")
pub fn client_values_host_issue_source_free_run_definition(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientValuesCompilation,
  admission : @publication.RunPublicationAdmission,
  scope_id : String,
  run_id : String,
  created_at : String,
  valid_until : String,
) -> Result[
  @publication.PublicationContract,
  ClientValuesHostSourceFreeDefinitionIssue,
] {
  let definition = match
    @publication.issue_run_definition(
      admission,
      scope_id,
      run_id,
      @publication.empty_initial_input_artifact_set_cid(),
      created_at,
      valid_until,
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Definition(issue))
  }
  match
    @host.bind_source_free_client_values_run(
      prepared, compilation, admission, definition,
    ) {
    Ok(_) => Ok(definition)
    Err(issue) => Err(Binding(issue))
  }
}

///|
pub(all) enum ClientValuesHostTaskDefinitionIssue {
  Definition(@publication.RunPublicationAdmissionIssue)
  Binding(@host.ClientTaskRunBindingIssue)
}

///|
/// Later provider capture is distinct from the empty Run-start Artifact set.
#export_name("clientValuesHostIssueTaskRunDefinition")
pub fn client_values_host_issue_task_run_definition(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  scope_id : String,
  run_id : String,
  created_at : String,
  valid_until : String,
) -> Result[
  @publication.PublicationContract,
  ClientValuesHostTaskDefinitionIssue,
] {
  let definition = match
    @publication.issue_run_definition(
      admission,
      scope_id,
      run_id,
      @publication.empty_initial_input_artifact_set_cid(),
      created_at,
      valid_until,
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Definition(issue))
  }
  match
    @host.bind_client_task_run(prepared, compilation, admission, definition) {
    Ok(_) => Ok(definition)
    Err(issue) => Err(Binding(issue))
  }
}

///|
#export_name("clientValuesHostRunDefinitionWire")
pub fn client_values_host_run_definition_wire(
  definition : @publication.PublicationContract,
) -> String {
  @publication.publication_contract_json(definition)
}

///|
#export_name("clientValuesHostRunDefinitionCid")
pub fn client_values_host_run_definition_cid(
  definition : @publication.PublicationContract,
) -> String {
  @publication.publication_contract_identity(definition)
}

///|
/// Restore exact Run Definition bytes. Its CID is identity, not authority;
/// the Host separately checks current permission before starting work.
#export_name("clientValuesHostAdmitRunDefinition")
pub fn client_values_host_admit_run_definition(
  wire : String,
) -> Result[
  @publication.PublicationContract,
  @publication.PublicationContractIssue,
] {
  @publication.admit_publication_contract(
    "run_definition", wire, 100000, 10000, 100,
  )
}

///|
pub(all) enum ClientValuesHostSourceFreeAdmissionIssue {
  Contract(@publication.PublicationContractIssue)
  Binding(@host.ClientValuesRunBindingIssue)
}

///|
#export_name("clientValuesHostAdmitSourceFreeRunDefinition")
pub fn client_values_host_admit_source_free_run_definition(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientValuesCompilation,
  admission : @publication.RunPublicationAdmission,
  wire : String,
) -> Result[
  @publication.PublicationContract,
  ClientValuesHostSourceFreeAdmissionIssue,
] {
  let definition = match
    @publication.admit_publication_contract(
      "run_definition", wire, 100000, 10000, 100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Contract(issue))
  }
  match
    @host.bind_source_free_client_values_run(
      prepared, compilation, admission, definition,
    ) {
    Ok(_) => Ok(definition)
    Err(issue) => Err(Binding(issue))
  }
}

///|
pub(all) enum ClientValuesHostTaskAdmissionIssue {
  Contract(@publication.PublicationContractIssue)
  Binding(@host.ClientTaskRunBindingIssue)
}

///|
#export_name("clientValuesHostAdmitTaskRunDefinition")
pub fn client_values_host_admit_task_run_definition(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  wire : String,
) -> Result[
  @publication.PublicationContract,
  ClientValuesHostTaskAdmissionIssue,
] {
  let definition = match
    @publication.admit_publication_contract(
      "run_definition", wire, 100000, 10000, 100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Contract(issue))
  }
  match
    @host.bind_client_task_run(prepared, compilation, admission, definition) {
    Ok(_) => Ok(definition)
    Err(issue) => Err(Binding(issue))
  }
}

///|
/// After an atomic reservation the shared owner permits only reconciliation
/// of that same physical Run, including after a lost dispatch response.
#export_name("clientValuesHostPrepareRunStart")
pub fn client_values_host_prepare_run_start(
  requested : @host.ClientRequestIdentity,
  retained : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  retained_run_definition_cid : String,
  dispatch_reserved : Bool,
  current_authorization : Bool,
) -> Result[Int, @host.ClientRunStartIssue] {
  match
    @host.prepare_client_run_start(
      requested, retained, definition, retained_run_definition_cid, dispatch_reserved,
      current_authorization,
    ) {
    Ok(@host.ReserveDispatch) => Ok(0)
    Ok(@host.ReconcileReservedDispatch) => Ok(1)
    Err(issue) => Err(issue)
  }
}

///|
/// Check a restored Definition against the same checked Program, Template,
/// Compiled Plan and Host-issued admission evidence before physical start.
#export_name("clientValuesHostCheckRunBinding")
pub fn client_values_host_check_run_binding(
  prepared : @host.PreparedClientProgram,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
) -> Result[Unit, @publication.RunProgramBindingIssue] {
  let identity = @host.prepared_client_identity(prepared)
  @publication.check_run_publication_program_binding(
    admission,
    definition,
    identity.program_definition_cid,
    @host.prepared_client_program_semantics_cid(prepared),
    @host.prepared_client_check_environment_cid(prepared),
  )
}

///|
/// Project an accepted, unpublished Effect-free Run from the common state
/// owner. The Host supplies durable dispatch observations after restoring the
/// checked Run binding; this operation neither dispatches nor reads payload.
#export_name("clientValuesHostIssueUnpublishedRunStateWire")
pub fn client_values_host_issue_unpublished_run_state_wire(
  definition : @publication.PublicationContract,
  compilation : @host.ClientValuesCompilation,
  observed_at : String,
  dispatch_reserved : Bool,
  pre_dispatch_failure_confirmed : Bool,
  cancelled_before_start : Bool,
  execution_unknown : Bool,
) -> String? {
  let run_id = match @publication.run_definition_run_id(definition) {
    Ok(value) => value
    Err(_) => return None
  }
  let names = @host.client_values_compilation_result_names(compilation)
  match
    @publication.issue_effect_free_unpublished_run_state_wire(
      run_id,
      observed_at,
      names,
      dispatch_reserved,
      pre_dispatch_failure_confirmed,
      100000,
      10000,
      64,
      cancelled_before_start~,
      execution_unknown~,
    ) {
    Ok(wire) => Some(wire)
    Err(_) => None
  }
}

///|
/// Project a committed Run and current per-Result Store observations through
/// the common state validator. The caller must first prove the index commit.
#export_name("clientValuesHostIssueSucceededRunStateWire")
pub fn client_values_host_issue_succeeded_run_state_wire(
  definition : @publication.PublicationContract,
  compilation : @host.ClientValuesCompilation,
  observed_at : String,
  names : Array[String],
  states : Array[String],
  reasons : Array[String],
  result_observed_at : Array[String],
) -> String? {
  let run_id = match @publication.run_definition_run_id(definition) {
    Ok(value) => value
    Err(_) => return None
  }
  match
    @publication.issue_succeeded_run_state_wire(
      run_id,
      observed_at,
      @host.client_values_compilation_result_names(compilation),
      names,
      states,
      reasons,
      result_observed_at,
      100000,
      10000,
      64,
    ) {
    Ok(wire) => Some(wire)
    Err(_) => None
  }
}

///|
/// Retention is an admitted public contract, not an adapter clock rule.
#export_name("clientValuesHostResultReadAvailability")
pub fn client_values_host_result_read_availability(
  manifest : @publication.PublicationContract,
  result_name : String,
  retention : @publication.PublicationContract,
  observed_at : String,
) -> Result[String, @publication.DeliveryIssuanceIssue] {
  @publication.result_read_availability(
    manifest, result_name, retention, observed_at,
  )
}

///|
/// Resolve the committed named Result through the portable publication
/// owner. Store adapters use this projection to open one exact generation.
#export_name("clientValuesHostProjectCommittedResultReadWire")
pub fn client_values_host_project_committed_result_read_wire(
  index : @publication.PublicationContract,
  manifest : @publication.PublicationContract,
  result_name : String,
  bindings : Array[@publication.PublicationContract],
) -> String? {
  let selected = match
    @publication.project_committed_result_read(
      index, manifest, result_name, bindings,
    ) {
    Ok(value) => value
    Err(_) => return None
  }
  let writer = @encode.writer(100000, 10000, 64) catch { _ => return None }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "byte_count")
    @encode.number_value(writer, selected.byte_count.to_double())
    @encode.key(writer, "codec_contract_cid")
    @encode.string_value(writer, selected.codec_contract_cid)
    @encode.key(writer, "durable_result_binding_cid")
    @encode.string_value(writer, selected.durable_result_binding_cid)
    @encode.key(writer, "effective_retention_policy_cid")
    @encode.string_value(writer, selected.effective_retention_policy_cid)
    @encode.key(writer, "logical_result_cid")
    @encode.string_value(writer, selected.logical_result_cid)
    @encode.key(writer, "material_generation_cid")
    @encode.string_value(writer, selected.material_generation_cid)
    @encode.key(writer, "ordering_evidence_cid")
    @encode.string_value(writer, selected.ordering_evidence_cid)
    @encode.key(writer, "physical_sha256")
    @encode.string_value(writer, selected.physical_sha256)
    @encode.key(writer, "result_artifact_cid")
    @encode.string_value(writer, selected.result_artifact_cid)
    @encode.key(writer, "result_definition_cid")
    @encode.string_value(writer, selected.result_definition_cid)
    @encode.key(writer, "result_fields")
    @encode.begin_array(writer)
    for field in selected.result_fields {
      @encode.string_value(writer, field)
    }
    @encode.end_array(writer)
    @encode.key(writer, "result_name")
    @encode.string_value(writer, selected.result_name)
    @encode.key(writer, "result_schema_cid")
    @encode.string_value(writer, selected.result_schema_cid)
    @encode.key(writer, "row_count")
    @encode.number_value(writer, selected.row_count.to_double())
    @encode.key(writer, "store_authority_cid")
    @encode.string_value(writer, selected.store_authority_cid)
    @encode.end_object(writer)
  } catch {
    _ => return None
  }
  Some(@encode.finish(writer) catch { _ => return None })
}

///|
pub(all) enum ClientValuesHostDispatchIssue {
  Binding(@host.ClientValuesRunBindingIssue)
  Dispatch(@host.ClientValuesDispatchIssue)
}

///|
/// Host policy selects a Site, grant and budget before this call. The common
/// owner fixes the checked Run, task, authority and source-free input. This
/// creates an identity only; durable dispatch admission precedes Site I/O.
#export_name("clientValuesHostPrepareDispatch")
pub fn client_values_host_prepare_dispatch(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientValuesCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  request : @host.ClientRequestIdentity,
  task_attempt : Int,
  dispatch_id : String,
  site_key : String,
  site_generation : Int,
  runtime_bundle_cid : String,
  connector_registration : String,
  connector_revision : String,
  strategy_revision : String,
  obligations_cid : String,
  budget_cid : String,
  evidence_issuer_capability_cid : String,
  grant_cid : String,
) -> Result[@remote.DispatchRequest, ClientValuesHostDispatchIssue] {
  let bound = match
    @host.bind_source_free_client_values_run(
      prepared, compilation, admission, definition,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  match
    @host.prepare_source_free_client_values_dispatch(
      bound,
      request,
      task_attempt,
      dispatch_id,
      {
        site_key,
        site_generation,
        runtime_bundle_cid,
        connector_registration,
        connector_revision,
        strategy_revision,
        obligations_cid,
        budget_cid,
        evidence_issuer_capability_cid,
        grant_cid,
      },
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Dispatch(issue))
  }
}

///|
#export_name("clientValuesHostDispatchCid")
pub fn client_values_host_dispatch_cid(
  request : @remote.DispatchRequest,
) -> String {
  @remote.dispatch_request_identity(request)
}

///|
#export_name("clientValuesHostDispatchWire")
pub fn client_values_host_dispatch_wire(
  request : @remote.DispatchRequest,
) -> Result[String, @remote.DispatchIssue] {
  @remote.dispatch_request_json(request)
}

///|
/// Portable publication contract admission for a Host or Store adapter.
/// Admission checks the canonical body and self identity; it grants no read
/// or publication authority.
#export_name("clientValuesHostAdmitPublicationContract")
pub fn client_values_host_admit_publication_contract(
  name : String,
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  @publication.PublicationContractIssue,
] {
  @publication.admit_publication_contract(
    name, wire, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientValuesHostPublicationContractIdentity")
pub fn client_values_host_publication_contract_identity(
  contract : @publication.PublicationContract,
) -> String {
  @publication.publication_contract_identity(contract)
}

///|
#export_name("clientValuesHostPublicationContractWire")
pub fn client_values_host_publication_contract_wire(
  contract : @publication.PublicationContract,
) -> String {
  @publication.publication_contract_json(contract)
}

///|
/// The owner derives the complete named inventory; the adapter cannot
/// substitute an arbitrary Manifest for admitted Definitions and Artifacts.
#export_name("clientValuesHostIssueResultManifest")
pub fn client_values_host_issue_result_manifest(
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  @publication.ResultManifestIssuanceIssue,
] {
  @publication.issue_result_manifest(
    run_definition, invocation, definitions, artifacts, max_wire_bytes, max_nodes,
    max_depth,
  )
}

///|
/// The Host supplies identities from the checked Result export and current
/// policy; the shared owner seals the derivation and occurrence witness.
#export_name("clientValuesHostIssueResultOccurrenceEvidence")
pub fn client_values_host_issue_result_occurrence_evidence(
  definition : @publication.PublicationContract,
  logical_value_cid : String,
  result_schema_cid : String,
  computation_contract_cid : String,
  input_relation_cids : Array[String],
  scope_cid : String,
  effective_data_policy_cid : String,
  issuer_id : String,
  authority_scope_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.ResultOrderingEvidence,
  @publication.ResultEvidenceIssuanceIssue,
] {
  @publication.issue_result_occurrence_evidence(
    definition, logical_value_cid, result_schema_cid, computation_contract_cid, input_relation_cids,
    scope_cid, effective_data_policy_cid, issuer_id, authority_scope_cid, max_wire_bytes,
    max_nodes, max_depth,
  )
}

///|
pub(all) enum ClientValuesHostCheckedOccurrenceIssue {
  Definition(@publication.ResultDefinitionIssue)
  ForeignResult
  ResultSchema(@host.ClientValuesOutputSchemaIssue)
  ResultSchemaMismatch
  Issuance(@publication.ResultEvidenceIssuanceIssue)
}

///|
/// Bind one source-free Values occurrence to its checked Result, output
/// schema and Compiled Plan. Site selection and dispatch remain separate.
#export_name("clientValuesHostIssueCheckedValuesResultOccurrenceEvidence")
pub fn client_values_host_issue_checked_values_result_occurrence_evidence(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientValuesCompilation,
  definition : @publication.PublicationContract,
  logical_value_cid : String,
  result_schema_cid : String,
  scope_cid : String,
  effective_data_policy_cid : String,
  issuer_id : String,
  authority_scope_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.ResultOrderingEvidence,
  ClientValuesHostCheckedOccurrenceIssue,
] {
  let admitted = match
    @publication.admit_result_definition(
      @publication.publication_contract_json(definition),
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Definition(issue))
  }
  if @publication.result_definition_program_cid(admitted) !=
    @host.prepared_client_identity(prepared).program_definition_cid ||
    !@host.client_values_compilation_result_names(compilation).contains(
      @publication.result_definition_name(admitted),
    ) {
    return Err(ForeignResult)
  }
  let schema = match
    @host.issue_prepared_client_values_output_schema(
      prepared,
      0,
      @host.client_standard_values_sequence_limits(),
      {
        max_fields: 100,
        max_bytes: 1000000,
        max_nodes: 100000,
        max_depth: 100,
      },
      1000000,
      100000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ResultSchema(issue))
  }
  if result_schema_cid != @execution.relation_schema_cid(schema) {
    return Err(ResultSchemaMismatch)
  }
  match
    @publication.issue_result_occurrence_evidence(
      definition,
      logical_value_cid,
      result_schema_cid,
      @publication.publication_contract_identity(
        @host.client_values_compilation_compiled_plan(compilation),
      ),
      [],
      scope_cid,
      effective_data_policy_cid,
      issuer_id,
      authority_scope_cid,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Issuance(issue))
  }
}

///|
#export_name("clientValuesHostResultOccurrenceDerivation")
pub fn client_values_host_result_occurrence_derivation(
  evidence : @publication.ResultOrderingEvidence,
) -> @publication.PublicationContract {
  @publication.result_ordering_derivation_contract(evidence)
}

///|
#export_name("clientValuesHostResultOccurrenceOrdering")
pub fn client_values_host_result_occurrence_ordering(
  evidence : @publication.ResultOrderingEvidence,
) -> @publication.PublicationContract {
  @publication.result_ordering_evidence_contract(evidence)
}

///|
/// The Result Artifact is issued from admitted invocation, retention and
/// owner-sealed ordering evidence, never from an adapter-built body.
#export_name("clientValuesHostIssueCompleteResultArtifact")
pub fn client_values_host_issue_complete_result_artifact(
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  evidence : @publication.ResultOrderingEvidence,
  retention : @publication.PublicationContract,
  actual_row_count : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  @publication.ResultArtifactIssuanceIssue,
] {
  @publication.issue_complete_result_artifact(
    definition, invocation, evidence, retention, actual_row_count, max_wire_bytes,
    max_nodes, max_depth,
  )
}

///|
/// Store physical observations are supplied after independent holding and
/// verification; the owner validates semantic references before issuance.
#export_name("clientValuesHostIssueDurableResultBinding")
pub fn client_values_host_issue_durable_result_binding(
  run_definition : @publication.PublicationContract,
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  artifact : @publication.PublicationContract,
  ordering : @publication.PublicationContract,
  retention : @publication.PublicationContract,
  codec_contract_cid : String,
  result_fields : Array[String],
  result_schema_wire : String,
  material_generation_cid : String,
  store_authority_cid : String,
  row_count : Int,
  byte_count : Int,
  physical_sha256 : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  @publication.DurableResultBindingIssue,
] {
  @publication.issue_durable_result_binding(
    run_definition, definition, invocation, artifact, ordering, retention, codec_contract_cid,
    result_fields, result_schema_wire, material_generation_cid, store_authority_cid,
    row_count, byte_count, physical_sha256, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// A physical Store calls this on its own bounded bytes. No bulk payload
/// needs to return to the Coordinator merely to establish logical identity.
#export_name("clientValuesHostInspectCanonicalResultRows")
pub fn client_values_host_inspect_canonical_result_rows(
  rows_wire : String,
  fields : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[String], @publication.CapturedRunIssuanceIssue] {
  match
    @publication.inspect_canonical_result_rows(
      rows_wire, fields, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok((cid, count)) => Ok([cid, count.to_string()])
    Err(issue) => Err(issue)
  }
}

///|
/// The shared owner checks the exact Named Result inventory and references.
#export_name("clientValuesHostValidatePublicationChain")
pub fn client_values_host_validate_publication_chain(
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, @publication.RunPublicationChainIssue] {
  @publication.validate_run_publication_chain(
    run_definition, invocation, definitions, artifacts, manifest, max_wire_bytes,
    max_nodes, max_depth,
  )
}

///|
/// Physical CAS and durable write remain Store effects.
#export_name("clientValuesHostValidatePublicationRecordTransition")
pub fn client_values_host_validate_publication_record_transition(
  previous : @publication.PublicationContract?,
  next : @publication.PublicationContract,
  uncommitted_confirmed : Bool,
) -> Result[Unit, @publication.PublicationTransitionIssue] {
  @publication.validate_publication_record_transition(
    previous, next, uncommitted_confirmed,
  )
}

///|
/// The Host supplies one checked inventory and policy decision. The portable
/// owner fixes the publication request identity and its canonical order.
#export_name("clientValuesHostIssuePublicationRequest")
pub fn client_values_host_issue_publication_request(
  run_definition : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  tenant_id : String,
  authority_scope_cid : String,
  publication_policy_cid : String,
  publication_target_cid : String,
  requested_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  @publication.PublicationCommitIssuanceIssue,
] {
  @publication.issue_publication_request(
    run_definition, definitions, tenant_id, authority_scope_cid, publication_policy_cid,
    publication_target_cid, requested_at, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Attempt identity is immutable; outcome and physical Store CAS are separate.
#export_name("clientValuesHostIssuePublicationAttempt")
pub fn client_values_host_issue_publication_attempt(
  request : @publication.PublicationContract,
  run_definition : @publication.PublicationContract,
  attempt_id : String,
  fence_cid : String,
  external_idempotency_key : String?,
  started_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  @publication.PublicationCommitIssuanceIssue,
] {
  @publication.issue_publication_attempt(
    request, run_definition, attempt_id, fence_cid, external_idempotency_key, started_at,
    max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// This exact entry still requires the Store to validate and commit the full
/// chain atomically before a Host may report publication success.
#export_name("clientValuesHostIssuePublicIndexEntry")
pub fn client_values_host_issue_public_index_entry(
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
  durable_bindings : Array[@publication.PublicationContract],
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  committed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  @publication.PublicationCommitIssuanceIssue,
] {
  @publication.issue_public_index_entry(
    run_definition, invocation, manifest, receipt, captured_run, durable_bindings,
    request, attempt, committed_at, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Before a Store installs the public index, validate the entire captured
/// Effect-free chain and its exact publication request and attempt.
#export_name("clientValuesHostValidateEffectFreePublicationCommit")
pub fn client_values_host_validate_effect_free_publication_commit(
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  derivations : Array[@publication.PublicationContract],
  orderings : Array[@publication.PublicationContract],
  retentions : Array[@publication.PublicationContract],
  bindings : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  index_entry : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, @publication.PublicationCommitIssue] {
  @publication.validate_effect_free_publication_commit_with_result_evidence(
    run_definition, invocation, definitions, artifacts, derivations, orderings, retentions,
    bindings, manifest, receipt, captured_run, request, attempt, index_entry, max_wire_bytes,
    max_nodes, max_depth,
  )
}

///|
/// Sequence and predecessor are derived by the portable publication owner.
#export_name("clientValuesHostIssuePublicationRecord")
pub fn client_values_host_issue_publication_record(
  attempt : @publication.PublicationContract,
  previous : @publication.PublicationContract?,
  state : String,
  observed_at : String,
  public_index_entry : @publication.PublicationContract?,
  failure_cid : String?,
  cleanup_owner_cids : Array[String],
  uncommitted_confirmed : Bool,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  @publication.PublicationCommitIssuanceIssue,
] {
  @publication.issue_publication_record(
    attempt, previous, state, observed_at, public_index_entry, failure_cid, cleanup_owner_cids,
    uncommitted_confirmed, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// The shared issuer checks the complete Effect-free Run evidence chain.
#export_name("clientValuesHostIssueEffectFreeRunReceipt")
pub fn client_values_host_issue_effect_free_run_receipt(
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  normalization_journal : @publication.RunEvidenceValue,
  binding_names : Array[String],
  binding_digests : Array[String],
  source_evidence : Array[@publication.RunEvidenceValue],
  model_evidence : Array[@publication.RunEvidenceValue],
  barrier_attempt_receipt_cids : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  @publication.RunReceiptIssuanceIssue,
] {
  @publication.issue_effect_free_run_receipt(
    admission, run_definition, invocation, observation, definitions, artifacts, manifest,
    normalization_journal, binding_names, binding_digests, source_evidence, model_evidence,
    barrier_attempt_receipt_cids, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Captured rows must match the previously issued logical Result Artifact.
#export_name("clientValuesHostAdmitCapturedResultSnapshot")
pub fn client_values_host_admit_captured_result_snapshot(
  definition : @publication.PublicationContract,
  artifact : @publication.PublicationContract,
  rows_wire : String,
  fields : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.CapturedResultSnapshot,
  @publication.CapturedRunIssuanceIssue,
] {
  @publication.admit_captured_result_snapshot(
    definition, artifact, rows_wire, fields, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
/// Source-free capture has no pending source-state advances. Other capture
/// modes must expose their checked advances through a separate shared API.
#export_name("clientValuesHostIssueSourceFreeCapturedRun")
pub fn client_values_host_issue_source_free_captured_run(
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  snapshots : Array[@publication.CapturedResultSnapshot],
  authoring : @publication.RunEvidenceValue,
  models : Array[@publication.RunEvidenceValue],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  @publication.CapturedRunIssuanceIssue,
] {
  @publication.issue_effect_free_captured_run(
    run_definition,
    invocation,
    definitions,
    artifacts,
    manifest,
    receipt,
    snapshots,
    [],
    authoring,
    models,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Restore admitted Site facts and bind them to this checked Run and task.
/// Projection cannot dispatch, claim a retry or release physical resources.
#export_name("clientValuesHostProjectSiteRun")
pub fn client_values_host_project_site_run(
  definition : @publication.PublicationContract,
  compilation : @host.ClientValuesCompilation,
  authority : String,
  durable_wire : String,
  observed_at : String,
  cancellation_requested : Bool,
  physical_start_claimed : Bool,
) -> Result[Array[String], Unit] {
  let durable = match
    @remote.admit_durable_coordinator_dispatch_record(
      @utf8.encode(durable_wire),
    ) {
    Ok(value) => value
    Err(_) => return Err(())
  }
  let journal = match @remote.create_coordinator_dispatch_journal(authority) {
    Ok(value) => value
    Err(_) => return Err(())
  }
  let record = match
    @remote.restore_durable_coordinator_dispatch_record(journal, durable) {
    Ok(value) => value
    Err(_) => return Err(())
  }
  let observation = match
    @remote.coordinator_execution_observation(
      record,
      authority,
      @publication.publication_contract_identity(definition),
      @host.client_values_compilation_plan_node_id(compilation),
    ) {
    Ok(value) => value
    Err(_) => return Err(())
  }
  let run_id = match @publication.run_definition_run_id(definition) {
    Ok(value) => value
    Err(_) => return Err(())
  }
  let terminal = match observation.execution {
    Some(@remote.ExecutionFailed) => Some(@publication.RunOutcomeStatus::Failed)
    Some(@remote.ExecutionCancelled) =>
      Some(@publication.RunOutcomeStatus::Cancelled)
    Some(@remote.NativeSettled) if cancellation_requested &&
      observation.cleanup_complete =>
      Some(@publication.RunOutcomeStatus::Cancelled)
    _ => None
  }
  let state = match
    @publication.issue_effect_free_unpublished_run_state_wire(
      run_id,
      observed_at,
      @host.client_values_compilation_result_names(compilation),
      true,
      false,
      100000,
      10000,
      64,
      observed_terminal_outcome=terminal,
      execution_unknown=observation.execution is Some(@remote.ExecutionUnknown) ||
        (physical_start_claimed && observation.execution is None),
    ) {
    Ok(value) => value
    Err(_) => return Err(())
  }
  let execution = match observation.execution {
    None if physical_start_claimed => "unknown"
    None => "unobserved"
    Some(@remote.Accepted | @remote.Provisioning | @remote.Running) => "running"
    Some(@remote.NativeSettled) => "settled"
    Some(@remote.ExecutionFailed) => "failed"
    Some(@remote.ExecutionCancelled) => "cancelled"
    Some(@remote.ExecutionUnknown) => "unknown"
  }
  let work = if terminal is Some(_) {
    if observation.cleanup_complete {
      "none"
    } else {
      "cleanup"
    }
  } else if cancellation_requested {
    if observation.execution_terminal {
      "release"
    } else {
      "cancel"
    }
  } else if observation.execution is Some(@remote.NativeSettled) {
    "publication"
  } else {
    "reconcile"
  }
  Ok([
    state,
    execution,
    if observation.cleanup_complete {
      "complete"
    } else {
      "pending"
    },
    observation.revision.to_string(),
    work,
  ])
}

///|
#export_name("clientValuesHostPreparePhysicalStart")
pub fn client_values_host_prepare_physical_start(
  requested : @host.ClientRequestIdentity,
  retained : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  definition_cid : String,
  reserved : Bool,
  unstarted : Bool,
  authorized : Bool,
  cancellation_requested : Bool,
  pre_start_failure_confirmed : Bool,
) -> Result[Bool, @host.ClientRunStartIssue] {
  @host.prepare_client_run_physical_start(
    requested,
    retained,
    definition,
    definition_cid,
    reserved,
    unstarted,
    authorized,
    cancellation_requested~,
    pre_start_failure_confirmed~,
  )
}

///|
#export_name("clientValuesHostPreparePreStartFailure")
pub fn client_values_host_prepare_pre_start_failure(
  requested : @host.ClientRequestIdentity,
  retained : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  definition_cid : String,
  reserved : Bool,
  unstarted : Bool,
  admission_denied : Bool,
  cancellation_requested : Bool,
) -> Result[Bool, @host.ClientRunStartIssue] {
  @host.prepare_client_run_pre_start_failure(
    requested, retained, definition, definition_cid, reserved, unstarted, admission_denied,
    cancellation_requested,
  )
}

///|
#export_name("clientValuesHostPrepareCancellation")
pub fn client_values_host_prepare_cancellation(
  definition : @publication.PublicationContract,
  definition_cid : String,
  authorized : Bool,
  terminal : Bool,
  requested : Bool,
) -> Result[String, @host.ClientRunStartIssue] {
  match
    @host.prepare_client_run_cancellation(
      definition, definition_cid, authorized, terminal, requested,
    ) {
    Ok(@host.AcceptCancellation) => Ok("accepted")
    Ok(@host.AlreadyRequested) => Ok("already_requested")
    Ok(@host.AlreadyTerminal) => Ok("already_terminal")
    Err(issue) => Err(issue)
  }
}

///|
#export_name("clientValuesHostRunControlObservation")
pub fn client_values_host_run_control_observation(
  revision : Int,
  requested : Bool,
  unstarted : Bool,
  stopped : Bool,
) -> Result[String, @publication.RunStateIssue] {
  @publication.issue_run_control_observation_wire(
    revision, requested, unstarted, false, stopped,
  )
}
