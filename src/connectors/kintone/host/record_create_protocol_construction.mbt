///|
/// Native protocol constructors only. The same original Form/Mapping/request
/// remains borrowed. Parser/index/normalization, received Bytes, JS envelopes,
/// credentials and failed physical children remain separate caller components.
pub(all) struct RecordCreateProtocolConstructionInventory {
  representation : @shape.CollectionConstructionExtent
  owned_utf16_units : Int64
  owned_wire_bytes : Int64
}

///|
/// Complete project_form_fields + original Form correspondence constructor
/// envelope. Original paths are compared in place inside their existing owner;
/// no later response bound substitutes for a snapshot of original geometry.
/// This runs no projection and issues no current/read/write/capacity grant.
pub fn record_create_mapped_form_recheck_construction_inventory(
  mapping : RecordCreateMapping,
  limits : @catalog.FormFieldLimits,
) -> RecordCreateProtocolConstructionInventory? {
  if !record_create_mapping_is_original(mapping) ||
    limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_fields < 1 ||
    limits.max_name_units < 1 {
    return None
  }
  let n = limits.max_nodes.to_int64()
  let f = Int::min(limits.max_fields, limits.max_nodes).to_int64()
  let d = Int::min(limits.max_depth, limits.max_nodes).to_int64()
  // Shared JSON nodes bound ALL options and lookup entries together. Every
  // Object cursor is opened at most twice: properties in guard+loop, or a
  // SUBTABLE field in metadata+children selection. Hence <=2N maps and <=2N
  // entries across those maps, not N maps of width N.
  // Per field: metadata1H10R; seven private Options7H7R7W (co-count Bool
  // scalar/reference alternatives); metadata Ok1H1R1W; flag/optional-text
  // Results4H4R4W; non-retained form_text Some <=2F+3N+1;
  // scalar-reader Results <=8F+3N+1; Presence6H6R6W; names Ok1H1R1W;
  // pending tuple1H2R, popped Some1H1R1W and two length Options2H4W.
  // Initial pending/root and final Catalog/Ok/Form+Err/InvalidField+Err
  // controls add12H14R12W. Input names/text and original paths are borrowed.
  guard @shape.collection_construction_extent({
      records: 12L + 34L * f + 10L * n,
      record_references: 14L + 42L * f + 12L * n,
      record_words: 12L + 34L * f + 8L * n,
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
/// One standard row's SAME original Mapping correspondence, CREATE response
/// acknowledgement and typed provider outcome. The prior native constructor
/// selects max_records=1. This is not a batch quote or terminal Ledger proof.
pub fn record_create_mapped_response_construction_inventory(
  mapping : RecordCreateMapping,
  limits : @catalog.RecordMutationLimits,
) -> RecordCreateProtocolConstructionInventory? {
  if !record_create_mapping_is_original(mapping) ||
    limits.max_records != 1 ||
    limits.max_identity_bytes < 1 ||
    limits.max_comparison_work < 1 ||
    limits.max_output_bytes < 1 ||
    limits.max_output_nodes < 1 ||
    limits.max_output_depth < 1 {
    return None
  }
  // Invalid received objects can be as wide as the complete admitted tree.
  // The allowed ids/revisions pair NEVER bounds that failed constructor.
  guard @decode.closed_object_field_construction_extent(
      Some(limits.max_output_nodes),
      2,
      0L,
    )
    is Some(closed) &&
    @decode.issue_construction_extent(limits.max_output_depth) is Some(issue) &&
    @shape.scale_collection_construction_extent(
      @decode.indexed_child_construction_extent(),
      4L,
    )
    is Some(children) else {
    return None
  }
  // Ack/self-Some/Ok3H5R2W; id+revision tuple1H2R; text Results2H2R2W;
  // length Options2H4W; cursor Ok1H1R1W; identity-work Ok1H2W;
  // outcome+Ok2H4R1W; EncodedDocument1H1R3W; three failure wrappers3H3R3W.
  // Mapping validation additionally owns5 captured predicates7R and its
  // one-record copy plus all actual writable-field names (not just Mapping
  // destinations). Strings remain the original decoder/installed Form borrows.
  guard @shape.collection_construction_extent({
      records: 21L,
      record_references: 25L,
      record_words: 18L,
      reference_arrays: 5L,
      reference_items: 6L +
      @catalog.form_field_count(mapping.original.catalog).to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(body) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) &&
    @encode.text_writer_construction_inventory(
      limits.max_output_bytes,
      limits.max_output_nodes,
      limits.max_output_depth,
    )
    is Some(writer) else {
    return None
  }
  guard @shape.compose_collection_construction_extents([
      body,
      closed,
      issue,
      children,
      {
        record_headers: hash.record_headers,
        reference_slots: hash.reference_slots,
        scalar_words: hash.scalar_words,
      },
      {
        record_headers: writer.record_headers,
        reference_slots: writer.reference_slots,
        scalar_words: writer.scalar_words,
      },
    ])
    is Some(representation) else {
    return None
  }
  Some({
    representation,
    owned_utf16_units: hash.owned_utf16_units + writer.owned_utf16_units,
    owned_wire_bytes: hash.owned_wire_bytes,
  })
}

///|
fn record_create_protocol_capacity(
  inventory : RecordCreateProtocolConstructionInventory,
) -> @execution.ExecutionCapacity? {
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: inventory.representation.record_headers,
      reference_slots: inventory.representation.reference_slots,
      scalar_words: inventory.representation.scalar_words,
      owned_utf16_units: inventory.owned_utf16_units,
      owned_wire_bytes: inventory.owned_wire_bytes,
    },
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

///|
pub fn record_create_mapped_form_recheck_construction_capacity(
  mapping : RecordCreateMapping,
  limits : @catalog.FormFieldLimits,
) -> @execution.ExecutionCapacity? {
  guard record_create_mapped_form_recheck_construction_inventory(
      mapping, limits,
    )
    is Some(inventory) else {
    return None
  }
  record_create_protocol_capacity(inventory)
}

///|
pub fn record_create_mapped_response_construction_capacity(
  mapping : RecordCreateMapping,
  limits : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  guard record_create_mapped_response_construction_inventory(mapping, limits)
    is Some(inventory) else {
    return None
  }
  record_create_protocol_capacity(inventory)
}
