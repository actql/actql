///|
/// Original relation-write Mapping construction. Existing Row document,
/// parser/contract/writer inventories cover the selected view, complete
/// carrier identity and the later target-field extraction. Separate writer,
/// parsed schema and small envelope inventories cover emitted identities and
/// sealing. No Mapping or schema is constructed by this quantity inspection.
pub fn record_update_mapping_construction_capacity(
  original : RecordDeclaration,
  source_count : Int,
  input_units : Int64,
  limits : @rows.RowDeclarationLimits,
) -> @execution.ExecutionCapacity? {
  if source_count < 1 ||
    source_count > limits.max_fields ||
    input_units < 0L ||
    limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_fields < 1 ||
    limits.max_views < 1 {
    return None
  }
  let mut units = input_units
  for
    wires in [original.declaration.view_bodies, original.declaration.contracts] {
    for wire in wires {
      if units > 9223372036854775807L / 64L - wire.length().to_int64() {
        return None
      }
      units += wire.length().to_int64()
    }
  }
  if units > 9223372036854775807L / 64L {
    return None
  }
  // UTF8 costs at most3 bytes per UTF16 unit. Original schema text plus
  // repeated fixed envelopes/sources bound the emitted prefixes. The native
  // constructor still keeps ALL selected semantic byte/node/depth limits.
  let bytes = Int64::min(
    limits.max_bytes.to_int64(),
    4096L + 6L * units + 1024L * source_count.to_int64(),
  ).to_int()
  let nodes = Int64::min(
    limits.max_nodes.to_int64(),
    256L + units + 64L * source_count.to_int64(),
  ).to_int()
  guard @rows.relation_document_mapping_construction_inventory({
      max_bytes: bytes,
      max_nodes: nodes,
      max_depth: Int::min(nodes, limits.max_depth),
      max_rows: 1,
    })
    is Some(stage) else {
    return None
  }
  let count = @catalog.form_field_count(original.catalog)
  if count == 2147483647 {
    return None
  }
  let fields = Int::min(limits.max_fields, count + 1).to_int64()
  // Original native Mapping/self, RowMapping, retained name vectors and
  // decoded name backing. The original Catalog/declaration remain borrowed.
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 24L + 4L * fields,
    reference_slots: 48L + 12L * fields,
    scalar_words: 16L + 4L * fields,
    owned_utf16_units: 2L * bytes.to_int64() + 4L * input_units + 512L,
    owned_wire_bytes: 0L,
  }
  guard record_read_decoded_construction(bytes, nodes, limits.max_depth, false)
    is Some(schema_json) &&
    record_read_writer_units(bytes, nodes, limits.max_depth) is Some(writer) &&
    @encode.hash_writer_construction_inventory(nodes, limits.max_depth)
    is Some(hash) &&
    @shape.collection_construction_extent({
      records: 96L + 24L * fields + 12L * source_count.to_int64(),
      record_references: 192L + 48L * fields + 24L * source_count.to_int64(),
      record_words: 96L + 24L * fields,
      reference_arrays: 24L,
      reference_items: 128L + 16L * fields + 12L * source_count.to_int64(),
      scalar_arrays: 2L,
      scalar_items: 16L,
      maps: 8L,
      map_entries: 96L + 12L * fields + 8L * source_count.to_int64(),
    })
    is Some(envelopes) else {
    return None
  }
  // Two actual complete checked reads: original Relation selection and the
  // final Mapping target-field extraction. The latter is bounded by the same
  // complete inventory, including its conservative canonical/schema controls.
  // It does not parse the original metadata six more times. Schema JSON parse,
  // schema/request/resource/schema-identity/seal/final writers and hash outputs
  // are independent overlapping families below, not six Mapping admissions.
  guard @execution.compose_preparation_representation([
      stage,
      stage,
      schema_json,
      writer,
      writer,
      writer,
      writer,
      writer,
      writer,
      record_read_collection_units(envelopes),
      {
        record_headers: 5L * hash.record_headers,
        reference_slots: 5L * hash.reference_slots,
        scalar_words: 5L * hash.scalar_words,
        owned_utf16_units: 5L * hash.owned_utf16_units + 8L * bytes.to_int64(),
        owned_wire_bytes: 5L * hash.owned_wire_bytes + 8L * bytes.to_int64(),
      },
    ])
    is Some(workspace) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained,
    workspace,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
/// One installed Kintone driver/request/recipe assembly. Original Mapping,
/// metadata and Site are borrowed. This covers method+receiver closures,
/// fixed initial/maximum vectors,5 member/12 row/13 Credential slot records,
/// binding/current predicates and empty nominal-holder maps. Per-row entries
/// and their payloads are separately priced by the operation recipe.
pub fn record_update_installation_construction_capacity(
  fields : Int,
  text_units : Int,
  retained_text_units : Int,
) -> @execution.ExecutionCapacity? {
  if fields < 1 || text_units < 1 || retained_text_units < 0 {
    return None
  }
  let f = fields.to_int64()
  guard @shape.collection_construction_extent({
      records: 2L * 192L + 96L,
      record_references: 14L * 192L + 768L + 8L * f,
      record_words: 256L + 8L * f,
      reference_arrays: 64L,
      reference_items: 1024L + 5L + 12L + 13L + 8L * f,
      scalar_arrays: 16L,
      scalar_items: 512L,
      maps: 8L,
      map_entries: 2L,
    })
    is Some(owned) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: owned.record_headers,
      reference_slots: owned.reference_slots,
      scalar_words: owned.scalar_words,
      // Borrowed configuration/metadata Strings are not copied output.
      // The caller counts only new connection/path/CID spellings here.
      owned_utf16_units: retained_text_units.to_int64(),
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: 256L,
      reference_slots: 2048L + 16L * f,
      scalar_words: 256L,
      owned_utf16_units: 24L * text_units.to_int64(),
      owned_wire_bytes: 12L * text_units.to_int64(),
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}
