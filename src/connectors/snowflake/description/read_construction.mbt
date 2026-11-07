///|
fn read_initialization_collection_units(
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
fn read_initialization_decoded_construction(
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
fn read_initialization_writer_units(
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
/// One actual SQL API response constructor, before response_root/project_rows.
/// Wrong headers are detected only AFTER row projection by TableDescription:
/// therefore VARIANT/OBJECT/ARRAY, numeric and temporal failure prefixes are
/// included, not merely the ten successful metadata scalar columns.
fn read_response_construction(
  body_bytes : Int,
  limits : @response.ResponseLimits,
) -> @execution.PreparationRepresentationUnits? {
  let b = Int::max(1, body_bytes)
  let n = Int::min(b, limits.max_nodes)
  let nn = n.to_int64()
  let c = Int::min(n, limits.max_columns).to_int64()
  let child = @decode.indexed_child_construction_extent()
  guard read_initialization_decoded_construction(b, n, limits.max_depth, false)
    is Some(parsed) &&
    // All embedded cell text is disjoint within the same original wire B.
    // Json literal/REAL parsers and scalar converted_cursor indices coexist
    // with the outer response. Shared cumulative cell budget bounds N.
    read_initialization_decoded_construction(b, n, limits.max_depth, false)
    is Some(literals) &&
    @shape.collection_construction_extent({
      // ResultSet/Partition, root/metadata views, Column/Contract/Options and
      // lookup/scalar Result families. Per column <=24H36R24W; row/cell
      // arrays/CheckedValue/Result/converted Node+Value+Span add12H18R16W.
      records: 24L +
      24L * c +
      12L * nn +
      child.record_headers * (12L * c + 4L * nn + 16L),
      record_references: 40L +
      36L * c +
      18L * nn +
      child.reference_slots * (12L * c + 4L * nn + 16L),
      record_words: 32L +
      24L * c +
      16L * nn +
      child.scalar_words * (12L * c + 4L * nn + 16L),
      reference_arrays: 4L + nn,
      reference_items: c + 3L * nn,
      scalar_arrays: 1L,
      scalar_items: nn,
      maps: 2L + c + nn,
      map_entries: 2L * nn,
    })
    is Some(response) &&
    @shape.collection_construction_extent({
      // JsonAdmission: Value/FrozenArray/field tuple3H4R2W per node;
      // Next/Append/Read frames + builder/Some/poll <=8H16R16W;
      // ObjectKeys/Names/Sort and pinned sort controls <=12H20R20W.
      // Runtime recheck/CheckedValue+outcome <=4H6R6W. These disjoint
      // families cover JSON and scalar alternatives, not a byte tariff.
      records: (3L + 8L + 12L + 4L) * nn + 16L,
      record_references: (4L + 16L + 20L + 6L) * nn + 24L,
      record_words: (2L + 16L + 20L + 6L) * nn + 24L,
      reference_arrays: 4L * nn + 4L,
      reference_items: 8L * nn,
      // Decimal digit normalization and coefficient builders have input-bound
      // scratch plus <=39 retained coefficient units per scalar cell.
      scalar_arrays: 4L,
      scalar_items: 6L * b.to_int64() + 80L,
      maps: 2L * nn,
      map_entries: 2L * nn,
    })
    is Some(values) &&
    @decode.admission_construction_inventory(n, n, n, n, limits.max_depth)
    is Some(converted) &&
    @decode.issue_construction_extent(limits.max_depth) is Some(issue) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) else {
    return None
  }
  @execution.compose_preparation_representation([
    parsed,
    literals,
    read_initialization_collection_units(response),
    read_initialization_collection_units(values),
    {
      record_headers: converted.indexed.record_headers,
      reference_slots: converted.indexed.reference_slots,
      scalar_words: converted.indexed.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    {
      record_headers: converted.keys.record_headers,
      reference_slots: converted.keys.reference_slots,
      scalar_words: converted.keys.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    {
      record_headers: converted.ancestry.record_headers,
      reference_slots: converted.ancestry.reference_slots,
      scalar_words: converted.ancestry.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    {
      record_headers: converted.controls.record_headers,
      reference_slots: converted.controls.reference_slots,
      scalar_words: converted.controls.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    read_initialization_collection_units(issue),
    {
      record_headers: hash.record_headers,
      reference_slots: hash.reference_slots,
      scalar_words: hash.scalar_words,
      // UTF8 decode + scalar numeric digit/substring copies + normalized
      // decimal/timestamp output (at most39/30 per original cell).
      owned_utf16_units: hash.owned_utf16_units + 6L * b.to_int64() + 69L * nn,
      owned_wire_bytes: hash.owned_wire_bytes + 2L * body_bytes.to_int64(),
    },
  ])
}

///|
/// Full DescribeTable/GenerateReadDeclaration/DeclarationJson synchronous
/// producer demand from the SAME bounded body-length vector and identifiers.
/// This constructs no description, schema, original or I/O owner. The Host
/// keeps the entire peak backed through initializer retirement, even on error.
pub fn read_declaration_construction_capacity(
  body_lengths : Array[Int],
  encoded_units : Int,
  target_units : Int,
  resource_units : Int,
  connector_units : Int,
  revision_units : Int,
  response : @response.ResponseLimits,
  description : DescriptionLimits,
  declaration : @rows.RowDeclarationLimits,
) -> @execution.ExecutionCapacity? {
  if body_lengths.is_empty() ||
    encoded_units < 0 ||
    target_units < 0 ||
    resource_units < 0 ||
    connector_units < 0 ||
    revision_units < 0 ||
    response.max_bytes < 1 ||
    response.max_nodes < 1 ||
    response.max_depth < 1 ||
    response.max_columns < 1 ||
    response.max_name_units < 1 ||
    response.max_handle_units < 1 ||
    response.max_partitions < 1 ||
    response.max_rows < 0 ||
    response.max_total_rows < 0L ||
    !valid_description_limits(description) {
    return None
  }
  let parts = []
  let mut bytes = 0L
  for size in body_lengths {
    if size < 0 || size > response.max_bytes {
      return None
    }
    bytes += size.to_int64()
    if bytes > 2147483647L {
      return None
    }
    guard read_response_construction(size, response) is Some(part) else {
      return None
    }
    parts.push(part)
  }
  let f = Int64::min(bytes, description.max_columns.to_int64())
  if f > 2147483646L {
    return None
  }
  // Every SQL metadata row is visited once. Each supported output field is a
  // primitive or decimal (<=five Json nodes); no array/record Contract expands
  // VARIANT: Snowflake projects those as Common JsonType.
  let decimal = "{\"nullable\":false,\"precision\":38,\"scale\":38,\"type\":\"decimal\"}"
    .length()
    .to_int64()
  let sb = Int64::min(
    description.max_schema_bytes.to_int64(),
    2L + 6L * bytes + f * (decimal + 4L),
  ).to_int()
  let sn = Int64::min(description.max_nodes.to_int64(), 1L + 5L * f).to_int()
  let names = Int64::min(
    bytes + target_units.to_int64(),
    description.max_name_bytes.to_int64(),
  )
  // SELECT + FROM + dot/comma + quote escaping, all independently prechecked
  // by prepare_read_projection. Intermediate quoted names/join/prefix Strings
  // are separately counted below, never max_schema_bytes for a tiny table.
  let sql = Int64::min(
    description.max_schema_bytes.to_int64(),
    21L + 3L * f + 2L * names,
  )
  guard @contract.object_construction_inventory(f.to_int(), names.to_int())
    is Some(objects) &&
    @contract.checked_emission_construction_extent((f + 1L).to_int())
    is Some(emission) &&
    read_initialization_writer_units(sb, sn, description.max_depth)
    is Some(writer) &&
    @rows.single_relation_declaration_construction_inventory(
      sb,
      sn,
      f.to_int(),
      2,
      1,
      resource_units,
      connector_units,
      revision_units,
      declaration,
    )
    is Some(common) &&
    @shape.collection_construction_extent({
      // DescriptionColumn1H8R, cell/options/number outcomes and selected tuple
      // <=32H44R32W; primitive/decimal Contract alternatives <=7H10R8W.
      // Ten cell lookups/Some/Array plus column-name snapshots are independent.
      records: 24L + (1L + 32L + 7L + 10L) * f,
      record_references: 40L + (8L + 44L + 10L + 10L) * f,
      record_words: 32L + (3L + 32L + 8L + 10L) * f,
      reference_arrays: 12L + 4L * f,
      reference_items: 32L + 20L * f + 2L * body_lengths.length().to_int64(),
      scalar_arrays: 2L,
      scalar_items: 3L * sql + 12L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(projected) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) else {
    return None
  }
  parts.push(read_initialization_collection_units(objects.retained))
  parts.push(read_initialization_collection_units(objects.scratch))
  parts.push(read_initialization_collection_units(emission))
  parts.push(read_initialization_collection_units(projected))
  parts.push(writer)
  parts.push(common)
  parts.push({
    record_headers: hash.record_headers,
    reference_slots: hash.reference_slots,
    scalar_words: hash.scalar_words,
    owned_utf16_units: hash.owned_utf16_units +
    objects.scratch_utf16_units +
    encoded_units.to_int64() +
    target_units.to_int64() +
    4L * sql +
    sb.to_int64(),
    owned_wire_bytes: hash.owned_wire_bytes + sb.to_int64(),
  })
  guard @execution.compose_preparation_representation(parts) is Some(peak) else {
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
