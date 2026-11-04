///|
/// Constructor DATA only. The original full row Contract must already have
/// been obtained from the declared mapping under funded metadata preparation.
/// Paths borrow their original Strings; these are their bounded array lengths.
pub(all) struct RelationDocumentProjectionConstruction {
  original : @contract.Contract
  items_path_depth : Int
  key_path_depth : Int?
  writable_fields : Int
}

///|
fn relation_document_construction_limits_valid(limits : RowPageLimits) -> Bool {
  limits.max_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_rows >= 0
}

///|
fn relation_document_construction_scale(
  units : @execution.PreparationRepresentationUnits,
  count : Int64,
) -> @execution.PreparationRepresentationUnits? {
  if count < 0L {
    return None
  }
  for
    quantity in [
      units.record_headers,
      units.reference_slots,
      units.scalar_words,
      units.owned_utf16_units,
      units.owned_wire_bytes,
    ] {
    if quantity < 0L || (count > 0L && quantity > 9223372036854775807L / count) {
      return None
    }
  }
  @execution.compose_preparation_representation([
    {
      record_headers: units.record_headers * count,
      reference_slots: units.reference_slots * count,
      scalar_words: units.scalar_words * count,
      owned_utf16_units: units.owned_utf16_units * count,
      owned_wire_bytes: units.owned_wire_bytes * count,
    },
  ])
}

///|
/// Whole original byte copy, preserving parser/tree and admitted cursor index.
/// The transport's input Bytes are borrowed and must remain funded separately.
/// Refusal scratch coexists with completed backing; no GC release is assumed.
pub fn relation_document_raw_construction_inventory(
  limits : RowPageLimits,
) -> @execution.PreparationRepresentationUnits? {
  guard relation_document_construction_limits_valid(limits) &&
    @decode.preserving_json_parser_construction_inventory(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(parsed) &&
    @decode.admission_construction_inventory(
      limits.max_nodes,
      limits.max_nodes,
      limits.max_nodes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(index) else {
    return None
  }
  @execution.compose_preparation_representation([
    {
      record_headers: parsed.record_headers,
      reference_slots: parsed.reference_slots,
      scalar_words: parsed.scalar_words,
      owned_utf16_units: parsed.owned_utf16_units,
      owned_wire_bytes: limits.max_bytes.to_int64(),
    },
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
    // Document/self Option, work Ref, Bytes header, makei closure, limits,
    // usage and success/refusal carriers. Parsed tree/index are above.
    {
      record_headers: 10L,
      reference_slots: 16L,
      scalar_words: 24L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
/// Fund BEFORE mapping_original_relation. Each successful original consumes
/// at least one of the cumulative node budget; one further reader can fail.
/// Payload nodes/bytes are cumulative across those readers. Their total
/// ancestry is bounded by cumulative nodes, with per-reader minimum controls
/// counted separately. Both canonical checks and schema construction overlap;
/// no full payload is multiplied by the number of contract envelopes.
pub fn relation_document_mapping_construction_inventory(
  limits : RowPageLimits,
) -> @execution.PreparationRepresentationUnits? {
  guard relation_document_construction_limits_valid(limits) &&
    relation_construction_decoded_construction(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_nodes,
      true,
    )
    is Some(decoded) &&
    relation_construction_json_forest(limits.max_nodes.to_int64())
    is Some(forest) &&
    relation_construction_contract_units(
      limits.max_nodes,
      limits.max_bytes,
      limits.max_depth,
    )
    is Some(contract) &&
    relation_construction_writer_units(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(writer) &&
    @encode.hash_writer_construction_inventory(
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(hash) &&
    @schema.unqualified_presence_construction_inventory(
      limits.max_nodes,
      limits.max_bytes,
    )
    is Some(schema) &&
    @schema.from_object_construction_extent(2) is Some(wrappers) &&
    @execution.compose_preparation_representation([
      decoded,
      relation_construction_collection_units(forest),
      relation_construction_collection_units(forest),
      contract,
      writer,
      relation_construction_collection_units(schema.retained),
      relation_construction_collection_units(schema.scratch),
      relation_construction_collection_units(wrappers),
      {
        record_headers: hash.record_headers + 12L,
        reference_slots: hash.reference_slots + 24L,
        scalar_words: hash.scalar_words + 12L,
        owned_utf16_units: hash.owned_utf16_units +
        schema.scratch_utf16_units +
        4L * limits.max_bytes.to_int64(),
        // mapping_read_original's UTF8 size probe owns its temporary Bytes.
        owned_wire_bytes: hash.owned_wire_bytes + limits.max_bytes.to_int64(),
      },
    ])
    is Some(one) else {
    return None
  }
  guard relation_construction_decoded_construction(1, 1, 1, true)
    is Some(reader_minimum) &&
    relation_document_construction_scale(
      reader_minimum,
      limits.max_nodes.to_int64() + 1L,
    )
    is Some(reader_controls) else {
    return None
  }
  // Only the selected View and selected carrier need canonical verification.
  // The first writer/hash is included in one; this is the second original.
  @execution.compose_preparation_representation([
    one,
    reader_controls,
    writer,
    {
      record_headers: hash.record_headers,
      reference_slots: hash.reference_slots,
      scalar_words: hash.scalar_words,
      owned_utf16_units: hash.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes,
    },
  ])
}

///|
// Sum feasible pure-container and text-leaf endpoint geometries. These
// overbound mixed trees without inventing an unsupported Value constructor.
fn relation_document_typed_construction(
  original : @contract.Contract,
  limits : RowPageLimits,
) -> @execution.PreparationRepresentationUnits? {
  let n = limits.max_nodes
  let parts = []
  for
    (arrays, objects, texts, items, fields) in [
      (n, 0, 0, n - 1, 0),
      (0, n, 0, 0, n - 1),
      (if n == 1 { 0 } else { 1 }, 0, if n == 1 { 1 } else { n - 1 }, n - 1, 0),
    ] {
    guard @admitted.contract_value_phase_construction_inventory(
        original,
        {
          nodes: n,
          arrays,
          objects,
          texts,
          array_items: items,
          fields,
          max_object_fields: fields,
          max_key_utf16: limits.max_bytes,
          max_text_utf16: limits.max_bytes,
          total_utf16: limits.max_bytes.to_int64(),
          work: n.to_int64(),
        },
        limits.max_depth.to_int64(),
        limits.max_depth,
      )
      is Some(value) else {
      // Json, Vector, references and any future unaccounted shape refuse.
      return None
    }
    parts.push(relation_construction_collection_units(value.returned))
    parts.push(relation_construction_collection_units(value.temporary))
    parts.push({
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: value.returned_utf16_units +
      value.temporary_utf16_units,
      owned_wire_bytes: 0L,
    })
    if value.normalization is Some(normalization) {
      parts.push({
        record_headers: normalization.record_headers,
        reference_slots: normalization.reference_slots,
        scalar_words: normalization.scalar_words,
        owned_utf16_units: normalization.owned_utf16_units,
        owned_wire_bytes: 0L,
      })
    }
  }
  guard @execution.compose_preparation_representation(parts) is Some(one) else {
    return None
  }
  // Raw payload nodes/text are disjoint across calls: construct their body
  // ONCE, plus each call's fixed entry/refusal controls. Rechecks of existing
  // containers are accounted separately, not as fresh copies of their trees.
  guard @admitted.contract_value_phase_construction_inventory(
      original,
      {
        nodes: 1,
        arrays: 0,
        objects: 0,
        texts: 1,
        array_items: 0,
        fields: 0,
        max_object_fields: 0,
        max_key_utf16: 0,
        max_text_utf16: 0,
        total_utf16: 0L,
        work: 1L,
      },
      0L,
      0,
    )
    is Some(entry) &&
    @execution.compose_preparation_representation([
      relation_construction_collection_units(entry.returned),
      relation_construction_collection_units(entry.temporary),
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: entry.returned_utf16_units +
        entry.temporary_utf16_units,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(entry_units) &&
    relation_document_construction_scale(entry_units, n.to_int64())
    is Some(entries) else {
    return None
  }
  @execution.compose_preparation_representation([one, entries])
}

///|
// Bounded inspection of the already-funded checked schema, not a new schema.
// The outer row Object is projected field-by-field, never rechecked as a value.
fn relation_document_nested_construction(
  fields : @contract.Fields,
) -> (Int, Bool, Bool, Bool) {
  let pending = []
  for index in 0..<@contract.field_count(fields) {
    pending.push((@contract.field_at(fields, index).unwrap().contract, 0))
  }
  let mut depth = 0
  let mut objects = false
  let mut decimals = false
  let mut integers = false
  while pending.pop() is Some((current, level)) {
    match current.shape {
      @contract.Array(item, ..) => {
        depth = Int::max(depth, level + 1)
        pending.push((item, level + 1))
      }
      @contract.Object(children) => {
        objects = true
        depth = Int::max(depth, level + 1)
        for index in 0..<@contract.field_count(children) {
          pending.push(
            (@contract.field_at(children, index).unwrap().contract, level + 1),
          )
        }
      }
      @contract.Decimal(..) => decimals = true
      @contract.Signed64 => integers = true
      _ => ()
    }
  }
  (depth, objects, decimals, integers)
}

///|
/// One retained projection plus its full constructor/failure overlap. The
/// raw tree is shared, not reparsed. Metadata reconstruction is separate here
/// and is included by the whole-document composer below.
pub fn relation_document_projection_construction_inventory(
  projection : RelationDocumentProjectionConstruction,
  limits : RowPageLimits,
) -> @execution.PreparationRepresentationUnits? {
  guard relation_document_construction_limits_valid(limits) &&
    projection.items_path_depth >= 0 &&
    projection.items_path_depth <= limits.max_depth &&
    projection.writable_fields >= 0 &&
    projection.writable_fields <= limits.max_nodes &&
    projection.original.shape is @contract.Object(fields) &&
    !projection.original.nullable else {
    return None
  }
  if projection.key_path_depth is Some(depth) &&
    (depth < 0 || depth > limits.max_depth) {
    return None
  }
  let f = @contract.field_count(fields).to_int64()
  let n = limits.max_nodes.to_int64()
  let r = Int::min(limits.max_rows, limits.max_nodes).to_int64()
  let (nested_depth, has_objects, has_decimals, has_integers) = relation_document_nested_construction(
    fields,
  )
  let d = Int::min(nested_depth, Int::min(limits.max_depth, limits.max_nodes)).to_int64()
  let recheck_count = if d == 0L { 0L } else { n * d }
  let normalization_depth = if has_objects { d } else { 0L }
  let decimal_depth = if has_decimals { d } else { 0L }
  guard n <= 9223372036854775807L / 3L / (d + 1L) &&
    limits.max_bytes.to_int64() <= 9223372036854775807L / 2L / (d + 1L) &&
    f <= n &&
    relation_document_typed_construction(projection.original, limits)
    is Some(typed) &&
    @shape.collection_construction_extent({
      // Target/self Option; row/field cursors and checked wrappers; nested
      // object pairs, Value wrappers, builder/recheck/refusal controls.
      records: 12L + 16L * n + 2L * r,
      record_references: 24L + 32L * n + 4L * r,
      record_words: 16L + 32L * n + r,
      // Names concat, columns, writable, key cursors, row cursors, identity
      // keys, rows/row arrays; nested declared names, values/copies/sort work.
      reference_arrays: 8L + r + 6L * n,
      reference_items: 2L +
      projection.items_path_depth.to_int64() +
      projection.key_path_depth.unwrap_or(0).to_int64() +
      projection.writable_fields.to_int64() +
      2L * f +
      3L * r +
      Int64::min(r * f, n) +
      8L * n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L * n,
      map_entries: 2L * n,
    })
    is Some(controls) &&
    // Signed64 conversion copies original numeric spelling BEFORE overflow
    // refusal. Successful tokens fit 20 units; failed tokens require the whole
    // input byte bound. Disjoint raw spans sum to at most max_bytes, not N*B.
    relation_construction_decoded_construction(
      limits.max_bytes,
      limits.max_nodes,
      1,
      false,
    )
    is Some(integers) &&
    relation_construction_decoded_construction(1, 1, 1, false)
    is Some(integer_entry) &&
    relation_document_construction_scale(integer_entry, n)
    is Some(integer_entries) &&
    @shape.collection_construction_extent({
      // Synchronous recheck_value (NOT RecheckCursor): budget, optional
      // counters/results, CheckedValue and Array.all closure; scalar refusal
      // alternatives include Date/Timestamp's 4+12+12 scalar vectors. A raw
      // node is revisited by at most one container at each original depth.
      records: 12L,
      record_references: 16L,
      record_words: 24L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 3L,
      scalar_items: 28L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(recheck) &&
    relation_document_construction_scale(
      relation_construction_collection_units(recheck),
      recheck_count,
    )
    is Some(rechecks) &&
    @canonical.nfc_lf_construction_extent(limits.max_bytes)
    is Some(normalization) &&
    @canonical.nfc_lf_construction_extent(0) is Some(normalization_entry) &&
    relation_document_construction_scale(
      {
        record_headers: normalization.record_headers,
        reference_slots: normalization.reference_slots,
        scalar_words: normalization.scalar_words,
        owned_utf16_units: normalization.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
      normalization_depth,
    )
    is Some(normalizations) &&
    relation_document_construction_scale(
      {
        record_headers: normalization_entry.record_headers,
        reference_slots: normalization_entry.reference_slots,
        scalar_words: normalization_entry.scalar_words,
        owned_utf16_units: normalization_entry.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
      n * normalization_depth,
    )
    is Some(normalization_entries) else {
    return None
  }
  @execution.compose_preparation_representation([
    typed,
    relation_construction_collection_units(controls),
    relation_document_construction_scale(
      integers,
      if has_integers {
        1L
      } else {
        0L
      },
    ).unwrap(),
    relation_document_construction_scale(
      integer_entries,
      if has_integers {
        1L
      } else {
        0L
      },
    ).unwrap(),
    rechecks,
    normalizations,
    normalization_entries,
    // Recursive Decimal recheck reconstructs canonical coefficients and their
    // carriers; total original text per depth stays bounded by raw input.
    {
      record_headers: 3L * n * decimal_depth,
      reference_slots: 2L * n * decimal_depth,
      scalar_words: 2L * n * decimal_depth,
      owned_utf16_units: 2L * limits.max_bytes.to_int64() * decimal_depth,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
/// One reusable raw original plus the SUM of all simultaneous declared model
/// projections. Duplicated projections are counted again; no logical dedup or
/// maximum substitutes for physical coexistence. Metadata contracts and all
/// mapping scratch remain in the overlap. Source and Effect use the same DATA;
/// later observation/hash/update writers need their own phase inventories.
/// Caller funds metadata inspection first, then reserves this complete demand
/// under its existing Run/Ledger BEFORE receiving/admitting document bytes.
pub fn relation_document_construction_inventory(
  limits : RowPageLimits,
  projections : Array[RelationDocumentProjectionConstruction],
) -> @execution.PreparationRepresentationUnits? {
  guard relation_document_raw_construction_inventory(limits) is Some(raw) else {
    return None
  }
  let parts = [raw]
  for projection in projections {
    guard relation_document_mapping_construction_inventory(limits)
      is Some(mapping) &&
      relation_document_projection_construction_inventory(projection, limits)
      is Some(projected) else {
      return None
    }
    parts.push(mapping)
    parts.push(projected)
  }
  @execution.compose_preparation_representation(parts)
}

///|
/// Explicit metadata CONSTRUCTION after the caller funds
/// relation_document_mapping_construction_inventory under its existing
/// preparation owner. This returns the exact checked Contract produced by
/// the original declared mapping, without a schema cache or another receipt.
/// It does not prove that the caller has installed services/funding context,
/// admit document bytes, or authorize Source/Effect I/O. Quantity observers
/// never call this implicitly while computing their pre-construction demand.
pub fn relation_document_projection_contract(
  declaration : RowDeclaration,
  resource : String,
  primary_identity : String,
  limits : RowPageLimits,
) -> Result[@contract.Contract, RowMappingIssue] {
  if !relation_document_construction_limits_valid(limits) {
    return Err(InvalidSpecification)
  }
  match
    mapping_original_relation(declaration, resource, primary_identity, {
      max_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_views: limits.max_nodes,
      max_fields: limits.max_nodes,
    }) {
    Ok((_, original)) => Ok(original)
    Err(issue) => Err(issue)
  }
}
