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
  record_mutation_mapping_construction_capacity(
    original,
    source_count,
    input_units,
    limits,
    None,
  )
}

///|
/// The key and proposed write sources are already owned by the caller.
/// input_units counts the resource and source spellings before the key.
pub fn record_key_upsert_mapping_construction_capacity(
  original : RecordDeclaration,
  key : String,
  source_count : Int,
  input_units : Int64,
  limits : @rows.RowDeclarationLimits,
) -> @execution.ExecutionCapacity? {
  if key.is_empty() || key.length() > limits.max_bytes {
    return None
  }
  record_mutation_mapping_construction_capacity(
    original,
    source_count,
    input_units,
    limits,
    Some(key.length()),
  )
}

///|
fn record_mutation_mapping_construction_capacity(
  original : RecordDeclaration,
  source_count : Int,
  input_units : Int64,
  limits : @rows.RowDeclarationLimits,
  key_units : Int?,
) -> @execution.ExecutionCapacity? {
  let unit_bound = 9223372036854775807L / 64L
  if source_count < 1 ||
    source_count > limits.max_fields ||
    input_units < 0L ||
    input_units > unit_bound ||
    limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_fields < 1 ||
    limits.max_views < 1 {
    return None
  }
  // The required names in a successful Mapping must also be source targets.
  // Reserve a further copy of those spellings plus the keyed relation fields.
  let mut units = match key_units {
    Some(key) => 2L * input_units + key.to_int64() + 64L
    None => input_units
  }
  for
    wires in [original.declaration.view_bodies, original.declaration.contracts] {
    for wire in wires {
      if units > unit_bound - wire.length().to_int64() {
        return None
      }
      units += wire.length().to_int64()
    }
  }
  if units > unit_bound {
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
  let extra_key_refs = if key_units is Some(_) { 1L } else { 0L }
  // Original native Mapping/self, RowMapping, retained name vectors and
  // decoded name backing. The original Catalog/declaration remain borrowed.
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 24L + 4L * fields,
    reference_slots: 48L + 12L * fields + extra_key_refs,
    scalar_words: 16L + 4L * fields,
    owned_utf16_units: 2L * bytes.to_int64() + 4L * input_units + 512L,
    owned_wire_bytes: 0L,
  }
  let selection_workspace = match key_units {
    None => stage
    Some(_) => {
      let required = Int::min(count, limits.max_fields).to_int64()
      let source = source_count.to_int64()
      let copied = @catalog.record_create_copied_target_bound(
        original.catalog,
        limits.max_fields,
        limits.max_nodes,
      ).to_int64()
      guard @shape.collection_construction_extent({
          // Key/field contract admission, copied-target Map with its growth,
          // required field scan, filtering and the sorted required prefix.
          // These arrays borrow field codes from the original Form.
          records: 24L + 8L * required + 4L * source,
          record_references: 36L + 12L * required + 6L * source,
          record_words: 24L + 6L * required + 4L * source,
          reference_arrays: 6L + source,
          reference_items: 8L + 4L * required + 2L * source,
          scalar_arrays: 0L,
          scalar_items: 0L,
          maps: 1L,
          map_entries: copied,
        })
        is Some(work) else {
        return None
      }
      record_read_collection_units(work)
    }
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
  // UPDATE also extracts fields from its completed Mapping. UPSERT retains
  // the selected sources directly and uses the Form selection workspace.
  // The separate schema, identity and Mapping writers share the checked input.
  guard @execution.compose_preparation_representation([
      stage,
      selection_workspace,
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
  record_mutation_installation_construction_capacity(
    fields, text_units, retained_text_units, false,
  )
}

///|
pub fn record_key_upsert_installation_construction_capacity(
  fields : Int,
  text_units : Int,
  retained_text_units : Int,
) -> @execution.ExecutionCapacity? {
  record_mutation_installation_construction_capacity(
    fields, text_units, retained_text_units, true,
  )
}

///|
fn record_mutation_installation_construction_capacity(
  fields : Int,
  text_units : Int,
  retained_text_units : Int,
  keyed : Bool,
) -> @execution.ExecutionCapacity? {
  if fields < 1 || text_units < 1 || retained_text_units < 0 {
    return None
  }
  let f = fields.to_int64()
  let extra = if keyed { 1L } else { 0L }
  let slots = if keyed { 2L + 13L + 11L } else { 5L + 12L + 13L }
  guard @shape.collection_construction_extent({
      // The keyed adapter captures additional lookup, branch and saved
      // codec method closures, and keeps its two write slots distinct.
      records: 2L * 192L + 96L + 24L * extra,
      record_references: 14L * 192L + 768L + 8L * f + 96L * extra,
      record_words: 256L + 8L * f + 16L * extra,
      reference_arrays: 64L + 8L * extra,
      reference_items: 1024L + slots + 8L * f + 32L * extra,
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
