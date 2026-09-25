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
  let wire = match
    @environment.read(@utf8.encode(body), evidence_bundle_cid, {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 64,
      max_members: 256,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  Some(
    @checked.checking_environment(wire, { text_time, veca, }, {
      rela,
      sga,
      tea,
      calendar,
      text_rank,
    }),
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
  let snapshot = match @publication.project_publication_snapshot(record, observed) {
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
    tenant_id, authority_scope_cid, run_definition_cid, max_wire_bytes,
    max_nodes, max_depth,
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
      { max_fields: 100, max_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
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
  let template = @host.client_values_compilation_template(compilation)
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(@publication.RunEvidenceValueIssue::RunEvidenceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "capture_completed_at")
    @encode.null_value(writer)
    @encode.key(writer, "capture_started_at")
    @encode.null_value(writer)
    @encode.key(writer, "captured_input_artifact_cids")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.key(writer, "consistency")
    @encode.string_value(writer, "no_external_sources")
    @encode.key(writer, "data_policy_cid")
    @encode.string_value(writer, data_policy_cid)
    @encode.key(writer, "invocation_template_cid")
    @encode.string_value(writer, @publication.run_evidence_value_identity(template))
    @encode.key(writer, "replayability")
    @encode.begin_object(writer)
    @encode.key(writer, "availability_evidence_cids")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.key(writer, "materialized")
    @encode.bool_value(writer, false)
    @encode.end_object(writer)
    @encode.key(writer, "source_evidence_cids")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-observation-set/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(@publication.RunEvidenceValueIssue::RunEvidenceEncoding)
  }
  let body = @encode.finish(writer) catch {
    _ => return Err(@publication.RunEvidenceValueIssue::RunEvidenceEncoding)
  }
  let observation = match
    @publication.seal_run_evidence_value(
      "observation_set", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let invocation = match
    @publication.issue_run_invocation(
      template, observation, max_wire_bytes, max_nodes, max_depth,
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
  let prepared_value = match
    @publication.seal_run_evidence_value(
      "prepared_invocation",
      "{\"version\":\"actql-prepared-invocation/0.1\"," +
      "\"invocation_template_cid\":\"" +
      @publication.run_evidence_value_identity(template) +
      "\",\"compiled_plan_cid\":\"" +
      @publication.publication_contract_identity(plan) +
      "\",\"execution_context_cid\":\"" +
      execution_context_cid +
      "\",\"host_policy_cid\":\"" +
      host_policy_cid +
      "\",\"policy_decision\":\"allow\",\"expires_at\":\"" +
      expires_at +
      "\"}",
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Prepared(issue))
  }
  let authorization = match
    @publication.seal_run_evidence_value(
      "run_authorization",
      "{\"version\":\"actql-run-authorization/0.1\"," +
      "\"prepared_invocation_cid\":\"" +
      @publication.run_evidence_value_identity(prepared_value) +
      "\",\"execution_context_cid\":\"" +
      execution_context_cid +
      "\",\"host_policy_cid\":\"" +
      host_policy_cid +
      "\",\"decision\":\"allowed\"}",
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Authorization(issue))
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
) -> Result[@publication.PublicationContract, @publication.PublicationContractIssue] {
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
) -> Result[@publication.PublicationContract, @publication.ResultManifestIssuanceIssue] {
  @publication.issue_result_manifest(
    run_definition, invocation, definitions, artifacts,
    max_wire_bytes, max_nodes, max_depth,
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
) -> Result[@publication.ResultOrderingEvidence, @publication.ResultEvidenceIssuanceIssue] {
  @publication.issue_result_occurrence_evidence(
    definition, logical_value_cid, result_schema_cid,
    computation_contract_cid, input_relation_cids, scope_cid,
    effective_data_policy_cid, issuer_id, authority_scope_cid,
    max_wire_bytes, max_nodes, max_depth,
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
) -> Result[@publication.ResultOrderingEvidence, ClientValuesHostCheckedOccurrenceIssue] {
  let admitted = match @publication.admit_result_definition(
    @publication.publication_contract_json(definition), max_wire_bytes,
    max_nodes, max_depth,
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
  let schema = match @host.issue_prepared_client_values_output_schema(
    prepared, 0, @host.client_standard_values_sequence_limits(),
    { max_fields: 100, max_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
    1000000, 100000, 100,
  ) {
    Ok(value) => value
    Err(issue) => return Err(ResultSchema(issue))
  }
  if result_schema_cid != @execution.relation_schema_cid(schema) {
    return Err(ResultSchemaMismatch)
  }
  match @publication.issue_result_occurrence_evidence(
    definition, logical_value_cid, result_schema_cid,
    @publication.publication_contract_identity(
      @host.client_values_compilation_compiled_plan(compilation),
    ),
    [], scope_cid, effective_data_policy_cid, issuer_id,
    authority_scope_cid, max_wire_bytes, max_nodes, max_depth,
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
) -> Result[@publication.PublicationContract, @publication.ResultArtifactIssuanceIssue] {
  @publication.issue_complete_result_artifact(
    definition, invocation, evidence, retention, actual_row_count,
    max_wire_bytes, max_nodes, max_depth,
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
) -> Result[@publication.PublicationContract, @publication.DurableResultBindingIssue] {
  @publication.issue_durable_result_binding(
    run_definition, definition, invocation, artifact, ordering, retention,
    codec_contract_cid, result_fields, result_schema_wire,
    material_generation_cid, store_authority_cid, row_count, byte_count,
    physical_sha256, max_wire_bytes, max_nodes, max_depth,
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
    run_definition, invocation, definitions, artifacts, manifest,
    max_wire_bytes, max_nodes, max_depth,
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
