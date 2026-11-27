///|
pub(all) enum ClientEffectLocalIdentityIssue {
  ForeignInput
  MissingMember
  ForeignArtifact
  MissingMapping
  ForeignPreview
  MissingIdentity
  WorkLimit
  Capacity
  Encoding
} derive(Eq, Debug)

///|
/// One checked local Effect occurrence. This is semantic identity, not a
/// current write grant or evidence that its Result remains available.
struct ClientEffectLocalIdentity {
  owner : PreparedClientEffectComputation
  member_index : Int
  artifact : ClientEffectLocalResultArtifact
  cid : String
  wire : String
}

///|
fn emit_client_effect_local_identity(
  writer : @encode.Writer,
  header : @syntax.EffectHeader,
  unit_definition_cid : String,
  local_invocation_cid : String,
  result_artifact_cid : String,
  resolved_contract_cid : String,
  self_cid : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_ordered_object(writer)
  @encode.ordered_key(writer, "effect_id")
  @encode.string_value(writer, @syntax.effect_header_id(header))
  @encode.ordered_key(writer, "effect_semantics")
  @syntax.emit_effect_header_semantics(header, writer)
  @encode.ordered_key(writer, "local_invocation_cid")
  @encode.string_value(writer, local_invocation_cid)
  @encode.ordered_key(writer, "resolved_contract_cid")
  @encode.string_value(writer, resolved_contract_cid)
  @encode.ordered_key(writer, "result_artifact_cid")
  @encode.string_value(writer, result_artifact_cid)
  if self_cid is Some(cid) {
    @encode.ordered_key(writer, "self_cid")
    @encode.string_value(writer, cid)
  }
  @encode.ordered_key(writer, "unit_definition_cid")
  @encode.string_value(writer, unit_definition_cid)
  @encode.ordered_key(writer, "version")
  @encode.string_value(writer, "actql-local-effect-identity/0.1")
  @encode.end_object(writer)
}

///|
/// Bind the authored member and its resolved Mapping or Command to the same checked
/// source pin, local Invocation, and completed local Result Artifact.
pub fn issue_source_free_client_effect_local_identity(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  artifact : ClientEffectLocalResultArtifact,
  max_work : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  fund? : ((
    @execution.PreparationRepresentationUnits,
    @execution.PreparationRepresentationUnits,
  ) -> Bool)? = None,
) -> Result[ClientEffectLocalIdentity, ClientEffectLocalIdentityIssue] {
  if !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) ||
    !client_effect_local_artifact_matches_inputs(artifact, inputs) ||
    !client_effect_local_artifact_matches_member(artifact, inputs, member_index) {
    return Err(ForeignInput)
  }
  let (unit, name, definition_cid, private_input) = match artifact.source {
    ResultSource(_, definition) => {
      guard @strategy.captured_effect_input_at(inputs, member_index)
        is Some(input) else {
        return Err(MissingMember)
      }
      let unit = @strategy.captured_effect_input_stage(input)
      if !client_effect_local_result_definition_matches(
          definition,
          owner,
          unit,
          definition.result_name,
        ) {
        return Err(ForeignArtifact)
      }
      (unit, definition.result_name, definition.unit_definition_cid, false)
    }
    TableSource(_, definition) => {
      guard @strategy.captured_effect_table_input_at(inputs, member_index)
        is Some(input) else {
        return Err(MissingMember)
      }
      if !client_effect_local_table_definition_matches(definition, owner, input) {
        return Err(ForeignArtifact)
      }
      (definition.unit, definition.name, definition.unit_definition_cid, true)
    }
  }
  let headers = @checked.effect_program_static_headers(owner.candidate)
  guard @syntax.effect_header_at(headers, member_index) is Some(header) &&
    @syntax.effect_header_stage(header) == unit else {
    return Err(MissingMember)
  }
  if private_input {
    if @syntax.effect_header_kind(header) != "store" ||
      @syntax.effect_header_source_table_input(header) != Some(name) ||
      @syntax.effect_header_source_result(header) is Some(_) {
      return Err(MissingMember)
    }
  } else if @syntax.effect_header_source_result(header) != Some(name) ||
    @syntax.effect_header_source_table_input(header) is Some(_) {
    return Err(MissingMember)
  }
  if !client_effect_local_invocation_matches(artifact.invocation, owner, unit) {
    return Err(ForeignArtifact)
  }
  let descriptor = match
    client_effect_member_descriptor(
      owner,
      unit,
      @syntax.effect_header_id(header),
      max_work,
    ) {
    Ok(value) => value
    Err(WorkLimit) => return Err(WorkLimit)
    Err(_) => return Err(MissingMapping)
  }
  let (
    _,
    _,
    _,
    _,
    _,
    resolved_contract_cid,
    source_result,
    _,
    source_table_input,
  ) = descriptor
  if source_result != (if private_input { None } else { Some(name) }) ||
    source_table_input != (if private_input { Some(name) } else { None }) {
    return Err(ForeignArtifact)
  }
  let invocation_cid = artifact.invocation.cid
  let artifact_cid = @publication.publication_contract_identity(
    artifact.artifact,
  )
  let measured = if fund is Some(fund) {
    let shape = @decode.observe_subtree_construction_geometry(
      @syntax.effect_header_body(header),
    )
    guard client_effect_local_identity_emission_inventory(
        shape, 0, max_depth, false,
      )
      is Some(measure) &&
      fund(measure, empty_effect_local_identity_inventory()) else {
      return Err(Capacity)
    }
    let writer = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth) catch {
      _ => return Err(Encoding)
    }
    let usage = try {
      // The fixed placeholder has the same UTF-8 extent as the issued CID.
      emit_client_effect_local_identity(
        writer,
        header,
        definition_cid,
        invocation_cid,
        artifact_cid,
        resolved_contract_cid,
        Some(definition_cid),
      )
      @encode.finish_measurement_usage(writer)
    } catch {
      _ => return Err(Encoding)
    }
    let (bytes, _, depth) = usage
    guard client_effect_local_identity_emission_inventory(
        shape, bytes, depth, true,
      )
      is Some(emission) &&
      fund(emission, {
        record_headers: 4L,
        reference_slots: 6L,
        scalar_words: 2L,
        owned_utf16_units: bytes.to_int64() + 71L,
        owned_wire_bytes: 0L,
      }) else {
      return Err(Capacity)
    }
    Some(usage)
  } else {
    None
  }
  let cid = try {
    let hash = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_effect_local_identity(
      hash,
      header,
      definition_cid,
      invocation_cid,
      artifact_cid,
      resolved_contract_cid,
      None,
    )
    "sha256:" + @encode.finish_hash(hash)
  } catch {
    _ => return Err(Encoding)
  }
  let (bytes, nodes, depth) = measured.unwrap_or(
    (max_wire_bytes, max_nodes, max_depth),
  )
  let writer = @encode.writer(bytes, nodes, depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_effect_local_identity(
    writer,
    header,
    definition_cid,
    invocation_cid,
    artifact_cid,
    resolved_contract_cid,
    Some(cid),
  ) catch {
    _ => return Err(Encoding)
  }
  let (wire, actual_bytes, actual_nodes, actual_depth) = @encode.finish_text_usage(
    writer,
  ) catch {
    _ => return Err(Encoding)
  }
  if measured is Some(usage) &&
    usage != (actual_bytes, actual_nodes, actual_depth) {
    return Err(Encoding)
  }
  Ok({ owner, member_index, artifact, cid, wire, })
}

///|
fn empty_effect_local_identity_inventory() -> @execution.PreparationRepresentationUnits {
  {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
// The semantics emitter visits the admitted syntax, sorts each original
// object’s field references and borrows its strings. Count every possible
// outstanding cursor and sort slot, including refused prefixes. Sorted keys
// use the writer's ordered cursor, whose frame holds only its previous key.
fn client_effect_local_identity_emission_inventory(
  shape : @decode.SubtreeConstructionGeometry,
  output_bytes : Int,
  depth : Int,
  emitting : Bool,
) -> @execution.PreparationRepresentationUnits? {
  guard depth >= 0 else { return None }
  let depth = Int::min(depth, Int::min(shape.nodes, 2147483643) + 4)
  let n = shape.nodes.to_int64()
  guard @shape.collection_construction_extent({
      records: 8L * n + 8L,
      record_references: 5L * n + 12L,
      record_words: 7L * n + 12L,
      reference_arrays: 3L * shape.objects.to_int64(),
      reference_items: 7L * shape.fields.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: 0L,
    })
    is Some(traversal) &&
    @encode.measuring_writer_construction_extent(0, depth) is Some(measure) else {
    return None
  }
  let operation = @encode.measurement_operation_construction_extent()
  let transient : @execution.PreparationRepresentationUnits = {
    record_headers: traversal.record_headers +
    measure.record_headers +
    operation.collections.record_headers +
    18L,
    reference_slots: traversal.reference_slots +
    measure.reference_slots +
    operation.collections.reference_slots +
    24L,
    scalar_words: traversal.scalar_words +
    measure.scalar_words +
    operation.collections.scalar_words +
    24L,
    owned_utf16_units: operation.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  if !emitting {
    return Some(transient)
  }
  guard @encode.hash_writer_live_key_inventory(0, depth) is Some(hash) &&
    @encode.text_writer_live_key_inventory(output_bytes, 0, depth) is Some(text) else {
    return None
  }
  Some({
    record_headers: Int64::max(
      transient.record_headers,
      traversal.record_headers +
      Int64::max(hash.record_headers, text.record_headers) +
      18L,
    ),
    reference_slots: Int64::max(
      transient.reference_slots,
      traversal.reference_slots +
      hash.reference_slots +
      text.reference_slots +
      24L,
    ),
    scalar_words: Int64::max(
      transient.scalar_words,
      traversal.scalar_words +
      Int64::max(hash.scalar_words, text.scalar_words) +
      24L,
    ),
    owned_utf16_units: Int64::max(
      hash.owned_utf16_units,
      text.owned_utf16_units,
    ) +
    71L,
    owned_wire_bytes: hash.owned_wire_bytes,
  })
}

///|
pub fn client_effect_local_identity_cid(
  identity : ClientEffectLocalIdentity,
) -> String {
  identity.cid
}

///|
pub fn client_effect_local_identity_json(
  identity : ClientEffectLocalIdentity,
) -> String {
  identity.wire
}

///|
pub fn client_effect_local_identity_matches(
  identity : ClientEffectLocalIdentity,
  owner : PreparedClientEffectComputation,
  member_index : Int,
  artifact : ClientEffectLocalResultArtifact,
) -> Bool {
  physical_equal(identity.owner, owner) &&
  identity.member_index == member_index &&
  physical_equal(identity.artifact, artifact)
}

///|
/// Bind every Relation-consuming Preview member to the identity issued by the
/// exact checked computation and pinned local Artifact. Preview CID
/// admission alone cannot establish that the claimed identity was issued.
pub fn check_source_free_client_effect_preview_identities(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  preview_wire : String,
  run_identity_cid : String,
  authoring_context_cid : String,
  identities : Array[ClientEffectLocalIdentity],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientEffectLocalIdentityIssue] {
  admit_source_free_client_effect_preview_identities(
    owner, inputs, preview_wire, run_identity_cid, authoring_context_cid, identities,
    max_wire_bytes, max_nodes, max_depth,
  ).map(_ => ())
}

///|
// Keep the same wire-admitted identity after checking its issued local
// members. Binding the original Run can consume it without another decode.
fn admit_source_free_client_effect_preview_identities(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  preview_wire : String,
  run_identity_cid : String,
  authoring_context_cid : String,
  identities : Array[ClientEffectLocalIdentity],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.EffectPreviewIdentity, ClientEffectLocalIdentityIssue] {
  if !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) {
    return Err(ForeignInput)
  }
  let preview = match
    @publication.admit_effect_preview_identity(
      preview_wire, run_identity_cid, authoring_context_cid, max_wire_bytes, max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignPreview)
  }
  check_admitted_source_free_client_effect_preview_identities(
    owner, inputs, preview, identities,
  ).map(_ => preview)
}

///|
fn check_admitted_source_free_client_effect_preview_identities(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  preview : @publication.EffectPreviewIdentity,
  identities : Array[ClientEffectLocalIdentity],
) -> Result[Unit, ClientEffectLocalIdentityIssue] {
  if @publication.effect_preview_program_definition_cid(preview) !=
    prepared_client_effect_computation_definition_cid(owner) ||
    @publication.effect_preview_program_semantics_cid(preview) !=
    prepared_client_effect_computation_semantics_cid(owner) ||
    @publication.effect_preview_check_environment_cid(preview) !=
    prepared_client_effect_computation_environment_cid(owner) {
    return Err(ForeignPreview)
  }
  let headers = @checked.effect_program_static_headers(owner.candidate)
  let by_effect_id : Map[String, ClientEffectLocalIdentity] = Map([])
  for identity in identities {
    guard @syntax.effect_header_at(headers, identity.member_index)
      is Some(header) else {
      return Err(ForeignPreview)
    }
    let effect_id = @syntax.effect_header_id(header)
    if by_effect_id.contains(effect_id) ||
      !physical_equal(identity.owner, owner) ||
      !client_effect_local_artifact_matches_inputs(identity.artifact, inputs) ||
      !client_effect_local_artifact_matches_member(
        identity.artifact,
        inputs,
        identity.member_index,
      ) {
      return Err(ForeignPreview)
    }
    by_effect_id[effect_id] = identity
  }
  let mut source_count = 0
  for preview_index in 0..<@publication.effect_preview_member_count(preview) {
    match
      @publication.effect_preview_member_relation_source(preview, preview_index) {
      None => continue
      Some(source) => {
        source_count += 1
        let effect_id = @publication.effect_preview_member_effect_id(
          preview, preview_index,
        ).unwrap()
        let expected_cid = @publication.effect_preview_member_effect_identity_cid(
          preview, preview_index,
        ).unwrap()
        guard by_effect_id.get(effect_id) is Some(identity) else {
          return Err(MissingIdentity)
        }
        let header = @syntax.effect_header_at(headers, identity.member_index).unwrap()
        let matched = match (source, identity.artifact.source) {
          (@publication.Result(name), ResultSource(_, definition)) =>
            @syntax.effect_header_source_result(header) == Some(name) &&
            @syntax.effect_header_source_table_input(header) is None &&
            definition.result_name == name
          (@publication.TableInput(name), TableSource(_, definition)) =>
            @syntax.effect_header_source_table_input(header) == Some(name) &&
            @syntax.effect_header_source_result(header) is None &&
            definition.name == name
          _ => false
        }
        if !matched ||
          identity.cid != expected_cid ||
          @publication.effect_preview_member_result_artifact_cid(
            preview, preview_index,
          ) !=
          Some(
            @publication.publication_contract_identity(
              identity.artifact.artifact,
            ),
          ) {
          return Err(ForeignPreview)
        }
      }
    }
  }
  if source_count != identities.length() {
    return Err(MissingIdentity)
  }
  Ok(())
}
