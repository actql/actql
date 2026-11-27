///|
pub(all) enum EffectSourceArtifactIssue {
  EffectSourceWrongContract
  EffectSourceInvalidBinding
  EffectSourceInvalidMeasurement
  EffectSourceCapacity
  EffectSourceEncoding
  EffectSourceContract(PublicationContractIssue)
} derive(Eq, Debug)

///|
/// Issue the private Artifact for a completed checked Stage Result export.
/// The Host bridge supplies its opaque export receipt's logical identity,
/// schema, and row count; this contract does not itself establish Store custody.
pub fn issue_effect_source_artifact(
  invocation : PublicationContract,
  retention : PublicationContract,
  source_result : String,
  source_binding_cid : String,
  store_authority_cid : String,
  logical_result_cid : String,
  result_schema_cid : String,
  row_count : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  before_body? : ((@encode.EncodingConstructionGeometry) -> Bool)? = None,
) -> Result[PublicationContract, EffectSourceArtifactIssue] {
  issue_effect_relation_source_artifact(
    invocation,
    retention,
    Result(source_result),
    source_binding_cid,
    store_authority_cid,
    logical_result_cid,
    result_schema_cid,
    row_count,
    max_wire_bytes,
    max_nodes,
    max_depth,
    before_body~,
  )
}

///|
/// Issue a physical source for a checked private Table input. The separate
/// source namespace preserves Conditional presence without publishing a Result.
/// Export facts do not establish live Store custody or permission to commit.
pub fn issue_effect_table_input_artifact(
  invocation : PublicationContract,
  retention : PublicationContract,
  table_input : String,
  source_binding_cid : String,
  store_authority_cid : String,
  logical_result_cid : String,
  result_schema_cid : String,
  row_count : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectSourceArtifactIssue] {
  issue_effect_relation_source_artifact(
    invocation,
    retention,
    TableInput(table_input),
    source_binding_cid,
    store_authority_cid,
    logical_result_cid,
    result_schema_cid,
    row_count,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn issue_effect_relation_source_artifact(
  invocation : PublicationContract,
  retention : PublicationContract,
  source : EffectPreviewRelationSource,
  source_binding_cid : String,
  store_authority_cid : String,
  logical_result_cid : String,
  result_schema_cid : String,
  row_count : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  before_body? : ((@encode.EncodingConstructionGeometry) -> Bool)? = None,
) -> Result[PublicationContract, EffectSourceArtifactIssue] {
  if invocation.name != "run_invocation" ||
    retention.name != "result_retention_policy" {
    return Err(EffectSourceWrongContract)
  }
  guard contract_string(retention, "effective_data_policy_cid")
    is Some(data_policy_cid) else {
    return Err(EffectSourceWrongContract)
  }
  let (source_field, source_name) = match source {
    Result(name) => ("source_result", name)
    TableInput(name) => ("source_table_input", name)
  }
  guard @canonical.normalize_nfc_lf(source_name) is Ok(normalized) else {
    return Err(EffectSourceInvalidBinding)
  }
  if source_name.is_empty() ||
    normalized != source_name ||
    !valid_contract_cid(source_binding_cid) ||
    !valid_contract_cid(store_authority_cid) ||
    !valid_contract_cid(logical_result_cid) ||
    !valid_contract_cid(result_schema_cid) {
    return Err(EffectSourceInvalidBinding)
  }
  if row_count < 0 {
    return Err(EffectSourceInvalidMeasurement)
  }
  let fields : Array[(String, EffectSourceArtifactField)] = [
    ("actual_completeness", Text("complete")),
    ("actual_row_count", Count(row_count)),
    ("effective_data_policy_cid", Text(data_policy_cid)),
    ("effective_retention_policy_cid", Text(retention.identity)),
    ("invocation_cid", Text(invocation.identity)),
    ("logical_result_cid", Text(logical_result_cid)),
    ("provenance_evidence_cids", EmptyArray),
    ("result_schema_cid", Text(result_schema_cid)),
    ("source_binding_cid", Text(source_binding_cid)),
    (source_field, Text(source_name)),
    ("store_authority_cid", Text(store_authority_cid)),
    ("version", Text("actql-effect-source-artifact/0.1")),
  ]
  let measured = if before_body is Some(fund) {
    let writer = @encode.construction_measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    ) catch {
      _ => return Err(EffectSourceEncoding)
    }
    let geometry = try {
      measure_effect_source_artifact_fields(fields, writer)
      @encode.finish_construction_measurement(writer)
    } catch {
      _ => return Err(EffectSourceEncoding)
    }
    // The original sealer adds this one fixed contract CID after hashing.
    guard publication_contract_identity_field_for_name("effect_source_artifact")
      is Some(key) &&
      geometry.bytes.to_int64() + key.length().to_int64() + 77L <=
      max_wire_bytes.to_int64() &&
      geometry.nodes < max_nodes else {
      return Err(EffectSourceEncoding)
    }
    let complete = {
      ..geometry,
      bytes: geometry.bytes + key.length() + 77,
      nodes: geometry.nodes + 1,
      fields: geometry.fields + 1,
      largest_object: geometry.largest_object + 1,
      strings: geometry.strings + 2,
      text_units: geometry.text_units + key.length() + 71,
    }
    if !fund(complete) {
      return Err(EffectSourceCapacity)
    }
    Some((complete.bytes, complete.nodes, complete.depth))
  } else {
    None
  }
  guard contract_spec("effect_source_artifact") is Some(spec) && max_nodes > 1 else {
    return Err(EffectSourceEncoding)
  }
  let body = build_effect_source_artifact_material(
    fields,
    max_wire_bytes,
    max_nodes - 1,
    max_depth,
  ) catch {
    _ => return Err(EffectSourceEncoding)
  }
  match
    seal_publication_material(
      spec,
      body,
      max_wire_bytes,
      max_nodes,
      max_depth,
      [],
    ) {
    Ok(artifact) if measured is None ||
      publication_contract_wire_usage(artifact) == measured => Ok(artifact)
    Ok(_) => Err(EffectSourceEncoding)
    Err(issue) => Err(EffectSourceContract(issue))
  }
}

///|
priv enum EffectSourceArtifactField {
  Text(String)
  Count(Int)
  EmptyArray
}

///|
// Borrow the same ordered fields for measurement and canonical construction.
fn measure_effect_source_artifact_fields(
  fields : Array[(String, EffectSourceArtifactField)],
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_ordered_object(writer)
  for (key, value) in fields {
    @encode.ordered_key(writer, key)
    match value {
      Text(text) => @encode.string_value(writer, text)
      Count(count) => @encode.number_value(writer, count.to_double())
      EmptyArray => {
        @encode.begin_array(writer)
        @encode.end_array(writer)
      }
    }
  }
  @encode.end_object(writer)
}

///|
fn build_effect_source_artifact_material(
  fields : Array[(String, EffectSourceArtifactField)],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @json.CanonicalValue raise {
  let material = @json.start_material(max_bytes, max_nodes, max_depth)
  defer @json.cancel_material(material)
  @json.material_begin_object(material)
  for (key, value) in fields {
    @json.material_key(material, key)
    while !@json.advance_material(material) {

    }
    match value {
      Text(text) => {
        @json.material_text(material, text)
        while !@json.advance_material(material) {

        }
      }
      Count(count) => {
        let number = @json.from_json(Json::number(count.to_double()), 1, 0, 0)
        @json.material_value(material, number)
        while !@json.advance_material(material) {

        }
      }
      EmptyArray => {
        @json.material_begin_array(material)
        @json.material_end_array(material)
      }
    }
  }
  @json.material_end_object(material)
  @json.finish_material(material).0
}

///|
/// Source Artifact issuance starts from its checked closed fields and seals
/// ordered canonical material. There is no intermediate text, source parser
/// or conversion tree. Store admission independently accounts its reader.
pub fn effect_source_artifact_construction_inventory(
  geometry : @encode.EncodingConstructionGeometry,
) -> (
  EffectPreviewIdentityConstructionInventory,
  EffectPreviewIdentityConstructionInventory,
)? {
  guard geometry.bytes > 0 &&
    geometry.nodes == 14 &&
    geometry.fields == 13 &&
    geometry.objects == 1 &&
    geometry.arrays == 1 &&
    geometry.depth == 2 &&
    publication_returned_contract_inventory(
      geometry.bytes,
      geometry.nodes,
      geometry.depth,
      geometry=Some(geometry),
    )
    is Some(retained) &&
    publication_borrowed_contract_inventory(
      geometry.bytes,
      geometry.nodes,
      geometry.depth,
    )
    is Some((validation, seal)) &&
    effectful_publication_measurement_construction_inventory(2) is Some(measure) &&
    @shape.collection_construction_extent({
      // Preimage object and self-CID insertion keep the old and new ordered
      // field backings, while all existing key/value strings stay borrowed.
      // Count one Material owner, two active frame variants, and its scalar
      // Number admission stack, pending key/value and measurement carriers.
      records: 8L + 8L * geometry.nodes.to_int64(),
      record_references: 10L + 10L * geometry.nodes.to_int64(),
      record_words: 12L + 8L * geometry.nodes.to_int64(),
      reference_arrays: 5L,
      reference_items: 2L * geometry.fields.to_int64() + 6L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(material) &&
    publication_inventory_add(validation, seal) is Some(working) &&
    publication_inventory_add(working, {
      record_headers: measure.record_headers + material.record_headers,
      reference_slots: measure.reference_slots + material.reference_slots,
      scalar_words: measure.scalar_words + material.scalar_words,
      owned_utf16_units: measure.owned_utf16_units,
      owned_wire_bytes: measure.owned_wire_bytes,
    })
    is Some(workspace) else {
    return None
  }
  // All field text points into the retained invocation, retention, captured
  // result or constant keys. Only the complete wire and its new CID escape.
  Some(
    (
      { ..retained, owned_utf16_units: geometry.bytes.to_int64() + 71L, },
      workspace,
    ),
  )
}

///|
/// Initial scratch for the closed Source Artifact and one original Result
/// name. Its fixed object/empty array and scalar emitter precede body funding.
pub fn effect_source_artifact_measurement_inventory(
  source_name_units : Int,
) -> EffectPreviewIdentityConstructionInventory? {
  guard @canonical.nfc_lf_construction_extent(source_name_units) is Some(name) &&
    effectful_publication_measurement_construction_inventory(2)
    is Some(measurement) &&
    @encode.text_writer_live_key_inventory(0, 0, 2) is Some(writer) else {
    return None
  }
  Some({
    record_headers: name.record_headers +
    measurement.record_headers +
    writer.record_headers +
    52L,
    reference_slots: name.reference_slots +
    measurement.reference_slots +
    writer.reference_slots +
    80L,
    scalar_words: name.scalar_words +
    measurement.scalar_words +
    writer.scalar_words +
    80L,
    owned_utf16_units: name.owned_utf16_units +
    measurement.owned_utf16_units +
    writer.owned_utf16_units,
    owned_wire_bytes: measurement.owned_wire_bytes,
  })
}

///|
/// Recover the Preview binding only from the issued source Artifact for the
/// exact Run Invocation and checked source Result. Store custody is a separate
/// obligation and is not established by this projection.
pub fn effect_source_artifact_preview_binding(
  artifact : PublicationContract,
  invocation_cid : String,
  source_result : String,
  store_authority_cid : String,
) -> Result[(String, String), EffectSourceArtifactIssue] {
  effect_relation_source_artifact_preview_binding(
    artifact,
    invocation_cid,
    Result(source_result),
    store_authority_cid,
  )
}

///|
pub fn effect_table_input_artifact_preview_binding(
  artifact : PublicationContract,
  invocation_cid : String,
  table_input : String,
  store_authority_cid : String,
) -> Result[(String, String), EffectSourceArtifactIssue] {
  effect_relation_source_artifact_preview_binding(
    artifact,
    invocation_cid,
    TableInput(table_input),
    store_authority_cid,
  )
}

///|
fn effect_source_artifact_relation_source(
  artifact : PublicationContract,
) -> EffectPreviewRelationSource? {
  if artifact.name != "effect_source_artifact" {
    return None
  }
  match
    (
      contract_string(artifact, "source_result"),
      contract_string(artifact, "source_table_input"),
    ) {
    (Some(name), None) => Some(Result(name))
    (None, Some(name)) => Some(TableInput(name))
    _ => None
  }
}

///|
fn effect_relation_source_artifact_preview_binding(
  artifact : PublicationContract,
  invocation_cid : String,
  source : EffectPreviewRelationSource,
  store_authority_cid : String,
) -> Result[(String, String), EffectSourceArtifactIssue] {
  if artifact.name != "effect_source_artifact" ||
    !valid_contract_cid(invocation_cid) ||
    !valid_contract_cid(store_authority_cid) ||
    contract_string(artifact, "invocation_cid") != Some(invocation_cid) ||
    effect_source_artifact_relation_source(artifact) != Some(source) ||
    contract_string(artifact, "store_authority_cid") !=
    Some(store_authority_cid) {
    return Err(EffectSourceWrongContract)
  }
  guard contract_string(artifact, "source_binding_cid") is Some(binding) &&
    valid_contract_cid(binding) else {
    return Err(EffectSourceInvalidBinding)
  }
  Ok((artifact.identity, binding))
}

///|
/// Read the original captured physical source's selected retention identity.
/// Full computation-chain admission remains with its original caller. This
/// borrowed DATA is neither a new retention contract nor a Store holding.
pub fn captured_run_effect_source_retention_cid(
  captured : PublicationContract,
  effect_id : String,
) -> String? {
  guard captured.name == "captured_run" &&
    @json.object_field(captured.value, "effect_context") is Some(context) &&
    @json.object_field(context, "effect_source_artifacts") is Some(sources) &&
    @json.object_field(sources, effect_id) is Some(source) else {
    return None
  }
  optional_string(@json.object_field(source, "effective_retention_policy_cid"))
}
