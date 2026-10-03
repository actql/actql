///|
/// Bounds for admitting one run materials body. Every body is checked by its
/// existing owner with these limits; nothing is read in full before it is
/// bounded.
pub(all) struct ClientValuesRunMaterialsLimits {
  preparation : ClientProgramPreparationLimits
  sequence : @lower.SequenceLimits
  max_sequence_steps : Int
  max_sequence_work : Int
  max_evidence_bytes : Int
  max_evidence_nodes : Int
  max_evidence_depth : Int
}

///|
pub(all) enum ClientValuesRunMaterialsIssue {
  /// Not an `actql-remote-run-materials/0.1` object of the exact fields.
  MaterialsMalformed
  /// The check environment is not admitted with this Site's profiles.
  MaterialsEnvironment
  MaterialsParameters
  MaterialsProgram(ClientProgramPreparationIssue)
  MaterialsCompilation(ClientValuesCompilationIssue)
  /// A prepared invocation or Run authorization body is not that evidence.
  MaterialsEvidence(String)
  MaterialsAdmission(@publication.RunPublicationAdmissionIssue)
  MaterialsDefinition(@publication.RunPublicationAdmissionIssue)
  /// The rebuilt Run is not the Run the dispatch names.
  MaterialsRunMismatch
  MaterialsBinding(ClientValuesRunBindingIssue)
}

///|
/// A source-free Values Run rebuilt by this Site from typed run materials.
/// It proves only that the materials describe the dispatched Run; execution
/// is still admitted by the Site's own delegation, grant and capacity.
pub(all) struct ClientValuesRunMaterials {
  prepared : PreparedClientProgram
  compilation : ClientValuesCompilation
  admission : @publication.RunPublicationAdmission
  run_definition : @publication.PublicationContract
}

///|
let client_run_materials_fields : Array[String] = [
  "check_environment", "check_environment_cid", "created_at", "parameters", "prepared_invocation",
  "program", "program_format", "run_authorization", "run_id", "scope_id", "valid_until",
  "version",
]

///|
/// Project an existing source-free Run, never compile a replacement Plan or
/// issue new authority. The retained input is checked against the original
/// checked identity; the existing compilation, admission and definition remain
/// the only owners of the executable Run. JSON quoting counts against the wire
/// cap, independently of the bounds of each retained input body.
pub fn issue_client_values_run_materials(
  prepared : PreparedClientProgram,
  compilation : ClientValuesCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  environment : @checked.CheckEnvironment,
  environment_wire : String,
  program : String,
  parameters_wire : String?,
) -> Result[String, ClientValuesRunMaterialsIssue] {
  match
    bind_source_free_client_values_run(
      prepared, compilation, admission, definition,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(MaterialsBinding(issue))
  }
  issue_client_run_materials_input(
    prepared, admission, definition, environment, environment_wire, program, parameters_wire,
  )
}

///|
// Both compilation owners project the same bounded original Run body.
fn issue_client_run_materials_input(
  prepared : PreparedClientProgram,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  environment : @checked.CheckEnvironment,
  environment_wire : String,
  program : String,
  parameters_wire : String?,
) -> Result[String, ClientValuesRunMaterialsIssue] {
  let environment_cid = @checked.checking_environment_cid(environment)
  guard environment_cid == prepared_client_check_environment_cid(prepared) &&
    @environment.read(@utf8.encode(environment_wire), environment_cid, {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 64,
      max_members: 256,
    })
    is Ok(_) else {
    return Err(MaterialsEnvironment)
  }
  let parameters = match parameters_wire {
    None => None
    Some(body) => {
      let parsed = match
        @source.parse_json_bytes(
          @utf8.encode(body),
          { max_input_bytes: 65536, max_nodes: 8192, max_depth: 64, },
          source_path="Retained Run Parameters",
        ) {
        Ok(value) => value
        Err(_) => return Err(MaterialsParameters)
      }
      match
        @decode.admit(parsed, {
          max_nodes: 8192,
          max_depth: 64,
          max_string_bytes: 65536,
          max_total_string_bytes: 65536,
        }) {
        Ok(value) => Some(value)
        Err(_) => return Err(MaterialsParameters)
      }
    }
  }
  let checked_input = match
    prepare_effect_free_client_program(
      program,
      Json,
      environment,
      parameters,
      client_standard_program_preparation_limits(),
    ) {
    Ok(value) => value
    Err(issue) => return Err(MaterialsProgram(issue))
  }
  guard prepared_client_identity(checked_input) ==
    prepared_client_identity(prepared) else {
    return Err(MaterialsRunMismatch)
  }
  // This is a read-only projection of an already admitted definition. It does
  // not reissue it (nor extend its original lifetime).
  let parsed = match
    @source.parse_json_bytes(
      @utf8.encode(@publication.publication_contract_json(definition)),
      { max_input_bytes: 100000, max_nodes: 10000, max_depth: 100, },
      source_path="Owned Run Definition",
    ) {
    Ok(value) => value
    Err(_) => return Err(MaterialsMalformed)
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: 10000,
      max_depth: 100,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    }) {
    Ok(value) => value
    Err(_) => return Err(MaterialsMalformed)
  }
  let object = match @decode.open_object(root) {
    Ok(value) => value
    Err(_) => return Err(MaterialsMalformed)
  }
  let text = fn(name : String) -> String? {
    match @decode.lookup(object, name) {
      Some(cursor) => @decode.text(cursor).to_option()
      None => None
    }
  }
  let fields : Array[(String, String?)] = [
    ("check_environment", Some(environment_wire)),
    ("check_environment_cid", Some(environment_cid)),
    ("created_at", text("created_at")),
    ("parameters", parameters_wire),
    (
      "prepared_invocation",
      Some(
        @publication.run_evidence_value_json(
          @publication.run_publication_prepared(admission),
        ),
      ),
    ),
    ("program", Some(program)),
    ("program_format", Some("json")),
    (
      "run_authorization",
      Some(
        @publication.run_evidence_value_json(
          @publication.run_publication_authorization(admission),
        ),
      ),
    ),
    ("run_id", text("run_id")),
    ("scope_id", text("scope_id")),
    ("valid_until", text("valid_until")),
    ("version", Some("actql-remote-run-materials/0.1")),
  ]
  let writer = @encode.writer(@remote.REMOTE_RUN_MATERIALS_MAX_BYTES, 32, 2) catch {
    _ => return Err(MaterialsMalformed)
  }
  try {
    @encode.begin_object(writer)
    for field in fields {
      @encode.key(writer, field.0)
      match field.1 {
        Some(value) => @encode.string_value(writer, value)
        None =>
          if field.0 == "parameters" {
            @encode.null_value(writer)
          } else {
            return Err(MaterialsMalformed)
          }
      }
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(MaterialsMalformed)
  }
}

///|
// Bounded retained inputs for both compilation owners.
priv struct ClientRunMaterialsInput {
  prepared : PreparedClientProgram
  prepared_wire : String
  authorization_wire : String
  scope_id : String
  run_id : String
  created_at : String
  valid_until : String
}

///|
// Parsing/checking is shared; no caller-supplied compilation or authority is
// accepted from the materials.
fn read_client_run_materials_input(
  materials : String,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  limits : ClientValuesRunMaterialsLimits,
) -> Result[ClientRunMaterialsInput, ClientValuesRunMaterialsIssue] {
  let parsed = match
    @source.parse_json_bytes(
      @utf8.encode(materials),
      {
        max_input_bytes: @remote.REMOTE_RUN_MATERIALS_MAX_BYTES,
        max_nodes: 32,
        max_depth: 2,
      },
      source_path="Run Materials",
    ) {
    Ok(value) => value
    Err(_) => return Err(MaterialsMalformed)
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: 32,
      max_depth: 2,
      max_string_bytes: @remote.REMOTE_RUN_MATERIALS_MAX_BYTES,
      max_total_string_bytes: @remote.REMOTE_RUN_MATERIALS_MAX_BYTES,
    }) {
    Ok(value) => value
    Err(_) => return Err(MaterialsMalformed)
  }
  let object = match @decode.closed_object(root, client_run_materials_fields) {
    Ok(value) => value
    Err(_) => return Err(MaterialsMalformed)
  }
  let text = fn(name : String) -> String? {
    match @decode.lookup(object, name) {
      Some(cursor) => @decode.text(cursor).to_option()
      None => None
    }
  }
  guard text("version") == Some("actql-remote-run-materials/0.1") &&
    text("program_format") == Some("json") &&
    text("program") is Some(program) &&
    text("check_environment") is Some(environment_wire) &&
    text("check_environment_cid") is Some(environment_cid) &&
    text("prepared_invocation") is Some(prepared_wire) &&
    text("run_authorization") is Some(authorization_wire) &&
    text("scope_id") is Some(scope_id) &&
    text("run_id") is Some(run_id) &&
    text("created_at") is Some(created_at) &&
    text("valid_until") is Some(valid_until) &&
    @decode.lookup(object, "parameters") is Some(parameters_cursor) else {
    return Err(MaterialsMalformed)
  }
  let parameters = if @decode.is_null(parameters_cursor) {
    None
  } else {
    match @decode.text(parameters_cursor) {
      Ok(body) => {
        let node = match
          @source.parse_json_bytes(
            @utf8.encode(body),
            { max_input_bytes: 65536, max_nodes: 8192, max_depth: 64, },
            source_path="Run Materials Parameters",
          ) {
          Ok(value) => value
          Err(_) => return Err(MaterialsParameters)
        }
        match
          @decode.admit(node, {
            max_nodes: 8192,
            max_depth: 64,
            max_string_bytes: 65536,
            max_total_string_bytes: 65536,
          }) {
          Ok(value) => Some(value)
          Err(_) => return Err(MaterialsParameters)
        }
      }
      Err(_) => return Err(MaterialsMalformed)
    }
  }
  guard admit_client_check_environment(
      environment_wire, environment_cid, expressions, operations,
    )
    is Some(environment) else {
    return Err(MaterialsEnvironment)
  }
  let prepared = match
    prepare_effect_free_client_program(
      program,
      Json,
      environment,
      parameters,
      limits.preparation,
    ) {
    Ok(value) => value
    Err(issue) => return Err(MaterialsProgram(issue))
  }
  Ok({
    prepared,
    prepared_wire,
    authorization_wire,
    scope_id,
    run_id,
    created_at,
    valid_until,
  })
}

///|
/// Rebuild a source-free Values Run from `actql-remote-run-materials/0.1`
/// and admit it only when its Run definition CID equals
/// `expected_run_definition_cid`.
///
/// The Program, check environment and parameters are checked again here; the
/// compiled Plan and invocation template are recomputed by the ordinary
/// compiler and are never taken from the materials. The prepared invocation
/// and Run authorization are received evidence, admitted by their owners and
/// never issued by this Site. The CID match is an identity check, not an
/// execution permission.
pub fn admit_client_values_run_materials(
  materials : String,
  expected_run_definition_cid : String,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  manifests : ClientCompilationManifests,
  limits : ClientValuesRunMaterialsLimits,
) -> Result[ClientValuesRunMaterials, ClientValuesRunMaterialsIssue] {
  let input = match
    read_client_run_materials_input(materials, expressions, operations, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  admit_client_values_run_materials_input(
    input, expected_run_definition_cid, manifests, limits,
  )
}

///|
fn admit_client_values_run_materials_input(
  input : ClientRunMaterialsInput,
  expected_run_definition_cid : String,
  manifests : ClientCompilationManifests,
  limits : ClientValuesRunMaterialsLimits,
) -> Result[ClientValuesRunMaterials, ClientValuesRunMaterialsIssue] {
  let {
    prepared,
    prepared_wire,
    authorization_wire,
    scope_id,
    run_id,
    created_at,
    valid_until,
  } = input
  let compilation = match
    issue_prepared_client_values_compilation(
      prepared,
      manifests,
      limits.sequence,
      limits.max_sequence_steps,
      limits.max_sequence_work,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(MaterialsCompilation(issue))
  }
  let evidence = fn(name : String, wire : String) {
    @publication.admit_run_evidence_value(
      name,
      wire,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    ).map_err(_ => MaterialsEvidence(name))
  }
  let prepared_invocation = match
    evidence("prepared_invocation", prepared_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let authorization = match evidence("run_authorization", authorization_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let admission = match
    admit_prepared_client_run_publication(
      prepared,
      client_values_compilation_template(compilation),
      prepared_invocation,
      authorization,
      client_values_compilation_compiled_plan(compilation),
    ) {
    Ok(value) => value
    Err(issue) => return Err(MaterialsAdmission(issue))
  }
  let run_definition = match
    @publication.issue_run_definition(
      admission,
      scope_id,
      run_id,
      @publication.empty_initial_input_artifact_set_cid(),
      created_at,
      valid_until,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(MaterialsDefinition(issue))
  }
  if @publication.publication_contract_identity(run_definition) !=
    expected_run_definition_cid {
    return Err(MaterialsRunMismatch)
  }
  match
    bind_source_free_client_values_run(
      prepared, compilation, admission, run_definition,
    ) {
    Ok(_) => Ok({ prepared, compilation, admission, run_definition, })
    Err(issue) => Err(MaterialsBinding(issue))
  }
}
