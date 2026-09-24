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
