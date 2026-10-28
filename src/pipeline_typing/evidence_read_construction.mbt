///|
/// Original retained compiler controls only, not schema/keys/ranking/core
/// bodies, an allowance, tariff or physical first-prelude. Read1H1R;
/// body1H10R4W; Reading1H1R1W; two overlapping phase alternatives2H6R2W;
/// four entry/advance/take Result/Option alternatives4H4R7W.
pub fn pipeline_evidence_read_control_construction_extent() -> @shape.CollectionConstructionExtent {
  { record_headers: 9L, reference_slots: 22L, scalar_words: 14L, }
}

///|
/// Read/body/Reading/selected phase4H15R6W. Phase storage uses its maximum
/// original three-reference payload, including before those slots are filled.
pub fn pipeline_evidence_read_control_retained_extent() -> @shape.CollectionConstructionExtent {
  { record_headers: 4L, reference_slots: 15L, scalar_words: 6L, }
}

///|
/// The actual original map borrows every input name, complete schema and
/// producer. Each tuple is new; only Keyed/CandidateKeys add Relation variants.
/// Before that constructor, the same original input count bounds both branches.
pub fn pipeline_evidence_read_step_construction(
  original : PipelineEvidenceRead,
) -> @shape.CollectionConstructionExtent? {
  guard original.state is Reading(body) && body.step is Carriers else {
    return None
  }
  let n = body.inputs.length().to_int64()
  guard @shape.collection_construction_extent({
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
    is Some(array) &&
    @shape.scale_collection_construction_extent(
      { record_headers: 2L, reference_slots: 3L, scalar_words: 1L, },
      n,
    )
    is Some(entries) else {
    return None
  }
  // map/constructor closure2H2R; next phase1H1R1W; original input/owner/
  // knowledge access alternatives3H5R4W; returned phase/Result2H2R5W.
  @shape.compose_collection_construction_extents([
    array,
    entries,
    { record_headers: 8L, reference_slots: 10L, scalar_words: 10L, },
  ])
}

///|
/// Observe actual retained buffer capacity and the constructor's own wrapper
/// count. No second carrier/schema traversal, clone, key admission or text scan.
/// This is only the new carrier delta; fixed reader controls stay with parent.
pub fn pipeline_evidence_read_carriers_retained_extent(
  original : PipelineEvidenceRead,
) -> @shape.CollectionConstructionExtent? {
  guard original.state is Reading(body) && body.step is Keys(carriers) else {
    return None
  }
  guard @shape.reference_array_retained_extent(
      1L,
      carriers.capacity().to_int64(),
    )
    is Some(array) &&
    @shape.scale_collection_construction_extent(
      { record_headers: 1L, reference_slots: 2L, scalar_words: 0L, },
      carriers.length().to_int64(),
    )
    is Some(tuples) &&
    @shape.scale_collection_construction_extent(
      { record_headers: 1L, reference_slots: 1L, scalar_words: 1L, },
      body.carrier_wrappers.to_int64(),
    )
    is Some(wrappers) else {
    return None
  }
  @shape.compose_collection_construction_extents([array, tuples, wrappers])
}
