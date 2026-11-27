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
        // Same document-consumption original selector (Query or whole Source).
        // One H/R/S remains live across the response-ticket/current boundary.
        record_headers: hash.record_headers + 13L,
        reference_slots: hash.reference_slots + 25L,
        scalar_words: hash.scalar_words + 13L,
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
/// Fund the original mapping, one additional canonical carrier-facts check
/// and the exact ordered index layout before preparing a composite file key.
/// The authored names are borrowed. A later probe needs its own workspace.
pub fn relation_document_key_metadata_construction_inventory(
  limits : RowPageLimits,
  key_fields : Int,
) -> @execution.PreparationRepresentationUnits? {
  guard key_fields >= 2 &&
    key_fields <= limits.max_nodes &&
    relation_document_mapping_construction_inventory(limits) is Some(mapping) &&
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
    @shape.collection_construction_extent({
      records: 3L,
      record_references: 5L,
      record_words: 2L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 1L,
      scalar_items: key_fields.to_int64(),
      maps: 0L,
      map_entries: 0L,
    })
    is Some(key) else {
    return None
  }
  @execution.compose_preparation_representation([
    mapping,
    writer,
    relation_construction_collection_units(key),
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
/// Quote the selected original before constructing its prepared key. Completed
/// parser, identity and writer frames contribute only to the working peak.
pub fn relation_document_key_metadata_capacity(
  declaration : RowDeclaration,
  resource : String,
  limits : RowPageLimits,
  key_fields : Int,
) -> @execution.ExecutionCapacity? {
  guard relation_document_construction_limits_valid(limits) &&
    declaration.views.search_by(view => view.resource == resource)
    is Some(index) &&
    declaration.view_bodies.get(index) is Some(view) &&
    update_mapping_original_geometry(declaration, view) is Some(geometry) else {
    return None
  }
  let bytes = Int::min(limits.max_bytes, geometry.bytes)
  let nodes = Int::min(limits.max_nodes, geometry.nodes)
  let depth = limits.max_depth
  guard relation_document_key_metadata_construction_inventory(
      { max_bytes: bytes, max_nodes: nodes, max_depth: depth, max_rows: 0, },
      key_fields,
    )
    is Some(workspace) &&
    @schema.unqualified_presence_retained_extent(nodes, 1) is Some(schema) &&
    @shape.collection_construction_extent({
      records: 6L,
      record_references: 13L,
      record_words: 9L,
      reference_arrays: 2L,
      reference_items: nodes.to_int64() + key_fields.to_int64(),
      scalar_arrays: 1L,
      scalar_items: key_fields.to_int64(),
      maps: 0L,
      map_entries: 0L,
    })
    is Some(layout) else {
    return None
  }
  let parts = [
    relation_construction_collection_units(schema),
    relation_construction_collection_units(layout),
    {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 4L * bytes.to_int64(),
      owned_wire_bytes: 0L,
    },
  ]
  for objects in [0, nodes] {
    guard @contract.read_construction_inventory({
        nodes,
        objects,
        arrays: nodes - objects,
        fields: nodes - 1,
        max_fields: nodes - 1,
        max_array_items: nodes - 1,
        max_selected_text_units: bytes,
        outer_depth: depth,
        work: nodes.to_int64(),
      })
      is Some(original) else {
      return None
    }
    parts.push(relation_construction_collection_units(original.retained))
  }
  guard @execution.compose_preparation_representation(parts) is Some(retained) &&
    @execution.preparation_representation_cost(retained) is Some(r) &&
    @execution.compose_preparation_representation([retained, workspace])
    is Some(peak) &&
    @execution.preparation_representation_cost(peak) is Some(e) else {
    return None
  }
  @execution.execution_capacity(r, e)
}

///|
// Sum feasible pure-container and text-leaf endpoint geometries. These
// overbound mixed trees without inventing an unsupported Value constructor.
fn relation_document_typed_construction(
  original : @contract.Contract,
  limits : RowPageLimits,
  returned_only? : Bool = false,
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
    if !returned_only {
      parts.push(relation_construction_collection_units(value.temporary))
    }
    parts.push({
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: value.returned_utf16_units +
      (if returned_only { 0L } else { value.temporary_utf16_units }),
      owned_wire_bytes: 0L,
    })
    if !returned_only && value.normalization is Some(normalization) {
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
      if returned_only {
        @execution.PreparationRepresentationUnits::{
          record_headers: 0L,
          reference_slots: 0L,
          scalar_words: 0L,
          owned_utf16_units: 0L,
          owned_wire_bytes: 0L,
        }
      } else {
        relation_construction_collection_units(entry.temporary)
      },
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: entry.returned_utf16_units +
        (if returned_only { 0L } else { entry.temporary_utf16_units }),
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
fn relation_document_projection_construction_valid(
  projection : RelationDocumentProjectionConstruction,
  limits : RowPageLimits,
) -> Bool {
  relation_document_construction_limits_valid(limits) &&
  projection.items_path_depth >= 0 &&
  projection.items_path_depth <= limits.max_depth &&
  projection.writable_fields >= 0 &&
  projection.writable_fields <= limits.max_nodes &&
  (
    projection.key_path_depth is None ||
    (
      projection.key_path_depth is Some(depth) &&
      depth >= 0 &&
      depth <= limits.max_depth
    )
  ) &&
  (
    projection.original.shape is @contract.Object(fields) &&
    @contract.field_count(fields) <= limits.max_nodes
  ) &&
  !projection.original.nullable
}

///|
/// Surviving immutable Values after a read-only projection has transferred
/// into the original Row and all document/cursor/constructor aliases retire.
/// Keep the SAME Contract's returned Value/CheckedValue inventory and owned
/// Decimal output. Text borrowed from Source is NOT included by that Value
/// inventory: retain its original String headers and decoded UTF16 backing
/// separately, without Span/tree/index/Bytes or temporary admission controls.
/// borrowed_text_utf16 must bound the SAME input's decoded text, not guessed
/// output sizes. This DATA neither proves retirement nor reduces a reservation.
pub fn relation_document_projection_retained_inventory(
  projection : RelationDocumentProjectionConstruction,
  limits : RowPageLimits,
  borrowed_text_utf16 : Int64,
) -> @execution.PreparationRepresentationUnits? {
  guard relation_document_projection_construction_valid(projection, limits) &&
    projection.writable_fields == 0 &&
    borrowed_text_utf16 >= 0L &&
    borrowed_text_utf16 <= limits.max_bytes.to_int64() &&
    relation_document_typed_construction(
      projection.original,
      limits,
      returned_only=true,
    )
    is Some(typed) &&
    @source.json_index_borrowed_construction_extent(
      limits.max_nodes,
      limits.max_nodes - 1,
      borrowed_text_utf16,
      keep_spans=false,
    )
    is Some(borrowed) else {
    return None
  }
  @execution.compose_preparation_representation([
    typed,
    {
      record_headers: borrowed.record_headers,
      reference_slots: borrowed.reference_slots,
      scalar_words: borrowed.scalar_words,
      owned_utf16_units: borrowed.owned_utf16_units,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
/// One retained projection plus its full constructor/failure overlap. The
/// raw tree is shared, not reparsed. Metadata reconstruction is separate here
/// and is included by the whole-document composer below.
pub fn relation_document_projection_construction_inventory(
  projection : RelationDocumentProjectionConstruction,
  limits : RowPageLimits,
) -> @execution.PreparationRepresentationUnits? {
  guard relation_document_projection_construction_valid(projection, limits) &&
    projection.original.shape is @contract.Object(fields) &&
    !projection.original.nullable else {
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

///|
/// Construct ONCE under the caller's original metadata allowance. The same
/// declaration and immutable mapping bounds must accompany later projection.
/// This retains the original checker result, never caller-provided schema DATA.
pub fn prepare_relation_document_contract(
  declaration : RowDeclaration,
  resource : String,
  primary_identity : String,
  limits : RowPageLimits,
) -> Result[RelationDocumentPreparedContract, RowMappingIssue] {
  let contract = match
    relation_document_projection_contract(
      declaration, resource, primary_identity, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @schema.from_object(contract) is Ok(schema) else {
    return Err(InvalidSpecification)
  }
  let columns = @schema.fields(schema).map(@schema.field_reference_name)
  guard columns.search(primary_identity) is Some(identity_index) else {
    return Err(InvalidSpecification)
  }
  let identity = @schema.field_at(schema, identity_index).unwrap().contract
  if identity.nullable || !(identity.shape is @contract.Text(_)) {
    return Err(InvalidSpecification)
  }
  Ok({
    declaration,
    resource,
    primary_identity,
    limits,
    contract,
    schema,
    columns,
    identity_index,
  })
}

///|
/// Select the exact ordered candidate from the original relation facts.
/// This prepares only non-null Text and Signed64 file key metadata; it issues
/// no Source grant, Mapping, or live uniqueness evidence.
pub fn prepare_relation_document_key_contract(
  declaration : RowDeclaration,
  resource : String,
  ordered_key : Array[String],
  limits : RowPageLimits,
) -> Result[RelationDocumentPreparedKey, RowMappingIssue] {
  if !relation_document_construction_limits_valid(limits) ||
    ordered_key.length() < 2 ||
    ordered_key.length() > limits.max_nodes {
    return Err(InvalidSpecification)
  }
  let mut name_bytes = limits.max_bytes
  for name in ordered_key {
    guard !name.is_empty() &&
      @scalar.admit_utf8_length(name, name_bytes) is Ok(bytes) else {
      return Err(InvalidSpecification)
    }
    name_bytes -= bytes
  }
  let primary_identity = ordered_key[0]
  let contract = match
    mapping_original_relation(
      declaration,
      resource,
      primary_identity,
      {
        max_bytes: limits.max_bytes,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_views: limits.max_nodes,
        max_fields: limits.max_nodes,
      },
      ordered_key=Some(ordered_key),
    ) {
    Ok((_, value)) => value
    Err(issue) => return Err(issue)
  }
  guard @schema.from_object(contract) is Ok(schema) else {
    return Err(InvalidSpecification)
  }
  let columns = @schema.fields(schema).map(@schema.field_reference_name)
  let positions = Array::make(ordered_key.length(), -1)
  for ordinal, name in ordered_key {
    guard columns.search(name) is Some(position) &&
      !positions.contains(position) else {
      return Err(InvalidSpecification)
    }
    let identity = @schema.field_at(schema, position).unwrap().contract
    if identity.nullable ||
      !(identity.shape is @contract.Text(_) ||
      identity.shape is @contract.Signed64) {
      return Err(InvalidSpecification)
    }
    positions[ordinal] = position
  }
  Ok({
    original: {
      declaration,
      resource,
      primary_identity,
      limits,
      contract,
      schema,
      columns,
      identity_index: positions[0],
    },
    positions,
  })
}

///|
/// Borrowed immutable quantity input, not a projection, resource or permission.
pub fn relation_document_prepared_contract(
  original : RelationDocumentPreparedContract,
) -> @contract.Contract {
  original.contract
}

///|
/// Borrow the same checked metadata for the physical owner's sizing phase.
pub fn relation_document_key_prepared_contract(
  original : RelationDocumentPreparedKey,
) -> RelationDocumentPreparedContract {
  original.original
}

///|
/// Workspace for a canonical key probe after the original projection is
/// funded. The original request wire is retained by the caller.
pub fn relation_target_key_wire_workspace_inventory(
  prepared : RelationDocumentPreparedKey,
  key_wire_utf16 : Int,
) -> @execution.PreparationRepresentationUnits? {
  let limits = prepared.original.limits
  let width = prepared.positions.length()
  guard width < limits.max_nodes &&
    limits.max_depth >= 2 &&
    key_wire_utf16 > 0 &&
    key_wire_utf16 <= limits.max_bytes else {
    return None
  }
  let nodes = width + 1
  let bytes = Int64::min(
    3L * key_wire_utf16.to_int64(),
    limits.max_bytes.to_int64(),
  ).to_int()
  // Ordered File admits only Text and Int64. Their typed-wire admission
  // uses the same scalar workspace at this bound, regardless of key order.
  let scalar = @schema.field_at(prepared.original.schema, prepared.positions[0]).unwrap().contract
  guard relation_document_raw_construction_inventory({
      max_bytes: bytes,
      max_nodes: nodes,
      max_depth: 2,
      max_rows: 1,
    })
    is Some(decoded) &&
    @admitted.contract_value_phase_construction_inventory(
      scalar,
      {
        nodes: 1,
        arrays: 0,
        array_items: 0,
        objects: 0,
        fields: 0,
        texts: 1,
        max_object_fields: 0,
        max_key_utf16: 0,
        max_text_utf16: key_wire_utf16,
        total_utf16: key_wire_utf16.to_int64(),
        work: 1L,
      },
      1L,
      2,
    )
    is Some(value) &&
    @execution.compose_preparation_representation([
      relation_construction_collection_units(value.returned),
      relation_construction_collection_units(value.temporary),
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: value.returned_utf16_units +
        value.temporary_utf16_units,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(entry) &&
    relation_document_construction_scale(entry, width.to_int64())
    is Some(values) &&
    relation_construction_writer_units(bytes, nodes, 2) is Some(writer) &&
    @execution.preparation_array_representation(1L, width.to_int64(), false)
    is Some(tuple) else {
    return None
  }
  @execution.compose_preparation_representation([
    decoded,
    values,
    writer,
    tuple,
    { // Projection/key handles, bounded parser and returned result wrappers.
      record_headers: 12L,
      reference_slots: 18L,
      scalar_words: 8L,
      // Canonical checked Int64 components can produce decimal Text.
      owned_utf16_units: 20L * width.to_int64(),
      owned_wire_bytes: 0L,
    },
  ])
}

///|
/// Additional workspace for an insertion. The same physical child already
/// funds the original document and its selected projection. The retained
/// request String is borrowed. The file size comes from the original physical
/// observation, and the caller still funds transport buffers separately.
pub fn relation_target_insert_workspace_inventory(
  prepared : RelationDocumentPreparedContract,
  items_path_depth : Int,
  original_bytes : Int,
  row_wire_utf16 : Int,
) -> @execution.PreparationRepresentationUnits? {
  relation_target_insert_workspace_inventory_with_width(
    prepared, items_path_depth, original_bytes, row_wire_utf16, 1,
  )
}

///|
/// INSERT row and replacement workspace, in addition to the ordered key
/// probe and original projection.
pub fn relation_target_ordered_insert_workspace_inventory(
  prepared : RelationDocumentPreparedKey,
  items_path_depth : Int,
  original_bytes : Int,
  row_wire_utf16 : Int,
) -> @execution.PreparationRepresentationUnits? {
  relation_target_insert_workspace_inventory_with_width(
    prepared.original,
    items_path_depth,
    original_bytes,
    row_wire_utf16,
    prepared.positions.length(),
  )
}

///|
fn relation_target_insert_workspace_inventory_with_width(
  prepared : RelationDocumentPreparedContract,
  items_path_depth : Int,
  original_bytes : Int,
  row_wire_utf16 : Int,
  key_fields : Int,
) -> @execution.PreparationRepresentationUnits? {
  let limits = prepared.limits
  guard relation_document_construction_limits_valid(limits) &&
    limits.max_rows > 0 &&
    items_path_depth >= 0 &&
    items_path_depth < limits.max_depth - 1 &&
    original_bytes > 0 &&
    original_bytes < limits.max_bytes &&
    row_wire_utf16 > 0 &&
    row_wire_utf16 <= limits.max_bytes else {
    return None
  }
  // Three UTF-8 bytes per UTF-16 unit bounds the verified request before
  // encoding; every potential decoded node consumes at least one input byte.
  let input_bytes = Int64::min(
    3L * row_wire_utf16.to_int64(),
    limits.max_bytes.to_int64(),
  ).to_int()
  let nodes = Int::min(input_bytes, limits.max_nodes)
  let input_depth = Int::min(nodes, limits.max_depth)
  let row_limits = {
    max_bytes: input_bytes,
    max_nodes: nodes,
    max_depth: input_depth,
    max_rows: 1,
  }
  let room = limits.max_bytes - original_bytes
  // Key nodes are emitted from the separately admitted identity.
  let physical_nodes = nodes + Int::min(key_fields, limits.max_nodes - nodes)
  let output_depth = Int::min(
    input_depth,
    limits.max_depth - items_path_depth - 1,
  )
  guard relation_document_raw_construction_inventory(row_limits)
    is Some(decoded) &&
    relation_document_projection_construction_inventory(
      {
        original: prepared.contract,
        items_path_depth: 0,
        key_path_depth: None,
        writable_fields: 0,
      },
      row_limits,
    )
    is Some(values) &&
    relation_construction_writer_units(room, physical_nodes, output_depth)
    is Some(writer) &&
    @admitted.wire_emit_workspace_construction_inventory(1) is Some(emit) &&
    relation_document_construction_scale(
      {
        record_headers: emit.record_headers,
        reference_slots: emit.reference_slots,
        scalar_words: emit.scalar_words,
        owned_utf16_units: emit.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
      physical_nodes.to_int64(),
    )
    is Some(emitters) else {
    return None
  }
  @execution.compose_preparation_representation([
    decoded,
    values,
    writer,
    emitters,
    // The encoded physical row and complete replacement Bytes coexist with
    // the writer and original reference. Include spans and output closures,
    // plus the separate key's Text wrapper, scalar recheck and result.
    {
      record_headers: 16L,
      reference_slots: 24L,
      scalar_words: 28L,
      owned_utf16_units: if key_fields == 1 {
        0L
      } else {
        20L * key_fields.to_int64()
      },
      owned_wire_bytes: room.to_int64() + limits.max_bytes.to_int64(),
    },
  ])
}

///|
/// Shared construction of the replacement wire. The original file and
/// its row projection have separate backing. Physical write buffers and
/// transport belong to the installed adapter.
pub struct RelationTargetWriteWireConstruction {
  change_limits : (Int, Int, Int)
  encoded_change_bytes : Int64
  replacement_bytes : Int64
  value_writer_cost : Int64
  placement : @execution.PreparationRepresentationUnits
}

///|
/// The checked Contract, schema wrapper and column names retained after
/// Mapping readers return. The original declaration, resource and limits
/// are borrowed. Retain the decoded text that those checked values may alias.
pub fn relation_document_prepared_contract_retained_inventory(
  original : RelationDocumentPreparedContract,
) -> @execution.PreparationRepresentationUnits? {
  let limits = original.limits
  let nodes = limits.max_nodes
  guard @source.json_index_borrowed_construction_extent(
      nodes,
      nodes - 1,
      limits.max_bytes.to_int64(),
      keep_spans=false,
    )
    is Some(text) &&
    @schema.unqualified_presence_retained_extent(original.columns.length(), 1)
    is Some(carrier) &&
    @schema.from_object_construction_extent(1) is Some(schema) &&
    @execution.preparation_array_representation(
      1L,
      original.columns.length().to_int64(),
      true,
    )
    is Some(columns) &&
    @canonical.nfc_lf_retained_output_units(limits.max_bytes.to_int64())
    is Some(normalized) else {
    return None
  }
  let parts = [
    columns,
    relation_construction_collection_units(carrier),
    relation_construction_collection_units(schema),
    {
      record_headers: text.record_headers + 3L,
      reference_slots: text.reference_slots + 12L,
      scalar_words: text.scalar_words + 7L,
      owned_utf16_units: text.owned_utf16_units + normalized,
      owned_wire_bytes: 0L,
    },
  ]
  for objects in [0, nodes] {
    guard @contract.read_construction_inventory({
        nodes,
        objects,
        arrays: nodes - objects,
        fields: nodes - 1,
        max_fields: nodes - 1,
        max_array_items: nodes - 1,
        max_selected_text_units: limits.max_bytes,
        outer_depth: limits.max_depth,
        work: nodes.to_int64(),
      })
      is Some(inventory) else {
      return None
    }
    parts.push(relation_construction_collection_units(inventory.retained))
  }
  @execution.compose_preparation_representation(parts)
}

///|
// The same closed Text-only Contract profile used by measured projection.
// Each field is one typed Contract node; no array/nested Contract or value
// enumeration is traversed by the quote. Broader contracts keep old bounds.
pub fn relation_document_text_contract_nodes(
  contract : @contract.Contract,
) -> Int? {
  guard contract.shape is @contract.Object(fields) else { return None }
  let count = @contract.field_count(fields)
  if count == 2147483647 {
    return None
  }
  for index in 0..<count {
    if !(@contract.field_at(fields, index).unwrap().contract.shape
      is @contract.Text(_)) {
      return None
    }
  }
  Some(count + 1)
}

///|
/// Quote from the observed file extent and the held changes String length
/// before encoding, parsing, normalizing or constructing replacement bytes.
pub fn relation_target_write_wire_construction(
  contract : @contract.Contract,
  page : RowPageLimits,
  file_bytes : Int,
  changes_utf16_units : Int,
  deleting~ : Bool,
) -> RelationTargetWriteWireConstruction? {
  guard relation_document_construction_limits_valid(page) &&
    file_bytes >= 0 &&
    file_bytes <= page.max_bytes &&
    changes_utf16_units >= 0 &&
    changes_utf16_units <= page.max_bytes &&
    (!deleting || changes_utf16_units == 0) else {
    return None
  }
  // Count the full UTF-8 allocation even when the original parser later
  // refuses it. The parser and writer themselves retain their page limits.
  let encoded_change_bytes = 3L * changes_utf16_units.to_int64()
  let change_bytes = Int::max(
    1,
    Int64::min(page.max_bytes.to_int64(), encoded_change_bytes).to_int(),
  )
  let change_nodes = Int::min(page.max_nodes, change_bytes)
  let change_depth = Int::min(page.max_depth, change_nodes)
  guard @decode.preserving_json_admission_construction_inventory(
      change_bytes, change_nodes, change_depth,
    )
    is Some(request) &&
    @canonical.nfc_lf_construction_scratch_extent(change_bytes)
    is Some(normalizing) &&
    @canonical.nfc_lf_retained_output_units(change_bytes.to_int64())
    is Some(text) &&
    @execution.checked_preparation_add_product(128L, text, 6L) is Some(encoded) else {
    return None
  }
  let text_profile = relation_document_text_contract_nodes(contract) is Some(_)
  let value_bytes = if deleting {
    1
  } else if text_profile {
    Int64::min(page.max_bytes.to_int64(), encoded).to_int()
  } else {
    page.max_bytes
  }
  let value_nodes = if deleting || text_profile {
    change_nodes
  } else {
    page.max_nodes
  }
  let value_depth = if deleting || text_profile {
    change_depth
  } else {
    page.max_depth
  }
  let replacement_bytes = Int64::min(
    page.max_bytes.to_int64(),
    file_bytes.to_int64() + (if deleting { 0L } else { value_bytes.to_int64() }),
  )
  guard @encode.text_writer_construction_inventory(
      value_bytes, value_nodes, value_depth,
    )
    is Some(value_writer) else {
    return None
  }
  let emitter : @execution.PreparationRepresentationUnits = {
    record_headers: value_writer.record_headers,
    reference_slots: value_writer.reference_slots,
    scalar_words: value_writer.scalar_words,
    owned_utf16_units: value_writer.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  guard @execution.preparation_representation_cost(emitter)
    is Some(value_writer_cost) &&
    @execution.compose_preparation_representation([
      {
        record_headers: request.record_headers,
        reference_slots: request.reference_slots,
        scalar_words: request.scalar_words,
        owned_utf16_units: request.owned_utf16_units,
        owned_wire_bytes: encoded_change_bytes,
      },
      {
        record_headers: normalizing.record_headers,
        reference_slots: normalizing.reference_slots,
        scalar_words: normalizing.scalar_words,
        owned_utf16_units: normalizing.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
      emitter,
      {
        // UPDATE's checked layout and returned Result also stay live while
        // the original placement emits its complete replacement.
        record_headers: if deleting {
          8L
        } else {
          10L
        },
        reference_slots: if deleting {
          16L
        } else {
          19L
        },
        scalar_words: if deleting {
          8L
        } else {
          10L
        },
        owned_utf16_units: text,
        owned_wire_bytes: replacement_bytes,
      },
    ])
    is Some(placement) else {
    return None
  }
  Some({
    change_limits: (change_bytes, change_nodes, change_depth),
    encoded_change_bytes,
    replacement_bytes,
    value_writer_cost,
    placement,
  })
}
