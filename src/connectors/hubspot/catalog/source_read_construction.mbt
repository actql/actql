///|
/// HubSpot's original metadata/page sequence only. The shared Reader quotes
/// physical originals, Credential and RowRun controls separately. No provider
/// opaque value or authority is accepted by this quantity projection.
pub fn source_read_construction_capacity(
  limits : Array[Int],
  target_units : Int,
  received : Array[Int],
) -> @execution.ExecutionCapacity? {
  // response/nodes/depth/properties/name/pages/rows/requests/pageRows/columns/
  // cursor/valueNodes/valueText/rowsWire/rowsNodes/rowsDepth.
  if limits.length() != 16 || target_units < 1 {
    return None
  }
  for limit in limits {
    if limit < 1 {
      return None
    }
  }
  if received.length() > limits[7] ||
    limits[5] > limits[7] ||
    limits[8] > limits[6] {
    return None
  }
  for bytes in received {
    if bytes < 0 || bytes > limits[0] {
      return None
    }
  }
  // No Set entry or future body-array element exists at installation. Before
  // decoding one charged body, its full extent bounds every possible new id
  // and cursor; keep every prior/failed prefix until original retirement.
  let possible_pages = Int::max(0, received.length() - 2).to_int64()
  let pages = Int64::min(limits[5].to_int64(), possible_pages)
  let rows = Int64::min(
    limits[6].to_int64(),
    possible_pages * limits[8].to_int64(),
  )
  let columns = limits[9].to_int64()
  // Original callbacks and receivers, returned request/projection records,
  // bounded input copies and both cross-page duplicate-tracking Sets. Catalog,
  // Site and installed property names are borrowed from the original Source.
  guard @shape.collection_construction_extent({
      records: 96L,
      // One parent dependency count and two original-secret references for
      // the independently authorized metadata Resource bindings.
      record_references: 768L + 2L,
      record_words: 128L + 1L,
      reference_arrays: 16L,
      reference_items: 64L + 4L * columns + received.length().to_int64(),
      scalar_arrays: 4L,
      scalar_items: 16L + received.length().to_int64(),
      maps: 4L,
      map_entries: rows + pages,
    })
    is Some(controls) else {
    return None
  }
  let parts = [
    initialization_collection_units(controls),
    {
      record_headers: 16L,
      reference_slots: 32L,
      scalar_words: 16L,
      // Complete percent-encoded target, JSON metadata/row wrapper and the two
      // Set text families. Retained ids/cursors come from received originals.
      owned_utf16_units: 6L * target_units.to_int64() + 2048L,
      owned_wire_bytes: 0L,
    },
  ]
  let mut metadata_capacity = @execution.execution_capacity(0L, 0L).unwrap()
  for index, bytes in received {
    if bytes < 0 || bytes > limits[0] {
      return None
    }
    // The selected protocol always receives Account then Properties before
    // any object page. Final Properties may follow any number of pages, so
    // later positions retain the existing metadata/page superset below.
    if index < 2 {
      let current = if index == 0 {
        account_initialization_construction_capacity(
          bytes,
          0,
          11,
          limits[0],
          limits[1],
          limits[2],
        )
      } else {
        source_property_recheck_construction_capacity(limits, bytes)
      }
      guard current is Some(current) &&
        @execution.add_execution_capacity(metadata_capacity, current)
        is Some(combined) else {
        return None
      }
      // No successful/failed prefix is discarded by the next response. The
      // same Reader retirement remains the only capacity-lifetime boundary.
      metadata_capacity = combined
      continue
    }
    let n = Int::min(bytes, limits[1])
    // Empty/malformed bodies still retain their constructor controls. Bounds
    // cover both the normalizing Catalog and preserving Account/page paths.
    let b = Int::max(1, bytes)
    guard initialization_decoded_construction(
        b,
        Int::max(1, n),
        Int::min(Int::max(1, n), limits[2]),
        true,
      )
      is Some(parsed) &&
      initialization_writer_units(limits[13], limits[14], limits[15])
      is Some(writer) &&
      @shape.collection_construction_extent({
        records: 32L + 8L * limits[11].to_int64(),
        record_references: 64L + 16L * limits[11].to_int64(),
        record_words: 32L + 8L * limits[11].to_int64(),
        reference_arrays: 8L + 2L * limits[8].to_int64(),
        reference_items: 32L + 8L * limits[11].to_int64(),
        scalar_arrays: 4L,
        scalar_items: 4L * b.to_int64(),
        maps: 4L,
        map_entries: n.to_int64() + limits[3].to_int64(),
      })
      is Some(values) else {
      return None
    }
    parts.push(parsed)
    parts.push(initialization_collection_units(values))
    parts.push(writer)
    // Native projected rows, exact exported wire and its Host JSON.parse tree
    // coexist. Do not count delimiters as post-parse facts or retire a failed
    // prefix merely because the next response succeeded.
    guard @source.json_construction_extent(
        limits[13],
        limits[14],
        limits[15],
        normalize_keys=false,
      )
      is Some(host_rows) else {
      return None
    }
    parts.push({
      record_headers: host_rows.record_headers + 16L,
      reference_slots: host_rows.reference_slots + 32L,
      scalar_words: host_rows.scalar_words + 16L,
      owned_utf16_units: host_rows.owned_utf16_units +
      4L * b.to_int64() +
      8L * limits[13].to_int64() +
      4L * limits[12].to_int64() +
      6L * limits[4].to_int64() +
      2048L,
      owned_wire_bytes: b.to_int64(),
    })
  }
  guard initialization_capacity(parts) is Some(common) else { return None }
  @execution.add_execution_capacity(common, metadata_capacity)
}

///|
// Same Properties parser, native projection and Catalog family as Source
// initialization. This path only rechecks the original: no ObjectSchemaWire,
// row ValueNode forest, row-wire writer or Host row JSON.parse is constructed.
fn source_property_recheck_construction_capacity(
  limits : Array[Int],
  bytes : Int,
) -> @execution.ExecutionCapacity? {
  let b = Int::max(1, bytes)
  let n = Int::min(b, limits[1])
  let f = Int::min(n, limits[3])
  guard initialization_decoded_construction(b, n, Int::min(n, limits[2]), true)
    is Some(parsed) &&
    property_projection_construction_extent(n, f) is Some(metadata) &&
    @shape.collection_construction_extent({
      // recheck_property_catalog indexes the original only after confirming
      // equal field counts. Its names/PropertyMetadata remain borrowed.
      records: 16L + 4L * f.to_int64(),
      record_references: 24L + 8L * f.to_int64(),
      record_words: 16L + 4L * f.to_int64(),
      reference_arrays: 2L,
      reference_items: f.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: f.to_int64(),
    })
    is Some(recheck) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) else {
    return None
  }
  initialization_capacity([
    parsed,
    initialization_collection_units(metadata),
    property_catalog_retained_units(bytes, limits[4], {
      max_bytes: limits[0],
      max_nodes: limits[1],
      max_depth: limits[2],
      max_properties: limits[3],
      max_name_units: limits[4],
    }),
    initialization_collection_units(recheck),
    {
      record_headers: hash.record_headers,
      reference_slots: hash.reference_slots,
      scalar_words: hash.scalar_words,
      owned_utf16_units: hash.owned_utf16_units + 4L * b.to_int64() + 128L,
      owned_wire_bytes: hash.owned_wire_bytes + bytes.to_int64(),
    },
  ])
}
