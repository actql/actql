///|
/// One prepared original restored under the existing held submission's
/// independently retained compiled Plan identity. This is not an allowed Run.
struct ClientEffectPreparedOriginal {
  prepared : PreparedClientEffectComputation
  compilation : ClientEffectCompilation
}

///|
pub fn client_effect_prepared_original_prepared(
  original : ClientEffectPreparedOriginal,
) -> PreparedClientEffectComputation {
  original.prepared
}

///|
pub fn client_effect_prepared_original_compilation(
  original : ClientEffectPreparedOriginal,
) -> ClientEffectCompilation {
  original.compilation
}

///|
/// Project only an existing compilation's concrete original inputs for the
/// existing held-submission capture. The Host must bind these bytes and this
/// compilation's CID in its original captured_input before continuation.
pub fn issue_client_effect_prepared_original(
  compilation : ClientEffectCompilation,
) -> Result[String, ClientEffectRunMaterialsIssue] {
  let prepared = compilation.owner
  guard prepared_client_effect_target_selections(prepared) is Some(selections) else {
    return Err(TargetSelection(OriginalOwnerRequired))
  }
  let (program, parameters, environment) = match
    client_effect_original_input_wires(prepared) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let infer_input = match client_effect_original_infer_input(compilation) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let infer_native_read_profile = match
    client_effect_original_infer_native_read_profile(compilation) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let infer_inputs_wire = match
    client_effect_original_infer_inputs(compilation) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let source_free_policy_input = match
    client_effect_original_source_free_policy_input(compilation) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  try {
    let writer = @encode.writer(@remote.REMOTE_RUN_MATERIALS_MAX_BYTES, 32, 2)
    @encode.begin_object(writer)
    @encode.key(writer, "check_environment")
    @encode.string_value(writer, environment)
    @encode.key(writer, "check_environment_cid")
    @encode.string_value(writer, prepared.check_environment_cid)
    @encode.key(writer, "effect_target_selections_json")
    @encode.string_value(writer, selections)
    if infer_input is Some((cid, wire)) {
      @encode.key(writer, "infer_execution_contract_cid")
      @encode.string_value(writer, cid)
      @encode.key(writer, "infer_execution_contract_json")
      @encode.string_value(writer, wire)
    }
    if infer_inputs_wire is Some(wire) {
      @encode.key(writer, "infer_execution_contracts_json")
      @encode.string_value(writer, wire)
    }
    if infer_native_read_profile is Some(wire) {
      @encode.key(writer, "infer_native_read_profile_json")
      @encode.string_value(writer, wire)
    }
    if compilation.normalization_profile is Some(inventory) {
      if !client_effect_normalization_inventory_matches(inventory, prepared) {
        return Err(Normalization(ForeignPreparation))
      }
      let (profile, cid) = client_effect_normalization_inventory_profile(
        inventory,
      )
      @encode.key(writer, "normalization_profile_cid")
      @encode.string_value(writer, cid)
      @encode.key(writer, "normalization_profile_key")
      @encode.string_value(writer, profile)
    }
    @encode.key(writer, "parameters")
    match parameters {
      None => @encode.null_value(writer)
      Some(wire) => @encode.string_value(writer, wire)
    }
    @encode.key(writer, "program")
    @encode.string_value(writer, program)
    if source_free_policy_input is Some((cid, wire)) {
      @encode.key(writer, "source_free_result_policy_cid")
      @encode.string_value(writer, cid)
      @encode.key(writer, "source_free_result_policy_json")
      @encode.string_value(writer, wire)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Input(MaterialsMalformed))
  }
}

///|
/// Restore only concrete original inputs under an identity selected from the
/// existing authenticated held capture, not a CID taken from these candidate
/// bytes. No fresh alias publication, journal, invocation, authorization or Run
/// is issued here. Installation freshness remains the Host's separate fence.
pub fn admit_client_effect_prepared_original(
  original : String,
  expected_compiled_plan_cid : String,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  manifests : ClientCompilationManifests,
  limits : ClientValuesRunMaterialsLimits,
  effect_limits : ClientEffectComputationLimits,
  request_value_policies? : ((@checked.EffectComputationCandidate) -> Result[
    Array[@checked.HostRequestValuePolicyEvidence],
    ClientEffectComputationIssue,
  ])? = None,
) -> Result[ClientEffectPreparedOriginal, ClientEffectRunMaterialsIssue] {
  if !valid_client_request_cid(expected_compiled_plan_cid) {
    return Err(TargetSelection(InvalidMaterials))
  }
  let parsed = match
    @source.parse_json_bytes(
      @utf8.encode(original),
      {
        max_input_bytes: @remote.REMOTE_RUN_MATERIALS_MAX_BYTES,
        max_nodes: 32,
        max_depth: 2,
      },
      source_path="Original Prepared Effect",
    ) {
    Ok(value) => value
    Err(_) => return Err(Input(MaterialsMalformed))
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: 32,
      max_depth: 2,
      max_string_bytes: @remote.REMOTE_RUN_MATERIALS_MAX_BYTES,
      max_total_string_bytes: @remote.REMOTE_RUN_MATERIALS_MAX_BYTES,
    }) {
    Ok(value) => value
    Err(_) => return Err(Input(MaterialsMalformed))
  }
  let object = match
    @decode.closed_object(root, [
      "check_environment", "check_environment_cid", "effect_target_selections_json",
      "infer_execution_contract_cid", "infer_execution_contract_json", "infer_execution_contracts_json",
      "infer_native_read_profile_json", "normalization_profile_cid", "normalization_profile_key",
      "parameters", "program", "source_free_result_policy_cid", "source_free_result_policy_json",
    ]) {
    Ok(value) => value
    Err(_) => return Err(Input(MaterialsMalformed))
  }
  let text = fn(name : String) -> String? {
    match @decode.lookup(object, name) {
      None => None
      Some(value) => @decode.text(value).to_option()
    }
  }
  guard text("program") is Some(program) &&
    text("check_environment") is Some(environment_wire) &&
    text("check_environment_cid") is Some(environment_cid) &&
    text("effect_target_selections_json") is Some(selections_wire) &&
    @decode.lookup(object, "parameters") is Some(parameters) else {
    return Err(Input(MaterialsMalformed))
  }
  let parameters_wire = if @decode.is_null(parameters) {
    None
  } else {
    match @decode.text(parameters) {
      Ok(value) => Some(value)
      Err(_) => return Err(Input(MaterialsMalformed))
    }
  }
  let supplied = match decode_client_run_materials_parameters(parameters_wire) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  guard admit_client_check_environment(
      environment_wire, environment_cid, expressions, operations,
    )
    is Some(environment) else {
    return Err(Input(MaterialsEnvironment))
  }
  let checked = match
    prepare_client_effect_computation(
      program,
      Json,
      environment,
      supplied,
      [],
      effect_limits,
      request_value_policies~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Program(issue))
  }
  let target_selections = match
    admit_client_effect_target_selections(checked.candidate, selections_wire) {
    Ok(value) => value
    Err(issue) => return Err(TargetSelection(issue))
  }
  let prepared = { ..checked, target_selections: Some(target_selections), }
  let infer_input = match
    read_client_effect_original_infer_input(
      @decode.lookup(object, "infer_execution_contract_cid"),
      @decode.lookup(object, "infer_execution_contract_json"),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  let infer_native_read_profile = match
    read_client_effect_original_native_read_profile(
      @decode.lookup(object, "infer_native_read_profile_json"),
      infer_input,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  let infer = match
    restore_client_effect_original_infer(
      prepared,
      infer_input,
      limits,
      native_read_profile=infer_native_read_profile,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let infers = match @decode.lookup(object, "infer_execution_contracts_json") {
    None => []
    Some(value) => {
      guard infer_input is None && @decode.text(value) is Ok(wire) else {
        return Err(Input(MaterialsMalformed))
      }
      match
        read_plural_client_infer_run_graphs(
          client_effect_program_view(prepared),
          wire,
          limits,
        ) {
        Ok(value) => value
        Err(_) =>
          return Err(Input(MaterialsEvidence("infer_execution_contracts")))
      }
    }
  }
  let source_free_policy_input = match
    read_client_effect_original_source_free_policy_input(
      @decode.lookup(object, "source_free_result_policy_cid"),
      @decode.lookup(object, "source_free_result_policy_json"),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  let source_free_policy = match
    restore_client_effect_original_source_free_policy(
      prepared, source_free_policy_input,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let normalization_profile = match
    (
      @decode.lookup(object, "normalization_profile_key"),
      @decode.lookup(object, "normalization_profile_cid"),
    ) {
    (None, None) => None
    (Some(key), Some(cid)) => {
      let inventory = match
        checked_client_effect_normalization_inventory(prepared) {
        Ok(value) => value
        Err(issue) => return Err(Normalization(issue))
      }
      let (expected_key, expected_cid) = client_effect_normalization_inventory_profile(
        inventory,
      )
      if @decode.text(key) != Ok(expected_key) ||
        @decode.text(cid) != Ok(expected_cid) {
        return Err(Normalization(ForeignCatalog))
      }
      Some(inventory)
    }
    _ => return Err(Input(MaterialsMalformed))
  }
  let compilation = match
    issue_client_effect_compilation_internal(
      prepared,
      manifests,
      limits.sequence,
      limits.max_sequence_steps,
      limits.max_sequence_work,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
      normalization_profile,
      infer~,
      infers~,
      source_free_policy~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Compilation(issue))
  }
  if @publication.publication_contract_identity(
      client_effect_compilation_compiled_plan(compilation),
    ) !=
    expected_compiled_plan_cid {
    return Err(TargetSelection(ForeignSelection))
  }
  let canonical = match issue_client_effect_prepared_original(compilation) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if canonical != original {
    return Err(TargetSelection(InvalidMaterials))
  }
  Ok({ prepared, compilation, })
}
