///|
// Existing native parser/index families. The schema and outgoing validation
// and all actual byte inputs stay with this preserving codec owner. The
// generic normalizing-input addition is deliberately NOT composed again.
// All alternatives coexist conservatively; this issues no capacity.
fn sheets_decoded_construction(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  guard @decode.preserving_json_admission_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(original) else {
    return None
  }
  Some({
    record_headers: original.record_headers,
    reference_slots: original.reference_slots,
    scalar_words: original.scalar_words,
    owned_utf16_units: original.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
fn sheets_collection_units(
  original : @shape.CollectionConstructionExtent,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: original.record_headers,
    reference_slots: original.reference_slots,
    scalar_words: original.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
fn sheets_writer_units(
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
fn sheets_constructor_capacity(
  parts : Array[@execution.PreparationRepresentationUnits],
) -> @execution.ExecutionCapacity? {
  guard @execution.compose_preparation_representation(parts) is Some(retained) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained,
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
// columns_of owns the parsed schema, all element Cursors, Column/name arrays,
// and each three-field closed view. The immutable schema has already passed
// the SAME original configuration codec; its actual byte/count metadata is
// supplied by the installer, never a user capacity or a new schema verdict.
fn sheets_column_construction(
  schema_bytes : Int,
  columns : Int,
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  let nodes = 1 + 4 * columns
  let cursor = @decode.cursor_construction_extent()
  let child = @decode.indexed_child_construction_extent()
  guard sheets_decoded_construction(schema_bytes, nodes, depth) is Some(parsed) &&
    @shape.collection_construction_extent({
      records: columns.to_int64() *
      (cursor.record_headers + 1L + 3L * child.record_headers),
      record_references: columns.to_int64() *
      (cursor.reference_slots + 1L + 3L * child.reference_slots),
      record_words: columns.to_int64() *
      (cursor.scalar_words + 2L + 3L * child.scalar_words),
      reference_arrays: 3L,
      reference_items: 3L * columns.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(collections) &&
    @decode.closed_object_field_construction_extent(Some(3), 3, 1L)
    is Some(view) &&
    @shape.scale_collection_construction_extent(view, columns.to_int64())
    is Some(views) else {
    return None
  }
  @execution.compose_preparation_representation([
    parsed,
    sheets_collection_units(collections),
    sheets_collection_units(views),
    // columns_of encodes the original JSON String before checking byte limits.
    {
      record_headers: 1L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: schema_bytes.to_int64(),
    },
  ])
}

///|
// check_target's full supplied sheets Array, Cursor wrappers and IDs survive
// beside its input tree. Every open_object Map borrows original fields. The
// TOTAL nodes bound covers all entries, including invalid response width;
// root/sheet/properties/grid are at most four live maps. Earlier loop maps do
// not escape. No permitted-field count replaces arbitrary input fields. Lookup
// and one failure path are sequential fixed controls, not N copied paths.
fn sheets_target_projection_construction(
  nodes : Int,
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  let cursor = @decode.cursor_construction_extent()
  let child = @decode.indexed_child_construction_extent()
  let n = nodes.to_int64()
  guard @shape.collection_construction_extent({
      records: n * cursor.record_headers,
      record_references: n * cursor.reference_slots,
      record_words: n * cursor.scalar_words,
      reference_arrays: 1L,
      reference_items: n,
      scalar_arrays: 1L,
      scalar_items: n,
      maps: 4L,
      map_entries: n,
    })
    is Some(collections) &&
    @decode.issue_construction_extent(depth + 1) is Some(issue) else {
    return None
  }
  @execution.compose_preparation_representation([
    sheets_collection_units(collections),
    sheets_collection_units(issue),
    // At most root/sheets/sheet/properties/grid and their scalar lookups are
    // live in this synchronous projection. Count all sixteen original child
    // carriers together instead of treating callback retirement as release.
    {
      record_headers: 16L * child.record_headers,
      reference_slots: 16L * child.reference_slots,
      scalar_words: 16L * child.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
/// Native append constructor DATA for the existing standard four-role owner.
/// Actual selected schema geometry and existing implementation/input limits
/// arrive unchanged from the installer. This neither constructs a business
/// request nor grants capacity, I/O, retries, permission or cleanup.
/// The return stays opaque through JS into the SAME typed Core composer.
/// Order: write request, absent GET body, write response, metadata response.
#export_name("sheetsAppendConstructionProfile")
pub fn sheets_append_construction_profile(
  schema_bytes : Int,
  columns : Int,
  input_wire_bytes : Int,
  request_bytes : Int,
  response_bytes : Int,
  nodes : Int,
  depth : Int,
) -> Array[
  (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
]? {
  if schema_bytes < 1 ||
    columns < 1 ||
    columns > 64 ||
    input_wire_bytes < 1 ||
    request_bytes < 1 ||
    response_bytes < 1 ||
    nodes < 1 ||
    depth < 1 ||
    depth == 2147483647 {
    return None
  }
  let c = columns.to_int64()
  // SAME document builder as append_request, with no cells. The longest
  // existing cell-key branch and fixed Int32 sheet ID bound the fixed text;
  // values/Unicode are original input borrows, never a synthetic accepted row.
  let fixed = @catalog.append_request_document(2147483647, [])
    .stringify()
    .length()
  let cell = @catalog.literal_cell_document(Text, "x".to_json())
    .unwrap()
    .stringify()
    .length()
  let fixed_units = fixed.to_int64() + c * (cell.to_int64() + 26L)
  // Six units per original UTF16 unit cover an inner escape; the outer
  // String adds only one more slash to a control escape (7), not 6*6.
  // The extra26 per scalar covers a comma and full native number spelling.
  let inner = fixed_units + 6L * input_wire_bytes.to_int64()
  let outer = "{\"body\":\"\"}".length().to_int64() +
    2L * fixed_units +
    7L * input_wire_bytes.to_int64()
  if 3L * outer > 2147483647L || 3L * inner > 2147483647L {
    return None
  }
  let body_nodes = 9 + 3 * columns
  let child = @decode.indexed_child_construction_extent()
  // A parsed Object field needs at least five original wire bytes including
  // its separator (5F+1 total). Use supplied-input syntax, never allowed C,
  // to bound even an invalid root's complete closed_object map.
  // Outgoing validation instead consumes the SAME closed literal forest:
  // exactly9+3C nodes, depth<=9, and only after its byte check succeeded.
  guard sheets_column_construction(schema_bytes, columns, depth) is Some(schema) &&
    @decode.closed_object_field_construction_extent(
      Some(Int::min(nodes - 1, (request_bytes - 1) / 5)),
      columns,
      0L,
    )
    is Some(row_view) &&
    @shape.collection_construction_extent({
      records: c * (1L + child.record_headers),
      record_references: c * (1L + child.reference_slots),
      record_words: c * (1L + child.scalar_words),
      reference_arrays: 2L,
      reference_items: 2L * c,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(values) &&
    @source.json_tree_retained_construction_extent(
      body_nodes,
      6 + 2 * columns,
      4 + 2 * columns,
      3,
      0L,
    )
    is Some(forest) &&
    sheets_writer_units((3L * inner).to_int(), body_nodes, 9)
    is Some(inner_writer) &&
    sheets_writer_units((3L * outer).to_int(), 4, 2) is Some(outer_writer) &&
    sheets_decoded_construction(
      Int::min(request_bytes, (3L * inner).to_int()),
      body_nodes,
      9,
    )
    is Some(outgoing) &&
    sheets_decoded_construction(request_bytes, nodes, depth) is Some(row_input) &&
    sheets_decoded_construction(response_bytes, nodes, depth)
    is Some(response_input) &&
    sheets_constructor_capacity([
      schema,
      sheets_collection_units(row_view),
      sheets_collection_units(values),
      {
        record_headers: forest.record_headers,
        reference_slots: forest.reference_slots,
        scalar_words: forest.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      inner_writer,
      outer_writer,
      outgoing,
      row_input,
      // Original row encode and BOTH body encodes precede complete outgoing
      // admission. A body exceeding the later HTTP quota is still funded.
      {
        record_headers: 3L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 3L * input_wire_bytes.to_int64() + 6L * inner,
      },
    ])
    is Some(write) &&
    sheets_target_projection_construction(nodes, depth) is Some(target) else {
    return None
  }
  // The actual response exports have no unbounded provider text. This wider
  // ORIGINAL issue projection also covers every metadata-refusal branch.
  let refusal = (
      {
        "refused": issue_json(MissingEffectiveValue(row=2147483647, column="")),
      } : Json)
    .stringify()
    .length()
  let response_export : @source.ParseLimits = {
    max_input_bytes: refusal,
    max_nodes: 5,
    max_depth: 2,
  }
  guard sheets_writer_units(refusal, 5, 2) is Some(reply_writer) &&
    // Append shares the same private fresh-Source acknowledgement classifier.
    // Metadata still uses its original full indexed projection below.
    sheets_range_response_capacity(response_bytes, nodes, depth) is Some(reply) &&
    sheets_constructor_capacity([schema, response_input, target, reply_writer])
    is Some(metadata) else {
    return None
  }
  // Native quantities above already own the exact non-normalizing byte
  // parsers. None requests no ADDITIONAL generic normalizing input inventory;
  // it does not assert that these native functions have no physical input.
  Some([
    (
      write,
      None,
      Some({
        max_input_bytes: (3L * outer).to_int(),
        max_nodes: 5,
        max_depth: 2,
      }),
    ),
    (@execution.execution_capacity(0L, 0L).unwrap(), None, None),
    (reply, None, Some(response_export)),
    (metadata, None, Some(response_export)),
  ])
}

///|
/// Additional standard Source constructor DATA only. The existing reader
/// already owns raw response parsing, provider rows and output-row workspace.
/// This adds BOTH schema decoders, fixed grid request/output builders, Host
/// literal decode and body encoding before the existing HTTP size refusal.
/// It neither validates a range nor grants Source or Credential authority.
#export_name("sheetsGridReadConstructionCapacity")
pub fn sheets_grid_read_construction_capacity(
  schema_bytes : Int,
  columns : Int,
  sheet_id : Int,
  start_row : Int,
  end_row : Int,
  start_column : Int,
  end_column : Int,
) -> @execution.ExecutionCapacity? {
  if schema_bytes < 1 || columns < 1 || columns > 64 {
    return None
  }
  let body = @catalog.read_request_document({
    sheet_id,
    start_row,
    end_row,
    start_column,
    end_column,
  }).stringify()
  let output = ({ "body": body.to_json() } : Json).stringify()
  let b = body.length()
  let refused = ({ "refused": issue_json(BudgetExceeded) } : Json).stringify()
  let o = Int::max(output.length(), refused.length())
  guard sheets_column_construction(schema_bytes, columns, 2) is Some(schema) &&
    sheets_decoded_construction(b, 10, 4) is Some(validation) &&
    sheets_writer_units(b, 10, 4) is Some(body_writer) &&
    sheets_writer_units(o, 5, 2) is Some(output_writer) &&
    @source.json_literal_construction_extent(o, 5, 2) is Some(host) else {
    return None
  }
  let envelope : @execution.PreparationRepresentationUnits = {
    record_headers: host.record_headers + 2L,
    reference_slots: host.reference_slots,
    scalar_words: host.scalar_words,
    owned_utf16_units: host.owned_utf16_units + schema_bytes.to_int64(),
    owned_wire_bytes: 0L,
  }
  guard sheets_constructor_capacity([
      schema,
      schema,
      validation,
      body_writer,
      output_writer,
      { ..envelope, owned_wire_bytes: 2L * b.to_int64(), },
    ])
    is Some(peak) &&
    sheets_constructor_capacity([
      {
        ..envelope,
        // The page reader captures its schema wire and retains the request
        // body/projection. Native columns/parser/Writer locals do not escape.
        owned_utf16_units: envelope.owned_utf16_units +
        b.to_int64() +
        o.to_int64(),
      },
    ])
    is Some(output) else {
    return None
  }
  @execution.execution_capacity(
    @execution.execution_capacity_retained_bytes(output),
    @execution.execution_capacity_execution_bytes(peak),
  )
}

///|
/// Original range/clear declaration constructor only. The fixed document
/// shapes come from their SAME Catalog builders; native Source/index, JSON
/// trees, NFC identity copies, writers, escaped outputs and Host parser overlap
/// are composed here before those original builders run. No Command, Catalog,
/// permission, current observation or reservation is issued by this quote.
#export_name("sheetsRangeDeclarationConstructionCapacity")
pub fn sheets_range_declaration_construction_capacity(
  schema_bytes : Int,
  columns : Int,
  range_bytes : Int,
  connector_bytes : Int,
  declared_bytes : Int,
) -> @execution.ExecutionCapacity? {
  if range_bytes < 1 || declared_bytes < 1 {
    return None
  }
  guard @catalog.range_declaration_construction_bounds(
      schema_bytes, columns, connector_bytes,
    )
    is Some(command) else {
    return None
  }
  let d = declared_bytes.to_int64()
  let c = command.bundle_bytes.to_int64()
  // The old declaration embeds its Catalog/contracts as strings. Their
  // aggregate decoded input is <=the original declared wire (including keys
  // and escaping). Parse that whole inner forest conservatively as well.
  // The final Catalog and the declared contract list both retain the added
  // contracts. Two complete input forests cover that duplication. New
  // Catalog/contract/Command strings add one JSON quoting layer: <=7 units
  // per original UTF16 unit, including escaped control characters.
  let result = 2L * 7L * (d + c) +
    "{\"command_bodies\":[\"\"]}".length().to_int64()
  let native_nodes = d + command.bundle_nodes.to_int64()
  if result > 2147483647L ||
    native_nodes > 2147483647L ||
    8L * (d + c) > 2147483647L {
    return None
  }
  let n = native_nodes.to_int()
  // The native body parser itself rejects depths beyond32. An outer declared
  // view adds no more than its own bounded envelope beside the inner forest.
  let depth = 32
  guard sheets_column_construction(schema_bytes, columns, depth) is Some(schema) &&
    sheets_decoded_construction(range_bytes, 6, 1) is Some(range_input) &&
    sheets_decoded_construction(declared_bytes, declared_bytes, depth)
    is Some(declared) &&
    sheets_decoded_construction(
      command.bundle_bytes,
      command.bundle_nodes,
      command.bundle_depth,
    )
    is Some(bundle) &&
    // range_configuration_value normalizes the ORIGINAL decoded key/value
    // strings, bounded by the two input wires. Returned NFC text is retained
    // separately below; it is not another expanded normalization input.
    @canonical.nfc_lf_construction_scratch_extent((d + c).to_int())
    is Some(normalization) &&
    sheets_writer_units(result.to_int(), n, depth) is Some(writer) &&
    @source.json_literal_construction_extent(result.to_int(), n, depth)
    is Some(host) &&
    @shape.collection_construction_extent({
      records: native_nodes,
      record_references: 2L * native_nodes,
      record_words: 2L * native_nodes,
      reference_arrays: native_nodes,
      reference_items: native_nodes,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: native_nodes,
      map_entries: native_nodes,
    })
    is Some(native_json) else {
    return None
  }
  guard sheets_constructor_capacity([
      schema,
      range_input,
      // Outer declaration, embedded Catalog/contracts and parsed native bundle.
      declared,
      declared,
      bundle,
      sheets_collection_units(native_json),
      // Original Json, its NFC identity Json and canonical-value projection
      // overlap. One normalization cursor is enough; retain cumulative output
      // text separately, never normalize schema/Command meaning here.
      sheets_collection_units(native_json),
      sheets_collection_units(native_json),
      {
        record_headers: normalization.record_headers,
        reference_slots: normalization.reference_slots,
        scalar_words: normalization.scalar_words,
        owned_utf16_units: normalization.owned_utf16_units + 8L * (d + c),
        owned_wire_bytes: 0L,
      },
      // The six output families stay co-held, but these closed synchronous
      // calls do not nest or return a Writer/cursor. Only one original writer
      // workspace is live. Its quantity includes the current output; the other
      // five complete output families retain their own String backing below.
      // The per-contract loop contributes multiple Strings whose aggregate is
      // bounded by the SAME complete declared wire, not one whole wire per
      // contract. Keep their wrappers/references beside the fixed outputs.
      writer,
      {
        record_headers: native_nodes + 6L,
        reference_slots: native_nodes + 6L,
        scalar_words: 0L,
        owned_utf16_units: 5L * result,
        owned_wire_bytes: 0L,
      },
      {
        record_headers: host.record_headers,
        reference_slots: host.reference_slots,
        scalar_words: host.scalar_words,
        owned_utf16_units: host.owned_utf16_units + result,
        owned_wire_bytes: d +
        c +
        schema_bytes.to_int64() +
        range_bytes.to_int64(),
      },
    ])
    is Some(peak) &&
    @execution.execution_capacity_inventory(
      [
        // Returned Host definition forest plus the final outer declaration.
        // Replacing catalog/CID Strings adds no node; two new contract
        // Strings and command_bodies key/Array/String add five. The shared
        // commands Array, projected record and prepared record add three.
        {
          unit: @execution.ValueNodeSlots,
          count: native_nodes + 8L,
          copies: 1,
        },
        // Final wire, its parsed declaration text, parsed definition text,
        // and the original captured columns/range wires remain co-held.
        {
          unit: @execution.DecodedTextBytes,
          count: 2L * result +
          c +
          schema_bytes.to_int64() +
          range_bytes.to_int64(),
          copies: 1,
        },
      ],
      [],
      @execution.RetainedAlongsideExecution,
    )
    is Some(output) else {
    return None
  }
  let retained = @execution.execution_capacity_retained_bytes(output)
  @execution.execution_capacity(
    retained,
    Int64::max(retained, @execution.execution_capacity_execution_bytes(peak)),
  )
}

///|
/// The original Source Reference constructor outlives individual Readers.
/// Its full native/Host peak is retained on the original Source initializer;
/// the per-Run Reader quote never supplies this installation lifetime.
#export_name("sheetsRangeReferenceConstructionCapacity")
pub fn sheets_range_reference_construction_capacity(
  origin_bytes : Int,
  spreadsheet_bytes : Int,
) -> @execution.ExecutionCapacity? {
  guard @catalog.range_reference_construction_bounds(
      origin_bytes, spreadsheet_bytes,
    )
    is Some(bounds) else {
    return None
  }
  let bytes = bounds.identity_bytes
  let nodes = bounds.identity_nodes
  let depth = bounds.identity_depth
  guard @canonical.nfc_lf_construction_extent(bytes) is Some(normalization) &&
    sheets_writer_units(bytes, nodes, depth) is Some(identity_writer) &&
    sheets_writer_units(bounds.reference_bytes, bounds.reference_nodes, 1)
    is Some(reference_writer) &&
    @source.json_literal_construction_extent(
      bounds.reference_bytes,
      bounds.reference_nodes,
      1,
    )
    is Some(host) &&
    @shape.collection_construction_extent({
      records: nodes.to_int64(),
      record_references: nodes.to_int64(),
      record_words: nodes.to_int64(),
      reference_arrays: nodes.to_int64(),
      reference_items: nodes.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: nodes.to_int64(),
      map_entries: nodes.to_int64(),
    })
    is Some(identity_json) else {
    return None
  }
  sheets_constructor_capacity([
    // Original identity Json, NFC copy and canonical-value projection coexist.
    sheets_collection_units(identity_json),
    sheets_collection_units(identity_json),
    sheets_collection_units(identity_json),
    {
      record_headers: normalization.record_headers,
      reference_slots: normalization.reference_slots,
      scalar_words: normalization.scalar_words,
      owned_utf16_units: normalization.owned_utf16_units + bytes.to_int64(),
      // Both original identity hash inputs, digest buffers and prefixed CIDs
      // coexist conservatively with the complete bounded identity spelling.
      owned_wire_bytes: 2L * bytes.to_int64() + 2L * 32L + 4L * 71L,
    },
    sheets_collection_units(identity_json),
    identity_writer,
    identity_writer,
    reference_writer,
    {
      record_headers: host.record_headers + 4L,
      reference_slots: host.reference_slots + bounds.reference_nodes.to_int64(),
      scalar_words: host.scalar_words,
      owned_utf16_units: host.owned_utf16_units +
      bounds.reference_bytes.to_int64() +
      bytes.to_int64() +
      4L * 71L,
      owned_wire_bytes: bounds.reference_bytes.to_int64() + bytes.to_int64(),
    },
  ])
}

///|
/// The installed range/clear Source supports BOTH the original grid rows and
/// the one-reference metadata read. Those native callbacks are alternatives in
/// one Reader, so take their per-dimension maximum, not two live full parses.
/// The common preserving Reader still supplies received Bytes, Source/index,
/// provider page/output and failed-response overlap at the unchanged bounds.
#export_name("sheetsRangeReadConstructionCapacity")
pub fn sheets_range_read_construction_capacity(
  schema_bytes : Int,
  columns : Int,
  sheet_id : Int,
  start_row : Int,
  end_row : Int,
  start_column : Int,
  end_column : Int,
  nodes : Int,
  depth : Int,
) -> @execution.ExecutionCapacity? {
  if nodes < 1 || depth < 1 || depth == 2147483647 {
    return None
  }
  let reply_bytes = ({ "refused": issue_json(BudgetExceeded) } : Json)
    .stringify()
    .length()
  guard sheets_grid_read_construction_capacity(
      schema_bytes, columns, sheet_id, start_row, end_row, start_column, end_column,
    )
    is Some(grid) &&
    sheets_column_construction(schema_bytes, columns, depth) is Some(schema) &&
    sheets_target_projection_construction(nodes, depth) is Some(target) &&
    sheets_writer_units(reply_bytes, 5, 2) is Some(writer) &&
    @source.json_literal_construction_extent(reply_bytes, 5, 2) is Some(host) else {
    return None
  }
  let envelope : @execution.PreparationRepresentationUnits = {
    record_headers: host.record_headers + 2L,
    reference_slots: host.reference_slots + 3L,
    scalar_words: host.scalar_words,
    owned_utf16_units: host.owned_utf16_units + schema_bytes.to_int64(),
    owned_wire_bytes: 0L,
  }
  guard sheets_constructor_capacity([
      schema,
      target,
      writer,
      { ..envelope, owned_wire_bytes: schema_bytes.to_int64(), },
    ])
    is Some(metadata) &&
    sheets_constructor_capacity([
      {
        // Metadata returns no parsed sheet/maps/ID vector or new ResourceRef.
        // The existing Source initializer already retains the original target.
        ..envelope,
        owned_utf16_units: envelope.owned_utf16_units + reply_bytes.to_int64(),
      },
    ])
    is Some(output) else {
    return None
  }
  @execution.execution_capacity(
    Int64::max(
      @execution.execution_capacity_retained_bytes(grid),
      @execution.execution_capacity_retained_bytes(output),
    ),
    Int64::max(
      @execution.execution_capacity_execution_bytes(grid),
      @execution.execution_capacity_execution_bytes(metadata),
    ),
  )
}
