///|
/// Original Source input construction lifetimes. These DATA quantities do not
/// admit a name/key/score or infer runtime uniqueness, permission or currentness.
pub(all) struct SourceInputConstructionInventory {
  retained : @shape.CollectionConstructionExtent
  scratch : @shape.CollectionConstructionExtent
  retained_utf16_units : Int64
  scratch_utf16_units : Int64
  inspection_work : Int64
} derive(Eq, Debug)

///|
let source_input_zero : @shape.CollectionConstructionExtent = {
  record_headers: 0L,
  reference_slots: 0L,
  scalar_words: 0L,
}

///|
fn source_input_max_extent(
  a : @shape.CollectionConstructionExtent,
  b : @shape.CollectionConstructionExtent,
) -> @shape.CollectionConstructionExtent {
  {
    record_headers: Int64::max(a.record_headers, b.record_headers),
    reference_slots: Int64::max(a.reference_slots, b.reference_slots),
    scalar_words: Int64::max(a.scalar_words, b.scalar_words),
  }
}

///|
fn source_input_array_construction(
  n : Int64,
) -> @shape.CollectionConstructionExtent? {
  @shape.collection_construction_extent({
    records: 0L,
    record_references: 0L,
    record_words: 0L,
    reference_arrays: 1L,
    reference_items: n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  })
}

///|
/// Uses the original admitted tuple's cached width/name length. The SAME
/// admitted arena depth bounds a failed child path; no ancestry/name scan is
/// repeated. Each key reader is sequential: sum its held output, max scratch.
pub fn source_view_key_construction_inventory(
  view : @model_environment.SourceViewCarrier,
) -> SourceInputConstructionInventory? {
  guard @model_environment.source_view_relation_keys(view) is Some(keys) else {
    return Some({
      retained: source_input_zero,
      scratch: { record_headers: 1L, reference_slots: 0L, scalar_words: 1L, },
      retained_utf16_units: 0L,
      scratch_utf16_units: 0L,
      inspection_work: 1L,
    })
  }
  let count = @model_environment.source_relation_key_count(keys)
  let mut retained = source_input_zero
  let mut scratch = source_input_zero
  let mut text = 0L
  let mut work = 1L
  for index in 0..<count {
    guard @model_environment.source_relation_key_at(keys, index) is Some(source) &&
      @model_environment.source_relation_key_construction_geometry(keys, index)
      is Some((fields, name_units)) &&
      primary_key_read_construction_inventory(
        fields,
        name_units,
        @decode.admission_usage(source).depth.to_int64(),
      )
      is Some(q) &&
      @shape.add_collection_construction_extents(retained, q.retained)
      is Some(next) else {
      return None
    }
    work += 3L
    retained = next
    scratch = source_input_max_extent(scratch, q.scratch)
    text = Int64::max(text, q.scratch_utf16_units)
  }
  guard source_input_array_construction(count.to_int64()) is Some(array) &&
    @shape.compose_collection_construction_extents([
      retained,
      array,
      // Final original KeySet. Its witnesses are the SAME original keys.
      { record_headers: 1L, reference_slots: 2L, scalar_words: 2L, },
    ])
    is Some(retained) &&
    @shape.compose_collection_construction_extents([
      scratch,
      array,
      // Sequential source/collect budgets/limits, original lookup/usage/
      // UTF8/issue/Result/transfer alternatives. The first witnesses Array
      // overlaps its final copy; no key/name/schema body is rebuilt here.
      { record_headers: 20L, reference_slots: 20L, scalar_words: 32L, },
    ])
    is Some(scratch) else {
    return None
  }
  Some({
    retained,
    scratch,
    retained_utf16_units: 0L,
    scratch_utf16_units: text,
    inspection_work: work,
  })
}

///|
/// Observe only this selected original score map. Existing original score
/// admission still executes once. Its owned u:-key Strings use actual names;
/// unrelated Catalog bodies and configured depth/node limits are not demand.
pub fn source_view_ranking_construction_inventory(
  view : @model_environment.SourceViewCarrier,
) -> SourceInputConstructionInventory? {
  guard @model_environment.source_view_relation_scores(view) is Some(scores) else {
    return Some({
      retained: source_input_zero,
      scratch: { record_headers: 1L, reference_slots: 0L, scalar_words: 1L, },
      retained_utf16_units: 0L,
      scratch_utf16_units: 0L,
      inspection_work: 1L,
    })
  }
  let source = @model_environment.source_relation_scores_source(scores)
  let geometry = @decode.observe_subtree_geometry(source, [])
  let count = @decode.object_length(source).unwrap()
  let mut total = 0L
  let mut largest = 0
  let mut work = 1L + geometry.work
  for index in 0..<count {
    let (name, _) = @decode.field_at(source, index).unwrap()
    total += name.length().to_int64()
    largest = Int::max(largest, name.length())
    work += 2L
  }
  ranking_scores_construction_inventory(geometry, count, total, largest).map(q => {
    retained: q.retained,
    scratch: q.scratch,
    retained_utf16_units: q.retained_utf16_units,
    scratch_utf16_units: q.scratch_utf16_units,
    inspection_work: work,
  })
}
