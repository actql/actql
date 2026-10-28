///|
/// Original newly constructed input evidence holdings, not evidence validity,
/// a Resource grant or physical release. Work counts buffer/container visits.
pub(all) struct InputEvidenceRetainedConstruction {
  extent : @shape.CollectionConstructionExtent
  owned_utf16_units : Int64
  observation_work : Int64
} derive(Eq, Debug)

///|
/// Only the KeySet container is new for singleton_key; its original witness
/// remains borrowed. This same helper supplies the Source collection container.
pub fn key_set_container_retained_extent(
  original : KeySet,
) -> @shape.CollectionConstructionExtent? {
  @shape.reference_array_retained_extent(
    1L,
    original.witnesses.capacity().to_int64(),
  ).bind(array => {
    @shape.add_collection_construction_extents(array, {
      record_headers: 1L,
      reference_slots: 2L,
      scalar_words: 2L,
    })
  })
}

///|
/// Actual output of source_view_keys: its SAME new declaration witnesses,
/// aliased fields and array buffers. No strings/schema are scanned or copied.
pub fn source_key_set_retained_construction(
  original : KeySet,
) -> InputEvidenceRetainedConstruction? {
  guard key_set_container_retained_extent(original) is Some(container) else {
    return None
  }
  let mut held = container
  let mut work = 1L
  for key in original.witnesses {
    work += 1L
    // This is storage identity, not repeated semantic key admission. Source
    // declaration fields/declared_fields share exactly one original buffer.
    guard physical_equal(key.fields, key.declared_fields) else { return None }
    let mut alias_slots = 0L
    for aliases in key.aliases {
      work += 1L
      alias_slots += aliases.capacity().to_int64()
    }
    let n = key.fields.length().to_int64()
    guard @shape.reference_array_retained_extent(
        2L + key.aliases.length().to_int64(),
        key.fields.capacity().to_int64() +
        key.aliases.capacity().to_int64() +
        alias_slots,
      )
      is Some(arrays) &&
      @shape.scale_collection_construction_extent(
        { record_headers: 2L, reference_slots: 4L, scalar_words: 1L, },
        n,
      )
      is Some(fields) &&
      @shape.compose_collection_construction_extents([
        held,
        arrays,
        fields,
        // Original KeyedRelation1H8R1W and Usage1H2W.
        { record_headers: 2L, reference_slots: 8L, scalar_words: 3L, },
      ])
      is Some(next) else {
      return None
    }
    held = next
  }
  Some({ extent: held, owned_utf16_units: 0L, observation_work: work, })
}

///|
/// Newly constructed source_view_scores output only. Original name/source/
/// schema backing remains borrowed; actual u:-prefixed Map keys are owned.
pub fn source_ranking_retained_construction(
  original : RankingInput,
) -> InputEvidenceRetainedConstruction? {
  guard @shape.map_retained_extent(
      1L,
      original.tuples.capacity().to_int64(),
      original.tuples.length().to_int64(),
    )
    is Some(tuples) &&
    @shape.map_retained_extent(
      1L,
      original.score_aliases.capacity().to_int64(),
      original.score_aliases.length().to_int64(),
    )
    is Some(scores) &&
    @shape.scale_collection_construction_extent(
      // Cursor1H2R1W, DeclaredScore1H5R, ScoreContract1H2R2W,
      // Usage1H3W and original Unqualified field1H1R1W.
      { record_headers: 5L, reference_slots: 10L, scalar_words: 7L, },
      original.score_aliases.length().to_int64(),
    )
    is Some(declarations) else {
    return None
  }
  let mut text = 0L
  let mut work = 1L
  for name, _ in original.score_aliases {
    text += name.length().to_int64()
    work += 1L
  }
  let sole = if original.score_declaration is Some(_) { 1L } else { 0L }
  @shape.compose_collection_construction_extents([
    tuples,
    scores,
    declarations,
    {
      record_headers: 1L + sole,
      reference_slots: 7L + sole,
      scalar_words: sole,
    },
  ]).map(extent => { extent, owned_utf16_units: text, observation_work: work, })
}
