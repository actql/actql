///|
/// One original Member's logical constructor overlap and surviving Snapshot.
/// Quantities are DATA, not semantic admission, a policy or physical backing.
/// peak includes retained: callers do not add the two envelopes together.
pub(all) struct MemberReadConstructionInventory {
  peak : @environment.RegistryConstructionExtent
  retained : @environment.RegistryConstructionExtent
  inspection_work : Int64
} derive(Eq, Debug)

///|
fn member_extent(
  value : @shape.CollectionConstructionExtent,
  utf16? : Int64 = 0L,
  wire? : Int64 = 0L,
) -> @environment.RegistryConstructionExtent {
  {
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
    owned_utf16_units: utf16,
    owned_wire_bytes: wire,
  }
}

///|
// Domain lifetime composition only. All checked sums and representation units
// remain with the existing shared owners; there is no tariff or allocator here.
fn member_extent_join(
  a : @environment.RegistryConstructionExtent,
  b : @environment.RegistryConstructionExtent,
) -> @environment.RegistryConstructionExtent? {
  guard @shape.add_collection_construction_extents(
      {
        record_headers: a.record_headers,
        reference_slots: a.reference_slots,
        scalar_words: a.scalar_words,
      },
      {
        record_headers: b.record_headers,
        reference_slots: b.reference_slots,
        scalar_words: b.scalar_words,
      },
    )
    is Some(boxes) &&
    @counts.checked_nonnegative_add_product(
      a.owned_utf16_units,
      b.owned_utf16_units,
      1L,
    )
    is Some(text) &&
    @counts.checked_nonnegative_add_product(
      a.owned_wire_bytes,
      b.owned_wire_bytes,
      1L,
    )
    is Some(bytes) else {
    return None
  }
  Some(member_extent(boxes, utf16=text, wire=bytes))
}

///|
fn member_extent_max(
  a : @environment.RegistryConstructionExtent,
  b : @environment.RegistryConstructionExtent,
) -> @environment.RegistryConstructionExtent {
  {
    record_headers: Int64::max(a.record_headers, b.record_headers),
    reference_slots: Int64::max(a.reference_slots, b.reference_slots),
    scalar_words: Int64::max(a.scalar_words, b.scalar_words),
    owned_utf16_units: Int64::max(a.owned_utf16_units, b.owned_utf16_units),
    owned_wire_bytes: Int64::max(a.owned_wire_bytes, b.owned_wire_bytes),
  }
}

///|
fn member_extent_sum(
  values : Array[@environment.RegistryConstructionExtent],
) -> @environment.RegistryConstructionExtent? {
  let mut result = member_extent({
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
  })
  for value in values {
    guard member_extent_join(result, value) is Some(next) else { return None }
    result = next
  }
  Some(result)
}

///|
fn member_json_extent(
  value : @source.JsonConstructionExtent,
) -> @environment.RegistryConstructionExtent {
  member_extent(
    {
      record_headers: value.record_headers,
      reference_slots: value.reference_slots,
      scalar_words: value.scalar_words,
    },
    utf16=value.owned_utf16_units,
  )
}

///|
/// Quote the SAME immutable Member. One original indexed metadata pass supplies
/// geometry; one root-field pass selects representation/lifetime alternatives.
/// It does not invoke the Connector selector, Reference/Contract reader or hash.
/// Canonical member emission preserves its admitted NFC field keys, so the
/// completed parse's total decoded key/value UTF16 is bounded by wire bytes.
/// Original failure limits may stop earlier; they never replace actual demand.
pub fn member_read_construction_inventory(
  original : @environment.Member,
) -> MemberReadConstructionInventory? {
  if @environment.member_section(original) != @environment.SchemaSnapshots {
    return None
  }
  let root = @environment.member_body(original)
  let g = @contract.observe_read_construction_geometry(root)
  let (bytes, nodes, depth) = @environment.member_emission_geometry(original)
  let width = @decode.object_length(root).unwrap_or(0)
  let mut work = g.work + 2L
  let mut reference = None
  let mut scores = false
  let mut presence = false
  let mut material = false
  let mut connector = false
  for i in 0..<width {
    let (name, value) = @decode.field_at(root, i).unwrap()
    work += 2L
    if name == snapshot_reference_field {
      work += 1L
      guard @decode.text(value) is Ok(text) else { return None }
      reference = @reference.reference_read_construction_inventory(
        text.length(),
      )
      connector = text.has_prefix("connector://")
    } else if name == "score_contracts" {
      scores = true
    } else if name == "column_presence" {
      presence = true
    } else if name == "input_cid" {
      material = true
    }
  }
  let zero = member_extent({
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
  })
  let selector = member_extent(
    @environment.connector_source_snapshot_selector_construction(original),
  )
  // The original selector either admits Connector metadata or refuses its
  // shape. It never falls through to the Local byte reader for this prefix.
  if connector {
    return Some({ peak: selector, retained: zero, inspection_work: work, })
  }
  guard reference is Some(reference) &&
    @source.json_tree_retained_construction_extent(
      nodes,
      g.fields,
      g.objects,
      g.arrays,
      bytes.to_int64(),
    )
    is Some(tree) &&
    @source.json_index_borrowed_construction_extent(
      nodes,
      g.fields,
      bytes.to_int64(),
      keep_spans=true,
    )
    is Some(borrowed) &&
    @source.json_index_borrowed_construction_extent(
      nodes,
      g.fields,
      bytes.to_int64(),
      keep_spans=scores,
    )
    is Some(returned_text) &&
    @source.json_construction_extent(bytes, nodes, depth, normalize_keys=true)
    is Some(parser) &&
    @decode.admission_construction_inventory(
      nodes,
      g.fields,
      g.objects,
      g.arrays,
      depth,
    )
    is Some(index) &&
    @contract.read_construction_inventory(g) is Some(contract) &&
    @schema.from_object_construction_extent(1) is Some(dense) &&
    @schema.unqualified_presence_construction_inventory(
      g.fields,
      g.max_selected_text_units,
    )
    is Some(scoped) &&
    @contract.checked_emission_construction_extent(Int::max(1, g.fields))
    is Some(emitter) &&
    @encode.hash_writer_live_key_inventory(g.fields, depth) is Some(hash) else {
    return None
  }
  let indexed = member_extent({
    record_headers: index.indexed.record_headers,
    reference_slots: index.indexed.reference_slots,
    scalar_words: index.indexed.scalar_words,
  })
  let transient_index = member_extent({
    record_headers: index.keys.record_headers +
    index.ancestry.record_headers +
    index.controls.record_headers,
    reference_slots: index.keys.reference_slots +
    index.ancestry.reference_slots +
    index.controls.reference_slots,
    scalar_words: index.keys.scalar_words +
    index.ancestry.scalar_words +
    index.controls.scalar_words,
  })
  // The emitted text and UTF8 input remain with read_member while read runs.
  // The byte decoder's own text dies when its parser call returns.
  let input = member_extent(
    { record_headers: 2L, reference_slots: 0L, scalar_words: 0L, },
    utf16=bytes.to_int64(),
    wire=bytes.to_int64(),
  )
  let parse_text = member_extent(
    { record_headers: 1L, reference_slots: 0L, scalar_words: 0L, },
    utf16=bytes.to_int64(),
  )
  let reference_retained = member_extent(
    reference.retained,
    utf16=reference.retained_utf16_units,
  )
  let contract_retained = member_extent(contract.retained)
  let schema_retained = member_extent(dense)
  // Source data for strings is counted once. With scores, the returned source
  // Cursor retains the index and original Spans as well; otherwise only typed
  // names/data Strings survive the byte reader.
  guard member_extent_sum([member_json_extent(borrowed), indexed])
    is Some(cursor) else {
    return None
  }
  let returned_source = if scores {
    member_extent_join(member_json_extent(returned_text), indexed).unwrap()
  } else {
    member_json_extent(returned_text)
  }
  // Snapshot1H7R2W + EnvironmentSnapshot1H2R. A materialization has its
  // record/Some and optional original binding-CID Some; no String copy.
  let result = member_extent({
    record_headers: 2L + (if material { 3L } else { 0L }),
    reference_slots: 9L + (if material { 4L } else { 0L }),
    scalar_words: 2L + (if material { 3L } else { 0L }),
  })
  let f = g.fields.to_int64()
  let score_retained = if scores {
    // Per entry: original Cursor1H2R1W, Score1H3R3W, pair1H2R;
    // source Cursor/Some2H3R2W and returned Array Some1H1R1W.
    member_extent(
      @shape.collection_construction_extent({
        records: 3L * f + 3L,
        record_references: 7L * f + 4L,
        record_words: 4L * f + 3L,
        reference_arrays: 1L,
        reference_items: f,
        scalar_arrays: 0L,
        scalar_items: 0L,
        maps: 0L,
        map_entries: 0L,
      }).unwrap(),
    )
  } else {
    zero
  }
  let selected_schema = if presence {
    member_extent(scoped.retained)
  } else {
    zero
  }
  guard member_extent_sum([
      reference_retained, contract_retained, schema_retained, selected_schema, score_retained,
      result,
    ])
    is Some(typed_returned) &&
    member_extent_join(returned_source, typed_returned) is Some(retained) else {
    return None
  }
  let emitted = @environment.member_text_emission_construction_extent(original)
  let observer = member_extent(member_emission_observation_extent())
  let mut peak = member_extent_max(selector, emitted)
  let parse_peak = member_extent_sum([
    input,
    parse_text,
    member_json_extent(parser),
  ]).unwrap()
  let index_peak = member_extent_sum([
    input,
    member_json_extent(tree),
    indexed,
    transient_index,
  ]).unwrap()
  let root_view = @decode.closed_object_field_construction_extent(
    Some(width),
    9,
    0L,
  ).unwrap()
  let root_held = member_extent(
    @decode.open_object_construction_extent(width).unwrap(),
  )
  let root_peak = member_extent_sum([input, cursor, member_extent(root_view)]).unwrap()
  let ref_peak = member_extent_sum([
    input,
    cursor,
    root_held,
    reference_retained,
    member_extent(reference.scratch, utf16=reference.scratch_utf16_units),
  ]).unwrap()
  let contract_peak = member_extent_sum([
    input,
    cursor,
    root_held,
    reference_retained,
    contract_retained,
    member_extent(contract.scratch, utf16=contract.scratch_utf16_units),
  ]).unwrap()
  for phase in [parse_peak, index_peak, root_peak, ref_peak, contract_peak] {
    peak = member_extent_max(peak, phase)
  }
  let presence_view = @decode.open_object_construction_extent(g.max_fields).unwrap()
  // These three arrays are original names, schema.fields and mapped input
  // tuples. Their element bodies borrow the already checked contracts/names.
  let presence_input = @shape.collection_construction_extent({
    records: 3L * f,
    record_references: 7L * f,
    record_words: 2L * f,
    reference_arrays: 3L,
    reference_items: 3L * f,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let schema_peak = member_extent_sum([
    input,
    cursor,
    reference_retained,
    contract_retained,
    schema_retained,
    root_held,
    member_extent(presence_view),
    member_extent(presence_input),
    member_extent(scoped.retained),
    member_extent(scoped.scratch, utf16=scoped.scratch_utf16_units),
  ]).unwrap()
  let score_view = @decode.closed_object_field_construction_extent(
    Some(g.max_fields),
    4,
    depth.to_int64(),
  ).unwrap()
  let score_peak = member_extent_sum([
    input,
    cursor,
    reference_retained,
    contract_retained,
    schema_retained,
    selected_schema,
    result,
    root_held,
    member_extent(score_view),
    score_retained,
  ]).unwrap()
  let hash_extent = member_extent(
    {
      record_headers: hash.record_headers,
      reference_slots: hash.reference_slots,
      scalar_words: hash.scalar_words,
    },
    utf16=hash.owned_utf16_units + 142L,
    wire=hash.owned_wire_bytes,
  )
  let hash_peak = member_extent_sum([
    input,
    cursor,
    typed_returned,
    root_held,
    member_extent(emitter),
    hash_extent,
  ]).unwrap()
  // Pending Snapshot1H7R2W; nine payload-bearing original helper/read/typed
  // failure alternatives9H9R9W; required/text/current-child6H6R6W; CID iterator
  //5H4R4W and score/presence iteration4H3R3W. Zero-payload tags are inline.
  let controls = member_extent({
    record_headers: 25L,
    reference_slots: 29L,
    scalar_words: 24L,
  })
  let path = member_extent(@decode.issue_construction_extent(depth).unwrap())
  let range_child = @decode.indexed_child_construction_extent()
  let field_child = @decode.indexed_field_construction_extent()
  // Two range positions and one selected field are transient. The stored
  // score cursor is already in score_retained, so only its other field
  // carriers are added here; the owner supplies their original quantities.
  let score_controls = member_extent({
    record_headers: 2L * range_child.record_headers +
    field_child.record_headers -
    1L,
    reference_slots: 2L * range_child.reference_slots +
    field_child.reference_slots -
    2L,
    scalar_words: 2L * range_child.scalar_words + field_child.scalar_words - 1L,
  })
  if presence {
    peak = member_extent_max(peak, schema_peak)
  }
  if scores {
    peak = member_extent_max(
      peak,
      member_extent_join(score_peak, score_controls).unwrap(),
    )
  }
  peak = member_extent_max(peak, hash_peak)
  Some({
    peak: member_extent_sum([peak, observer, controls, path]).unwrap(),
    retained,
    inspection_work: work,
  })
}

///|
/// Fixed DATA controls of one body inventory call, reused sequentially across
/// Members. Call-expanded families:25 collection/input quotes,62 member joins,
///19 other expanded adds,4 NFC quotes,2 key-admission quotes,3 Map quotes and
///5 key-count descriptors. Remaining returned/projection records,11 fixed sum
/// Arrays, active original field and scalar carriers are included once. No
/// input body, recursive VM/GC storage or physical allocation promise follows.
pub fn member_read_construction_inspection_extent() -> @shape.CollectionConstructionExtent {
  member_read_inspection_controls
}

///|
let member_read_inspection_controls : @shape.CollectionConstructionExtent = {
  record_headers: 1593L,
  reference_slots: 636L,
  scalar_words: 3760L,
}

///|
/// Ordered original Members are constructed serially; prior returned bodies
/// coexist with the next constructor. Only original private Local callers use
/// this DATA to reserve capacity; a caller Array is not an admission or grant.
pub fn member_batch_read_construction_inventory(
  originals : Array[@environment.Member],
) -> MemberReadConstructionInventory? {
  let zero = member_extent({
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
  })
  let mut retained = zero
  let mut peak = zero
  let mut work = 0L
  for original in originals {
    guard member_read_construction_inventory(original) is Some(one) &&
      member_extent_join(retained, one.peak) is Some(next_peak) &&
      member_extent_join(retained, one.retained) is Some(next_retained) &&
      @counts.checked_nonnegative_add_product(work, one.inspection_work, 1L)
      is Some(next_work) else {
      return None
    }
    peak = member_extent_max(peak, next_peak)
    retained = next_retained
    work = next_work
  }
  Some({ peak, retained, inspection_work: work, })
}
