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
  guard artifact.source is ResultSource(borrow, result_definition) else {
    return Err(ForeignArtifact)
  }
  if !client_effect_local_artifact_matches_inputs(artifact, inputs) ||
    !@strategy.captured_any_result_borrows_share_view(
      borrow,
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
    result_definition.unit_definition_cid ||
    interface.result_name != result_definition.result_name ||
    !client_effect_local_result_definition_matches(
      result_definition,
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
    guard observation.artifact.source is ResultSource(borrow, _) else {
      return Err(ForeignResultImport)
    }
    let captured = observation.captured
    let producer = @strategy.captured_effect_result_import_producer(captured)
    let interface = @strategy.captured_effect_result_import_interface(captured)
    if !physical_equal(observation.owner, owner) ||
      !physical_equal(observation.inputs, inputs) ||
      !@strategy.captured_effect_result_import_matches(
        captured, inputs, unit, producer,
      ) ||
      !@strategy.captured_any_result_borrows_share_view(
        borrow,
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

///|
// The original completed pre-Model input already retains the producer
// Artifact/Manifest and kernel proof. This is a semantic body association,
// never a final Effect inventory, permission or independent cleanup owner.
priv struct ClientScopeResultImportObservation {
  input : ClientInferResultArtifactInput
  cid : String
  wire : String
}

///|
fn issue_scope_model_result_import_observations(
  owner : PreparedClientEffectComputation,
  scope : ClientInferCallScope,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  before_body? : ((String, @encode.EncodingConstructionGeometry) -> Bool)? = None,
) -> Result[
  Array[ClientScopeResultImportObservation],
  ClientEffectLocalInvocationIssue,
] {
  let occurrence = scope.plan.occurrence
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  guard client_infer_occurrence_matches_effect(occurrence, owner) &&
    client_infer_call_scope_matches(scope, occurrence.owner, scope.input) &&
    @checked.unit_result_import_count(program, occurrence.stage) is Some(count) &&
    count > 0 &&
    @checked.unit_import_cid_count(program, occurrence.stage) == Some(count) &&
    scope.result_inputs.length() == count &&
    @checked.unit_definition_cid(program, occurrence.stage) is Some(consumer) else {
    return Err(IncompleteResultImports)
  }
  for index in 0..<count {
    guard @checked.unit_result_import_at(program, occurrence.stage, index)
      is Some(interface) else {
      return Err(IncompleteResultImports)
    }
    let mut matches = 0
    for original in scope.original_result_inputs {
      if physical_equal(original.interface, interface) {
        matches += 1
      }
    }
    if matches != 1 {
      return Err(IncompleteResultImports)
    }
  }
  let observations : Array[ClientScopeResultImportObservation] = []
  for original in scope.result_inputs {
    // The original opaque Scope just checked its complete kernel-bound input
    // inventory. These immutable body fields need no second current callback.
    if before_body is Some(back) {
      let measure = @encode.construction_measuring_writer(
        max_bytes, max_nodes, max_depth,
      ) catch {
        _ => return Err(Encoding)
      }
      let shape = try {
        emit_client_effect_result_import(
          measure,
          consumer,
          original.interface.input_name,
          original.interface.cid,
          original.manifest.cid,
          client_effect_local_result_artifact_cid(original.artifact),
          Some(consumer),
        )
        @encode.finish_construction_measurement(measure)
      } catch {
        _ => {
          @encode.cancel_writer(measure)
          return Err(Encoding)
        }
      }
      if !back("result_import_observation", shape) {
        return Err(Encoding)
      }
      if !client_infer_result_input_inventory_current(scope) {
        return Err(ForeignResultImport)
      }
    }
    let hash = @encode.hashing_writer(max_bytes, max_nodes, max_depth) catch {
      _ => return Err(Encoding)
    }
    emit_client_effect_result_import(
      hash,
      consumer,
      original.interface.input_name,
      original.interface.cid,
      original.manifest.cid,
      client_effect_local_result_artifact_cid(original.artifact),
      None,
    ) catch {
      _ => return Err(Encoding)
    }
    let cid = "sha256:" +
      (@encode.finish_hash(hash) catch { _ => return Err(Encoding) })
    let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
      _ => return Err(Encoding)
    }
    emit_client_effect_result_import(
      writer,
      consumer,
      original.interface.input_name,
      original.interface.cid,
      original.manifest.cid,
      client_effect_local_result_artifact_cid(original.artifact),
      Some(cid),
    ) catch {
      _ => return Err(Encoding)
    }
    let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
    observations.push({ input: original, cid, wire, })
  }
  Ok(observations)
}
