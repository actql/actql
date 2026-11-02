///|
fn record_read_collection_units(
  value : @shape.CollectionConstructionExtent,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
// The preserving metadata parser and normalizing schema parser are distinct
// original operations. This inventory neither parses nor admits their input.
fn record_read_decoded_construction(
  bytes : Int,
  nodes : Int,
  depth : Int,
  normalize_keys : Bool,
) -> @execution.PreparationRepresentationUnits? {
  guard @source.json_construction_extent(bytes, nodes, depth, normalize_keys~)
    is Some(parsed) &&
    @decode.admission_construction_inventory(nodes, nodes, nodes, nodes, depth)
    is Some(index) else {
    return None
  }
  Some({
    record_headers: parsed.record_headers +
    index.indexed.record_headers +
    index.keys.record_headers +
    index.ancestry.record_headers +
    index.controls.record_headers,
    reference_slots: parsed.reference_slots +
    index.indexed.reference_slots +
    index.keys.reference_slots +
    index.ancestry.reference_slots +
    index.controls.reference_slots,
    scalar_words: parsed.scalar_words +
    index.indexed.scalar_words +
    index.keys.scalar_words +
    index.ancestry.scalar_words +
    index.controls.scalar_words,
    owned_utf16_units: parsed.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
fn record_read_writer_units(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  guard @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(writer) else {
    return None
  }
  Some({
    record_headers: writer.record_headers,
    reference_slots: writer.reference_slots,
    scalar_words: writer.scalar_words,
    owned_utf16_units: writer.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
// Same Form projection family inventoried by mapped-form recheck; no Mapping
// correspondence is executed here. Its extra comparison carriers co-count.
fn record_read_form_inventory(
  body_bytes : Int,
  limits : @catalog.FormFieldLimits,
) -> RecordCreateProtocolConstructionInventory? {
  let n = Int::min(body_bytes, limits.max_nodes).to_int64()
  let f = Int::min(body_bytes, Int::min(limits.max_fields, limits.max_nodes)).to_int64()
  let d = Int::min(body_bytes, Int::min(limits.max_depth, limits.max_nodes)).to_int64()
  // Shared JSON nodes bound ALL options and lookup entries together. Every
  // Object cursor is opened at most twice: properties in guard+loop, or a
  // SUBTABLE field in metadata+children selection. Hence <=2N maps and <=2N
  // entries across those maps, not N maps of width N.
  // Per field: metadata1H10R; seven private Options7H7R7W (co-count Bool
  // scalar/reference alternatives); metadata Ok1H1R1W; flag/optional-text
  // Results4H4R4W; non-retained form_text Some <=2F+3N+1;
  // scalar-reader Results <=8F+3N+1; Presence6H6R6W; names Ok1H1R1W;
  // pending tuple1H2R, popped Some1H1R1W and two length Options2H4W.
  // Full correspondence additionally calls form_field_named twice per field:
  // two original-metadata Some wrappers2H2R2W plus match tuple1H2R.
  // Initial pending/root and final Catalog/Ok/Form+Err/InvalidField+Err
  // controls add12H14R12W. Input names/text and original paths are borrowed.
  guard @shape.collection_construction_extent({
      records: 12L + 37L * f + 10L * n,
      record_references: 14L + 46L * f + 12L * n,
      record_words: 12L + 36L * f + 8L * n,
      // fields/pending/initial-prefix; each field's path, options names and
      // lookup target arrays. Arrays of empty lookup targets still count.
      reference_arrays: 3L + 3L * f,
      reference_items: 2L * f + f * d + 2L * n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L * n,
      map_entries: 2L * n,
    })
    is Some(body) &&
    @shape.scale_collection_construction_extent(
      @decode.indexed_child_construction_extent(),
      2L + 11L * f + 4L * n,
    )
    is Some(children) &&
    @shape.scale_collection_construction_extent(
      @decode.indexed_field_construction_extent(),
      f,
    )
    is Some(fields) &&
    @decode.issue_construction_extent(limits.max_depth) is Some(issue) &&
    @shape.scale_collection_construction_extent(issue, f + 1L) is Some(issues) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) else {
    return None
  }
  // Each lookup field deliberately tries decode.text before array_length;
  // its normal array alternative owns an Issue/path. Co-count every such
  // prefix plus one terminal wrong-kind refusal. SHA is the SAME source
  // digest sink/finish family; its unused fixed writer controls are co-counted.
  guard @shape.compose_collection_construction_extents([
      body,
      children,
      fields,
      issues,
      {
        record_headers: hash.record_headers,
        reference_slots: hash.reference_slots,
        scalar_words: hash.scalar_words,
      },
    ])
    is Some(representation) else {
    return None
  }
  Some({
    representation,
    owned_utf16_units: hash.owned_utf16_units,
    owned_wire_bytes: hash.owned_wire_bytes,
  })
}

///|
/// Full synchronous ProjectForm/DeclareRecords/DeclarationJson native demand.
/// Raw-byte and identifier extents come from the original bounded inputs.
/// Every provider prefix, including option/lookup arrays and SUBTABLE path
/// copies, stays backed until initializer retirement; this issues no original.
pub fn record_read_declaration_construction_capacity(
  body_bytes : Int,
  encoded_units : Int,
  selected_count : Int,
  selected_units : Int,
  app_units : Int,
  resource_units : Int,
  connector_units : Int,
  revision_units : Int,
  form : @catalog.FormFieldLimits,
  values : @catalog.RecordValueLimits,
  declaration : @rows.RowDeclarationLimits,
) -> @execution.ExecutionCapacity? {
  if body_bytes < 0 ||
    encoded_units < 0 ||
    selected_count < 0 ||
    selected_units < 0 ||
    app_units < 0 ||
    resource_units < 0 ||
    connector_units < 0 ||
    revision_units < 0 ||
    form.max_bytes < 1 ||
    body_bytes > form.max_bytes ||
    form.max_nodes < 1 ||
    form.max_depth < 1 ||
    form.max_fields < 1 ||
    form.max_name_units < 1 ||
    values.max_columns < 1 ||
    values.max_name_bytes < 1 ||
    values.max_nodes < 1 ||
    values.max_depth < 1 ||
    values.max_text_bytes < 1 ||
    declaration.max_bytes < 1 {
    return None
  }
  let b = Int::max(1, body_bytes)
  let f = Int::min(b, Int::min(form.max_fields, form.max_nodes)).to_int64()
  // Each selected tree is disjoint (top-level names are unique). A SUBTABLE
  // contributes array+object+synthetic id, all other supported fields <=array
  // plus string. The producer creates its initial text Contract even when it
  // subsequently refuses NUMBER/CALC; cap successful traversal by node budget.
  let c = Int64::min(3L * f + 1L, values.max_nodes.to_int64() + 1L)
  let object_entries = 4L * f + 2L
  if object_entries > 2147483647L {
    return None
  }
  let string_contract = "{\"nullable\":false,\"type\":\"string\"}"
    .length()
    .to_int64()
  let object_contract = "{\"additional_properties\":false,\"fields\":{},\"nullable\":false,\"type\":\"object\"}"
    .length()
    .to_int64()
  let array_contract = "{\"items\":{},\"nullable\":false,\"type\":\"array\"}"
    .length()
    .to_int64() -
    2L
  let schema_bound = 2L +
    6L * body_bytes.to_int64() +
    string_contract +
    7L +
    f * (object_contract + array_contract + string_contract + 11L)
  let sb = Int64::min(declaration.max_bytes.to_int64(), schema_bound).to_int()
  let sn = Int64::min(values.max_nodes.to_int64(), 4L + 12L * f).to_int()
  guard record_read_form_inventory(b, form) is Some(metadata) &&
    record_read_decoded_construction(
      b,
      Int::min(b, form.max_nodes),
      form.max_depth,
      false,
    )
    is Some(parsed) &&
    @contract.object_retained_construction_extent(
      object_entries.to_int(),
      (f + 2L).to_int(),
    )
    is Some(objects) &&
    @contract.object_construction_inventory(
      object_entries.to_int(),
      Int::min(b, values.max_name_bytes),
    )
    is Some(object_work) &&
    @contract.checked_emission_construction_extent(c.to_int()) is Some(emission) &&
    record_read_writer_units(sb, sn, values.max_depth) is Some(writer) &&
    @rows.single_relation_declaration_construction_inventory(
      sb,
      sn,
      (f + 1L).to_int(),
      "{\"relation_keys\":{\"candidate_keys\":[[\"$id\"]]}}".length(),
      5,
      resource_units,
      connector_units,
      revision_units,
      declaration,
    )
    is Some(common) &&
    @shape.collection_construction_extent({
      // Per field: primitive/Text/TextLimits, alternate nullable Contract,
      // array+Option+Result, recursive result/lookup/path selection, input tuple.
      // RecordDeclaration/self Result + original names copy are fixed below.
      records: 16L + 16L * c,
      record_references: 24L + 24L * c,
      record_words: 16L + 16L * c,
      reference_arrays: 8L + 3L * f,
      reference_items: 8L + 6L * f + selected_count.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L + f,
      map_entries: 2L * f,
    })
    is Some(schema) else {
    return None
  }
  guard @execution.compose_preparation_representation([
      parsed,
      record_read_collection_units(metadata.representation),
      record_read_collection_units(objects),
      record_read_collection_units(object_work.scratch),
      record_read_collection_units(emission),
      record_read_collection_units(schema),
      writer,
      common,
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: metadata.owned_utf16_units +
        object_work.scratch_utf16_units +
        encoded_units.to_int64() +
        selected_units.to_int64() +
        app_units.to_int64() +
        sb.to_int64(),
        owned_wire_bytes: metadata.owned_wire_bytes +
        body_bytes.to_int64() +
        sb.to_int64(),
      },
    ])
    is Some(peak) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained: peak,
    workspace: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}
