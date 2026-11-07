///|
fn managed_record_capacity(
  units : @execution.PreparationRepresentationUnits,
) -> @execution.ExecutionCapacity? {
  @execution.preparation_execution_capacity({
    retained: units,
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
/// Native adoption and one request producer only. Every original declared
/// column bounds the selected input; no caller array can narrow this quote.
/// Catalog/declaration/contracts/text backing stays with its original owner.
/// This does not fund Form/page decoding, a RowRun, JS or credential binding.
pub fn managed_record_construction_capacity(
  original : RecordDeclaration,
  pages : @catalog.RecordPageLimits,
  values : @catalog.RecordValueLimits,
  pairs : Int,
  per_page : Int,
  max_request_bytes : Int,
) -> @execution.ExecutionCapacity? {
  if pages.max_bytes <= 0 ||
    pages.max_nodes <= 0 ||
    pages.max_depth <= 0 ||
    pages.max_rows <= 0 ||
    pages.max_columns <= 0 ||
    pages.max_cells <= 0 ||
    pages.max_table_rows <= 0 ||
    values.max_columns <= 0 ||
    values.max_name_bytes <= 0 ||
    values.max_nodes <= 0 ||
    values.max_depth <= 0 ||
    values.max_text_bytes <= 0 ||
    pairs <= 0 ||
    per_page <= 0 ||
    per_page > 500 ||
    per_page > pages.max_rows ||
    max_request_bytes <= 0 {
    return None
  }
  let names = original.names.length().to_int64()
  let fields = names + 1L
  // The native request refuses more than 998 names before opening its writer;
  // adoption may still retain the complete original declared column vector.
  let request_names = Int64::min(names, 998L)
  let mut name_units = 0L
  for name in original.names {
    if name_units > 9223372036854775807L - name.length().to_int64() {
      return None
    }
    name_units += name.length().to_int64()
  }
  // Every retained cursor aliases original page text. Its request copies are
  // bounded by both the actual page ceiling and the request producer's guard.
  let cursor = Int::min(pages.max_bytes, max_request_bytes).to_int64()
  let app = original.catalog.app_id.length().to_int64()
  if name_units > (9223372036854775807L - 128L - 3L * names) / 6L - app - cursor {
    return None
  }
  // JSON escaping uses at most six units per input unit. Fixed punctuation,
  // physical id/revision names and the constant query suffix fit in 128 units.
  let request_bound = 128L + 3L * names + 6L * (name_units + app + cursor)
  let request = Int64::min(max_request_bytes.to_int64(), request_bound).to_int()
  guard record_read_writer_units(request, (request_names + 12L).to_int(), 3)
    is Some(writer) &&
    @shape.collection_construction_extent({
      // Read(1H10R6W), selection(1H1R1W), adoption/result/refusal
      // carriers, filter closure, per-column contract Some, and seven String
      // headers for perPage/prefix/query concatenation and refusal carriers.
      records: 17L + fields,
      record_references: 18L + fields,
      record_words: 14L + fields,
      // Acquisition columns, retained contracts, filtered native names and
      // one exported columns copy. All names and contracts remain borrowed.
      reference_arrays: 4L,
      reference_items: 4L * fields,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(frame) &&
    @execution.compose_preparation_representation([
      record_read_collection_units(frame),
      writer,
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        // The two prefix and two query concatenation outputs coexist;
        // perPage has at most three digits. No cursor String is cloned on save.
        owned_utf16_units: 4L * cursor + 128L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(units) else {
    return None
  }
  managed_record_capacity(units)
}

///|
fn managed_record_form_inventory(
  original : RecordDeclaration,
  body_bytes : Int,
  limits : @catalog.FormFieldLimits,
) -> @execution.PreparationRepresentationUnits? {
  if body_bytes < 0 ||
    limits.max_bytes <= 0 ||
    body_bytes > limits.max_bytes ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_fields <= 0 ||
    limits.max_name_units <= 0 {
    return None
  }
  let b = Int::max(1, body_bytes)
  let nodes = Int::min(b, limits.max_nodes)
  let depth = Int::min(nodes, limits.max_depth)
  // The metadata inventory's error path also uses this actual-body bound;
  // an unused configured depth cannot manufacture an enormous parser tree.
  let bounded = { ..limits, max_depth: depth, }
  let fields = Int::min(nodes, limits.max_fields).to_int64()
  let observed_paths = fields * depth.to_int64() + fields
  guard @catalog.form_construction_geometry(original.catalog) is Some(g) &&
    record_read_form_inventory(b, bounded) is Some(form) &&
    record_read_decoded_construction(b, nodes, depth, false) is Some(parsed) &&
    g.path_slots <= 9223372036854775807L - observed_paths - g.fields.to_int64() &&
    @shape.collection_construction_extent({
      // Original paths are copied even when the incoming Form has no fields.
      // Incoming paths are copied too, in addition to metadata-owned paths.
      // Retained observation Some, correspondence tuple/Options and result.
      // Geometry record/Some add2H1R4W before the path producer.
      records: 6L + 3L * g.fields.to_int64(),
      record_references: 5L + 4L * g.fields.to_int64(),
      record_words: 8L + 2L * g.fields.to_int64(),
      reference_arrays: 2L + g.fields.to_int64() + fields,
      reference_items: g.fields.to_int64() + g.path_slots + observed_paths,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(original_paths) else {
    return None
  }
  @execution.compose_preparation_representation([
    parsed,
    record_read_collection_units(form.representation),
    record_read_collection_units(original_paths),
    {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: form.owned_utf16_units,
      owned_wire_bytes: form.owned_wire_bytes,
    },
  ])
}

///|
/// Incremental demand before decoding these actual response bytes. The caller
/// must keep the base and previous Form/page quantities live through this
/// replacement (including drift refusal). Bytes are the existing charged
/// response borrow; this quote neither copies nor charges their wire storage.
pub fn managed_record_form_construction_inventory(
  read : ManagedRecordRead,
  body_bytes : Int,
  limits : @catalog.FormFieldLimits,
) -> @execution.PreparationRepresentationUnits? {
  if read.retired || read.failed || !read.needs_form {
    return None
  }
  managed_record_form_inventory(read.original, body_bytes, limits)
}

///|
fn managed_record_page_inventory(
  original : RecordDeclaration,
  names : Array[String],
  columns : Int,
  body_bytes : Int,
  pages : @catalog.RecordPageLimits,
  values : @catalog.RecordValueLimits,
  pairs : Int,
) -> @execution.PreparationRepresentationUnits? {
  if body_bytes < 0 ||
    pages.max_bytes <= 0 ||
    body_bytes > pages.max_bytes ||
    pages.max_nodes <= 0 ||
    pages.max_depth <= 0 ||
    pages.max_rows <= 0 ||
    pages.max_columns <= 0 ||
    pages.max_cells <= 0 ||
    pages.max_table_rows <= 0 ||
    values.max_columns <= 0 ||
    values.max_name_bytes <= 0 ||
    values.max_nodes <= 0 ||
    values.max_depth <= 0 ||
    values.max_text_bytes <= 0 ||
    pairs <= 0 ||
    columns < 0 {
    return None
  }
  let b = Int::max(1, body_bytes)
  let raw_nodes = Int::min(b, pages.max_nodes)
  let raw = raw_nodes.to_int64()
  let depth = Int::min(raw_nodes, pages.max_depth)
  let nodes = Int::min(raw_nodes, values.max_nodes)
  let n = nodes.to_int64()
  let rows = Int::min(raw_nodes, pages.max_rows).to_int64()
  let cells = Int::min(raw_nodes, pages.max_cells).to_int64()
  let selected = names.length().to_int64()
  guard @catalog.selected_form_construction_geometry(original.catalog, names)
    is Some(g) else {
    return None
  }
  let fields = g.fields.to_int64()
  let tables = g.tables.to_int64()
  let entries = fields + tables + 1L
  let contracts = 3L * fields + 1L
  // Original expected contract trees are disjoint by top-level selection.
  // Every field creates its initial Text contract; a SUBTABLE additionally
  // creates Object+Array, including the synthetic id and final root object
  // validation in record_contracts. No schema wire or declaration is rebuilt.
  if entries > 2147483647L || g.code_units > 9223372036854775807L / 128L {
    return None
  }
  guard record_read_decoded_construction(b, raw_nodes, depth, false)
    is Some(parsed) &&
    @contract.object_retained_construction_extent(
      entries.to_int(),
      g.tables + 1,
    )
    is Some(objects) &&
    @contract.object_construction_inventory(entries.to_int(), g.max_code_units)
    is Some(object_work) &&
    @shape.collection_construction_extent({
      // Same selected-field contract constructor family as read_construction:
      // primitive/Text/TextLimits, nullable alternative, array/Option/Result,
      // recursive lookup and entry tuples. Additional fixed object scratch is
      // per SUBTABLE; field-dependent sorting is already summed by entries.
      records: 16L + 16L * contracts + 20L * tables,
      record_references: 24L + 24L * contracts + 16L * tables,
      record_words: 16L + 16L * contracts + 14L * tables,
      reference_arrays: 8L + 3L * fields,
      reference_items: 8L + 6L * fields + selected,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L + fields,
      map_entries: 2L * fields,
    })
    is Some(expected) &&
    @shape.collection_construction_extent({
      // Native page/record/field/table carriers plus Result/Option/length and
      // scalar-validation controls. All input cursor/text backing is borrowed.
      // An original object is opened at most four times across projection and
      // normalization; total map entries therefore follow raw nodes, not N*N.
      records: 24L + 24L * raw + 6L * selected,
      record_references: 32L + 32L * raw + 8L * selected,
      record_words: 24L + 24L * raw + 6L * selected,
      reference_arrays: 6L + 4L * raw,
      // Empty tables still allocate original child-definition vectors. Their
      // width is genuine selected metadata, independent of response row count.
      reference_items: 6L +
      8L * raw +
      3L * selected +
      cells * g.max_children.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 3L + 5L * raw,
      map_entries: 5L * raw + selected,
    })
    is Some(projection) &&
    @shape.scale_collection_construction_extent(
      @decode.indexed_child_construction_extent(),
      16L * raw + 2L * selected + 8L,
    )
    is Some(children) &&
    @decode.issue_construction_extent(depth) is Some(issue) &&
    @shape.scale_collection_construction_extent(issue, raw + 1L) is Some(issues) else {
    return None
  }
  // Every converted node corresponds to a distinct raw node. SUBTABLE row
  // Object/id replace existing row Object/id, dropping provider wrappers;
  // principal/code collapses an Object, and Timestamp changes text only.
  // The same global value budget bounds successful cells plus a failed prefix.
  // Independent category upper bounds below are algebra, NOT an invented
  // observed SubtreeConstructionGeometry passed to a shared admission port.
  guard @decode.admission_construction_inventory(
      nodes, nodes, nodes, nodes, nodes,
    )
    is Some(index) &&
    @shape.collection_construction_extent({
      // Source Node/Value/Field plus native budget clones and two timestamp
      // strings+substring view; source arrays own their original edge slots.
      records: 7L * n,
      record_references: 6L * n,
      record_words: 5L * n,
      reference_arrays: n,
      reference_items: n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(normalized) &&
    @shape.collection_construction_extent({
      // Non-reference typed Value/FrozenArray/field-pair <=3N H4N R2N W.
      // Existing admission continuation <=2N+2 frames, cursor N, array builder
      // N and object/builder/Some <=3N; this co-counts category alternatives.
      records: 10L * n + 2L,
      record_references: 20L * n + 6L,
      record_words: 18L * n + 8L,
      reference_arrays: n + 1L,
      reference_items: 3L * n + 1L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: n,
      map_entries: n,
    })
    is Some(typed) &&
    @shape.collection_construction_extent({
      // Per-cell decoder fixed controls (18/47/30) and typed entry/result,
      // CheckedValue, native budget and date/timestamp validation controls.
      // Ancestry sums over the disjoint forest to <=N; the index above uses N
      // for that aggregate, not configured depth multiplied by every cell.
      records: 18L * n + 14L * n + 20L * n,
      record_references: 47L * n + 17L * n + 8L * n,
      record_words: 30L * n + 28L * n + 34L * n,
      reference_arrays: 1L + rows,
      reference_items: rows + n,
      scalar_arrays: 3L * n,
      scalar_items: 28L * n,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) else {
    return None
  }
  // Equality schedules original expected children only after checking its
  // remaining-pair budget. Names continuations scan at most64 units per poll;
  // the original selected code lengths, not the response, bound those polls.
  let comparisons = contracts +
    fields +
    g.code_units / 64L +
    columns.to_int64() +
    1L
  guard @shape.collection_construction_extent({
      records: 8L * comparisons,
      record_references: 12L * comparisons,
      record_words: 12L * comparisons,
      reference_arrays: columns.to_int64() + 1L,
      reference_items: 2L * contracts + columns.to_int64(),
      scalar_arrays: 1L,
      scalar_items: columns.to_int64(),
      maps: 1L,
      map_entries: columns.to_int64(),
    })
    is Some(equality) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) else {
    return None
  }
  let utf8 = @scalar.utf8_length_admission_construction_units()
  @execution.compose_preparation_representation([
    parsed,
    record_read_collection_units(objects),
    record_read_collection_units(object_work.scratch),
    record_read_collection_units(expected),
    record_read_collection_units(projection),
    record_read_collection_units(children),
    record_read_collection_units(issues),
    record_read_collection_units(normalized),
    record_read_collection_units(typed),
    record_read_collection_units(controls),
    record_read_collection_units(equality),
    {
      record_headers: index.indexed.record_headers +
      index.keys.record_headers +
      index.ancestry.record_headers +
      index.controls.record_headers,
      reference_slots: index.indexed.reference_slots +
      index.keys.reference_slots +
      index.ancestry.reference_slots +
      index.controls.reference_slots,
      scalar_words: index.indexed.scalar_words +
      index.keys.scalar_words +
      index.ancestry.scalar_words +
      index.controls.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    // Reuse the original object-name work for typed key normalization too;
    // its extra sort/map component safely co-counts the sequential alternative.
    record_read_collection_units(object_work.scratch),
    {
      record_headers: hash.record_headers + utf8.0 + 2L,
      reference_slots: hash.reference_slots + utf8.1 + 1L,
      scalar_words: hash.scalar_words + utf8.2 + 6L,
      // The 19-unit timestamp prefix and 24-unit normalized result coexist.
      owned_utf16_units: 43L * n +
      2L * object_work.scratch_utf16_units +
      hash.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes,
    },
  ])
}

///|
/// Incremental native page demand under this SAME reader's selected originals.
/// Prior Form/page backing and the charged response remain live at the caller.
/// No new parser, fake observed geometry, contract or acquisition is run here.
pub fn managed_record_page_construction_inventory(
  read : ManagedRecordRead,
  body_bytes : Int,
) -> @execution.PreparationRepresentationUnits? {
  if read.retired || read.failed || read.needs_form || read.terminal_page {
    return None
  }
  managed_record_page_inventory(
    read.original,
    read.names,
    read.columns.length(),
    body_bytes,
    read.page_limits,
    read.value_limits,
    read.max_contract_pairs,
  )
}

///|
/// Add this actual native response producer to the SAME cumulative typed
/// capacity. Previous parser/native peaks conservatively remain covered;
/// this neither mutates a reservation nor credits retired storage. The generic
/// owner already funds the charged wire prefix, so it is not added again here.
pub fn managed_record_response_construction_capacity(
  read : ManagedRecordRead,
  previous : @execution.ExecutionCapacity,
  body_bytes : Int,
  is_form : Bool,
  form_limits : @catalog.FormFieldLimits,
) -> @execution.ExecutionCapacity? {
  let units = if is_form {
    managed_record_form_construction_inventory(read, body_bytes, form_limits)
  } else {
    managed_record_page_construction_inventory(read, body_bytes)
  }
  guard units is Some(units) && managed_record_capacity(units) is Some(stage) else {
    return None
  }
  @execution.add_execution_capacity(previous, stage)
}

///|
/// Text extent of the installed target and its current-Form subject, without
/// serializing or hashing either. installed-kintone-source.mjs target() owns
/// version/apiOrigin/appId/optional guestSpaceId/resource/metadataCid/fields;
/// current Form authorization wraps that target in {binding,operation}.
/// The complete fixed skeleton with the longer kintone:records:read operation
/// and an empty guestSpaceId is 182 UTF16 units; 256 also covers punctuation
/// alternatives. CID text is 71 ASCII units. Names come from this SAME original
/// declaration, plus the physical $id, never a caller-provided field count.
pub fn managed_record_identity_units(
  original : RecordDeclaration,
  origin : String,
  resource : String,
  guest_space : String,
) -> Int64? {
  let fixed = 256L + 3L * (original.names.length().to_int64() + 1L) + 71L
  let maximum = (9223372036854775807L - fixed) / 6L
  // Empty guest space denotes absence; including its fixed member syntax in
  // the skeleton is conservative and does not construct an optional target.
  let mut units = 3L +
    original.catalog.app_id.length().to_int64() +
    origin.length().to_int64() +
    resource.length().to_int64() +
    guest_space.length().to_int64()
  if units > maximum {
    return None
  }
  for name in original.names {
    let length = name.length().to_int64()
    if units > maximum - length {
      return None
    }
    units += length
  }
  // A JSON escaped UTF16 unit occupies at most six output units. This is
  // representation DATA only, not target identity, authority or permission.
  Some(fixed + 6L * units)
}

///|
/// Exact original declared width, including the physical id. declare_records
/// has already constructed this bounded schema; no schema/vector is copied.
pub fn managed_record_column_count(original : RecordDeclaration) -> Int {
  original.names.length() + 1
}
