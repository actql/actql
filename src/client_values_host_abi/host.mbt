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
