///|
/// Native UPDATE constructor DATA. Original Mapping/Catalog/input backing,
/// Host JSON envelopes, physical buffers and permissions remain separate.
/// Returned immutable material and ended construction scratch have distinct
/// lifetimes; these quantities neither reserve nor retire either lifetime.
pub(all) struct RecordUpdateConstructionInventory {
  retained : @execution.PreparationRepresentationUnits
  workspace : @execution.PreparationRepresentationUnits
}

///|
fn update_construction_empty() -> @execution.PreparationRepresentationUnits {
  {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
fn update_construction_capacity(
  inventory : RecordUpdateConstructionInventory,
) -> @execution.ExecutionCapacity? {
  @execution.preparation_execution_capacity({
    retained: inventory.retained,
    workspace: inventory.workspace,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
/// SAME mapped Value admission as CREATE, followed by the UPDATE proposal.
/// The shared native admission envelope co-counts CREATE's unused request
/// writer as workspace only. No synthetic CREATE Mapping is constructed.
pub fn record_update_proposal_construction_inventory(
  mapping : RecordUpdateMapping,
  max_input_bytes : Int,
  write : @catalog.RecordWriteLimits,
  request : @catalog.RecordMutationLimits,
) -> RecordUpdateConstructionInventory? {
  if !record_update_mapping_is_original(mapping) {
    return None
  }
  guard record_write_admission_construction_inventory(
      mapping.original,
      mapping.written_fields.length(),
      max_input_bytes,
      write,
      request,
    )
    is Some(native) &&
    record_read_decoded_construction(
      max_input_bytes,
      Int::min(max_input_bytes, write.max_nodes),
      Int::min(max_input_bytes, write.max_depth),
      false,
    )
    is Some(parser) &&
    record_write_value_construction_extents(mapping.original, write)
    is Some((values, _)) else {
    return None
  }
  let f = Int::min(write.max_fields, write.max_nodes).to_int64()
  // Retained: proposal/self, WriteValues/original cells and EncodedDocument;
  // per field, both original/rechecked Contract alternatives conservatively
  // fit the SAME6H10R5W family. The checked original Value body is held once.
  // Input-decoded String backing, native value document and bare value wire
  // may overlap. Timestamp normalization adds at most39 units per field.
  guard @shape.collection_construction_extent({
      records: 8L + 16L * f,
      record_references: 14L + 26L * f,
      record_words: 6L + 10L * f,
      reference_arrays: 4L,
      reference_items: 4L + 3L * f,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(output) &&
    @execution.compose_preparation_representation([
      record_read_collection_units(values),
      record_read_collection_units(output),
      {
        ..update_construction_empty(),
        owned_utf16_units: max_input_bytes.to_int64() +
        2L * write.max_output_bytes.to_int64() +
        39L * f,
      },
    ])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      parser,
      record_read_collection_units(native.representation),
      {
        ..update_construction_empty(),
        owned_utf16_units: native.owned_utf16_units,
      },
    ])
    is Some(workspace) else {
    return None
  }
  Some({ retained, workspace, })
}

///|
/// Complete native Form recheck returns Unit. The original Catalog is
/// borrowed, and every newly parsed Form/path/compare control ends here.
pub fn record_update_form_construction_inventory(
  mapping : RecordUpdateMapping,
  body_bytes : Int,
  limits : @catalog.FormFieldLimits,
) -> RecordUpdateConstructionInventory? {
  if !record_update_mapping_is_original(mapping) {
    return None
  }
  guard managed_record_form_inventory(mapping.original, body_bytes, limits)
    is Some(workspace) else {
    return None
  }
  Some({ retained: update_construction_empty(), workspace, })
}

///|
/// Complete native target page/checked before/version production. The SAME
/// page producer supplies its original parse, contract and value workspace.
/// Retained output keeps its immutable decoder index/String/Span material,
/// Native page, checked Values, before text and version; no parser work stack
/// or key-admission Map is credited as continuing output.
pub fn record_update_target_construction_inventory(
  mapping : RecordUpdateMapping,
  body_bytes : Int,
  pages : @catalog.RecordPageLimits,
  values : @catalog.RecordValueLimits,
  limits : @catalog.RecordMutationLimits,
) -> RecordUpdateConstructionInventory? {
  if !record_update_mapping_is_original(mapping) ||
    !record_target_before_limits_valid(limits) ||
    pages.max_rows != 1 ||
    mapping.before_fields.length() == 2147483647 {
    return None
  }
  let columns = mapping.before_fields.length() + 1
  guard managed_record_page_inventory(
      mapping.original,
      mapping.before_fields,
      columns,
      body_bytes,
      pages,
      values,
      limits.max_comparison_work,
    )
    is Some(page) &&
    @catalog.selected_form_construction_geometry(
      mapping.original.catalog,
      mapping.before_fields,
    )
    is Some(g) else {
    return None
  }
  let b = Int::max(1, body_bytes)
  let nodes = Int::min(b, pages.max_nodes)
  let n = nodes.to_int64()
  let typed = Int::min(nodes, values.max_nodes).to_int64()
  let f = g.fields.to_int64()
  let t = g.tables.to_int64()
  let entries = f + t + 1L
  // Same primitive/Decimal/date/array/object before projection as the managed
  // reader. JSON String escaping costs at most6 units per source unit;
  // timestamp spelling adds at most43 units per value. Names are the original
  // selected metadata. Clamp constructor demand, not its semantic limits.
  let before_bytes = Int64::min(
    limits.max_output_bytes.to_int64(),
    6L * b.to_int64() + 43L * typed + 6L * g.code_units + 128L,
  ).to_int()
  guard @decode.admission_construction_inventory(
      nodes,
      nodes - 1,
      nodes,
      nodes,
      Int::min(nodes, pages.max_depth),
    )
    is Some(index) &&
    @source.json_index_borrowed_construction_extent(
      nodes,
      nodes - 1,
      b.to_int64(),
      keep_spans=true,
    )
    is Some(strings) &&
    @contract.object_retained_construction_extent(
      entries.to_int(),
      g.tables + 1,
    )
    is Some(objects) &&
    @shape.collection_construction_extent({
      // Page/checked/target/Preview/self and fixed projection records. Raw
      // records/fields/table rows and their retained child Cursors fit5N
      // records/12N refs/3N words. Type alternatives below co-count the actual
      // original contract forest, immutable Value/FrozenArray/field-pair body,
      // checked cells and their complete row/column arrays.
      records: 20L + 5L * n + 16L * (3L * f + 1L) + 20L * t + 5L * typed,
      record_references: 40L +
      12L * n +
      24L * (3L * f + 1L) +
      16L * t +
      8L * typed,
      record_words: 20L + 3L * n + 16L * (3L * f + 1L) + 14L * t + 2L * typed,
      reference_arrays: 8L + 2L * n + typed + 3L * f,
      reference_items: 8L +
      4L * n +
      3L * typed +
      6L * f +
      columns.to_int64() +
      Int::min(nodes, pages.max_cells).to_int64() * g.max_children.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(output) &&
    record_read_writer_units(
      before_bytes,
      limits.max_output_nodes,
      limits.max_output_depth,
    )
    is Some(writer) &&
    @encode.hash_writer_live_key_inventory(0, 1) is Some(hash) else {
    return None
  }
  guard @execution.compose_preparation_representation([
      record_read_collection_units(objects),
      record_read_collection_units(output),
      {
        record_headers: index.indexed.record_headers + strings.record_headers,
        reference_slots: index.indexed.reference_slots + strings.reference_slots,
        scalar_words: index.indexed.scalar_words + strings.scalar_words,
        // Decimal coefficient normalization can own one additional complete
        // source-text bound. Native response SHA64 and version CID71 remain.
        owned_utf16_units: strings.owned_utf16_units +
        b.to_int64() +
        43L * typed +
        before_bytes.to_int64() +
        135L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      page,
      writer,
      {
        record_headers: hash.record_headers + 24L,
        reference_slots: hash.reference_slots + 48L + 4L * columns.to_int64(),
        scalar_words: hash.scalar_words + 24L,
        owned_utf16_units: hash.owned_utf16_units,
        owned_wire_bytes: hash.owned_wire_bytes,
      },
    ])
    is Some(workspace) else {
    return None
  }
  Some({ retained, workspace, })
}

///|
/// Original final native PUT serialization. Proposal/Preview values and their
/// complete page remain borrowed; only request/document and its one-record
/// pair vector survive this constructor. No revision or values are rebuilt.
pub fn record_update_finalization_construction_inventory(
  mapping : RecordUpdateMapping,
  limits : @catalog.RecordMutationLimits,
) -> RecordUpdateConstructionInventory? {
  if !record_update_mapping_is_original(mapping) ||
    !record_target_before_limits_valid(limits) ||
    limits.max_records != 1 {
    return None
  }
  let f = mapping.before_fields.length().to_int64()
  guard record_read_writer_units(
      limits.max_output_bytes,
      limits.max_output_nodes,
      limits.max_output_depth,
    )
    is Some(writer) &&
    @shape.collection_construction_extent({
      records: 32L + 6L * f,
      record_references: 64L + 12L * f,
      record_words: 32L + 4L * f,
      reference_arrays: 12L,
      reference_items: 12L + 4L * f,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(checks) &&
    @execution.compose_preparation_representation([
      writer,
      record_read_collection_units(checks),
    ])
    is Some(workspace) else {
    return None
  }
  Some({
    retained: {
      record_headers: 9L,
      reference_slots: 18L,
      scalar_words: 10L,
      owned_utf16_units: limits.max_output_bytes.to_int64(),
      owned_wire_bytes: 0L,
    },
    workspace,
  })
}

///|
pub fn record_update_proposal_construction_capacity(
  mapping : RecordUpdateMapping,
  max_input_bytes : Int,
  write : @catalog.RecordWriteLimits,
  request : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  guard record_update_proposal_construction_inventory(
      mapping, max_input_bytes, write, request,
    )
    is Some(inventory) else {
    return None
  }
  update_construction_capacity(inventory)
}

///|
pub fn record_update_form_construction_capacity(
  mapping : RecordUpdateMapping,
  body_bytes : Int,
  limits : @catalog.FormFieldLimits,
) -> @execution.ExecutionCapacity? {
  guard record_update_form_construction_inventory(mapping, body_bytes, limits)
    is Some(inventory) else {
    return None
  }
  update_construction_capacity(inventory)
}

///|
pub fn record_update_target_construction_capacity(
  mapping : RecordUpdateMapping,
  body_bytes : Int,
  pages : @catalog.RecordPageLimits,
  values : @catalog.RecordValueLimits,
  limits : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  guard record_update_target_construction_inventory(
      mapping, body_bytes, pages, values, limits,
    )
    is Some(inventory) else {
    return None
  }
  update_construction_capacity(inventory)
}

///|
pub fn record_update_finalization_construction_capacity(
  mapping : RecordUpdateMapping,
  limits : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  guard record_update_finalization_construction_inventory(mapping, limits)
    is Some(inventory) else {
    return None
  }
  update_construction_capacity(inventory)
}

///|
/// One native acknowledgement and correlated applied outcome. Only exact
/// id/revision Strings, response digest, original request references and the
/// outcome document survive. Malformed wide objects keep full parser/closed
/// object refusal workspace; they never supply a successful outcome.
pub fn record_update_response_construction_inventory(
  mapping : RecordUpdateMapping,
  body_bytes : Int,
  limits : @catalog.RecordMutationLimits,
) -> RecordUpdateConstructionInventory? {
  if !record_update_mapping_is_original(mapping) ||
    body_bytes < 0 ||
    !record_target_before_limits_valid(limits) ||
    limits.max_records != 1 ||
    body_bytes > limits.max_output_bytes {
    return None
  }
  let b = Int::max(1, body_bytes)
  let nodes = Int::min(b, limits.max_output_nodes)
  let depth = Int::min(nodes, limits.max_output_depth)
  let outcome_bytes = Int64::min(
    limits.max_output_bytes.to_int64(),
    6L * Int::min(b, limits.max_identity_bytes).to_int64() + 128L,
  ).to_int()
  guard record_read_decoded_construction(b, nodes, depth, false) is Some(parser) &&
    @decode.closed_object_field_construction_extent(Some(nodes), 2, 0L)
    is Some(closed) &&
    @decode.issue_construction_extent(depth) is Some(issue) &&
    @shape.scale_collection_construction_extent(
      @decode.indexed_child_construction_extent(),
      6L,
    )
    is Some(children) &&
    @shape.collection_construction_extent({
      // Root and row closed views, exact scalar/identity comparison Results,
      // one-record acknowledgement, SHA/output wrappers and DATA predicates.
      records: 48L,
      record_references: 80L,
      record_words: 48L,
      reference_arrays: 12L,
      reference_items: 12L + 4L * mapping.before_fields.length().to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) &&
    record_read_writer_units(
      outcome_bytes,
      limits.max_output_nodes,
      limits.max_output_depth,
    )
    is Some(writer) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) &&
    @execution.compose_preparation_representation([
      parser,
      writer,
      record_read_collection_units(closed),
      record_read_collection_units(closed),
      record_read_collection_units(children),
      record_read_collection_units(issue),
      record_read_collection_units(controls),
      {
        record_headers: hash.record_headers,
        reference_slots: hash.reference_slots,
        scalar_words: hash.scalar_words,
        owned_utf16_units: hash.owned_utf16_units,
        owned_wire_bytes: hash.owned_wire_bytes,
      },
    ])
    is Some(workspace) else {
    return None
  }
  Some({
    retained: {
      record_headers: 16L,
      reference_slots: 24L,
      scalar_words: 16L,
      owned_utf16_units: b.to_int64() + outcome_bytes.to_int64() + 64L,
      owned_wire_bytes: 0L,
    },
    workspace,
  })
}

///|
pub fn record_update_response_construction_capacity(
  mapping : RecordUpdateMapping,
  body_bytes : Int,
  limits : @catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  guard record_update_response_construction_inventory(
      mapping, body_bytes, limits,
    )
    is Some(inventory) else {
    return None
  }
  update_construction_capacity(inventory)
}
