///|
pub(all) enum ClientEffectResultImportIssue {
  ForeignInput
  ForeignArtifact
  ForeignManifest
  ForeignInterface
  Encoding
} derive(Eq, Debug)

///|
/// Semantic observation issued from an actual retained input. Current Run
/// authority is checked separately and is not part of this semantic body.
struct ClientEffectResultImportObservation {
  owner : PreparedClientEffectComputation
  inputs : @strategy.CapturedEffectInputs
  captured : @strategy.CapturedEffectResultImport
  manifest : ClientEffectLocalManifest
  artifact : ClientEffectLocalResultArtifact
  cid : String
  wire : String
}

///|
fn emit_client_effect_result_import(
  writer : @encode.Writer,
  consumer : String,
  input_name : String,
  interface : String,
  manifest : String,
  artifact : String,
  self_cid : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "consumer_unit_definition_cid")
  @encode.string_value(writer, consumer)
  @encode.key(writer, "import_interface_cid")
  @encode.string_value(writer, interface)
  @encode.key(writer, "input_name")
  @encode.string_value(writer, input_name)
  @encode.key(writer, "producer_local_manifest_cid")
  @encode.string_value(writer, manifest)
  @encode.key(writer, "result_artifact_cid")
  @encode.string_value(writer, artifact)
  if self_cid is Some(cid) {
    @encode.key(writer, "self_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-result-import-observation/0.1")
  @encode.end_object(writer)
}

///|
pub fn issue_client_effect_result_import_observation(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  captured : @strategy.CapturedEffectResultImport,
  manifest : ClientEffectLocalManifest,
  artifact : ClientEffectLocalResultArtifact,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectResultImportObservation, ClientEffectResultImportIssue] {
  let consumer = @strategy.captured_effect_result_import_consumer(captured)
  let producer = @strategy.captured_effect_result_import_producer(captured)
  if !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) ||
    !@strategy.captured_effect_result_import_matches(
      captured, inputs, consumer, producer,
    ) {
    return Err(ForeignInput)
  }
  if !physical_equal(artifact.inputs, inputs) ||
    !@strategy.captured_any_result_borrows_share_view(
      artifact.borrow,
      @strategy.captured_effect_local_result_borrow(producer),
    ) {
    return Err(ForeignArtifact)
  }
  if !client_effect_local_manifest_matches(
      manifest,
      owner,
      artifact.invocation,
      manifest.artifacts,
    ) {
    return Err(ForeignManifest)
  }
  let mut occurrences = 0
  for entry in manifest.artifacts {
    if physical_equal(entry, artifact) {
      occurrences += 1
    }
  }
  if occurrences != 1 {
    return Err(ForeignManifest)
  }
  let interface = @strategy.captured_effect_result_import_interface(captured)
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  guard @checked.unit_definition_cid(program, consumer) is Some(definition) else {
    return Err(ForeignInterface)
  }
  if interface.producer_unit_definition_cid !=
    artifact.definition.unit_definition_cid ||
    interface.result_name != artifact.definition.result_name ||
    !client_effect_local_result_definition_matches(
      artifact.definition,
      owner,
      @strategy.captured_effect_local_result_stage(producer),
      interface.result_name,
    ) {
    return Err(ForeignInterface)
  }
  let artifact_cid = client_effect_local_result_artifact_cid(artifact)
  let hash = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_effect_result_import(
    hash,
    definition,
    interface.input_name,
    interface.cid,
    manifest.cid,
    artifact_cid,
    None,
  ) catch {
    _ => return Err(Encoding)
  }
  let cid = "sha256:" +
    (@encode.finish_hash(hash) catch { _ => return Err(Encoding) })
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_effect_result_import(
    writer,
    definition,
    interface.input_name,
    interface.cid,
    manifest.cid,
    artifact_cid,
    Some(cid),
  ) catch {
    _ => return Err(Encoding)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok({ owner, inputs, captured, manifest, artifact, cid, wire, })
}

///|
pub fn client_effect_result_import_observation_cid(
  value : ClientEffectResultImportObservation,
) -> String {
  value.cid
}

///|
pub fn client_effect_result_import_observation_json(
  value : ClientEffectResultImportObservation,
) -> String {
  value.wire
}

///|
/// Imported-input Units need every checked input observation, including
/// inputs not referenced by the final Result. This entry does not admit
/// additional external acquisition contracts or caller-provided CID lists.
pub fn issue_imported_client_effect_local_invocation(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  unit : Int,
  observations : Array[ClientEffectResultImportObservation],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectLocalInvocation, ClientEffectLocalInvocationIssue] {
  if !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) {
    return Err(ForeignCapturedInput)
  }
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  guard @checked.unit_definition_cid(program, unit) is Some(definition) &&
    @checked.unit_used_values_cid(program, unit) is Some(values) &&
    @checked.unit_contracts_cid(program, unit) is Some(contracts) &&
    @checked.unit_result_import_count(program, unit) is Some(count) else {
    return Err(MissingUnit)
  }
  if count == 0 ||
    count != observations.length() ||
    @checked.unit_import_cid_count(program, unit) != Some(count) {
    return Err(IncompleteResultImports)
  }
  let seen : Map[String, Bool] = Map([])
  let cids : Array[String] = []
  for observation in observations {
    let captured = observation.captured
    let producer = @strategy.captured_effect_result_import_producer(captured)
    let interface = @strategy.captured_effect_result_import_interface(captured)
    if !physical_equal(observation.owner, owner) ||
      !physical_equal(observation.inputs, inputs) ||
      !@strategy.captured_effect_result_import_matches(
        captured, inputs, unit, producer,
      ) ||
      !@strategy.captured_any_result_borrows_share_view(
        observation.artifact.borrow,
        @strategy.captured_effect_local_result_borrow(producer),
      ) ||
      !client_effect_local_manifest_matches(
        observation.manifest,
        owner,
        observation.artifact.invocation,
        observation.manifest.artifacts,
      ) ||
      seen.contains(interface.input_name) {
      return Err(ForeignResultImport)
    }
    // The captured proof already binds the checked interface and input
    // position. No ordering or name supplied by the caller can relabel it.
    seen[interface.input_name] = true
    cids.push(observation.cid)
  }
  cids.sort_by(@canonical_value.compare_utf16)
  issue_client_effect_local_invocation_body(
    owner,
    unit,
    definition,
    values,
    contracts,
    @checked.checked_local_policy_cid(program),
    cids,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}
