///|
/// Original Stage-registration constructor DATA. Input/Catalog/carrier/text
/// backing stays borrowed from the SAME retained Resolved. These extents are
/// construction peaks, not minimum storage, byte capacity or semantic success.
pub(all) struct PipelinePreparationConstruction {
  returned : @shape.CollectionConstructionExtent
  temporary : @shape.CollectionConstructionExtent
} derive(Eq, Debug)

///|
/// The original constructor charges inherited work, Stage count and entry
/// count BEFORE allocating any group. Quote that SAME prefix, then all actual
/// group/entry multiplicities without another name/Source/Catalog walk.
/// The quotation call frame and returned original Result/work pair are separate.
pub fn pipeline_preparation_construction(
  resolved : Resolved,
  max_work : Int,
) -> PipelinePreparationConstruction? {
  let early : @shape.CollectionConstructionExtent = {
    record_headers: 2L,
    reference_slots: 1L,
    scalar_words: 2L,
  }
  let zero : @shape.CollectionConstructionExtent = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
  }
  if max_work < 0 {
    return Some({ returned: early, temporary: zero, })
  }
  let stages = @stages.stage_count(@inputs.source(resolved.owner.inputs))
  let entries = resolved.entries.length()
  // The actual three-cost Array exists before a prefix refusal. Its scalar
  // backing uses the same shared growing-Array representation as execution.
  guard @shape.collection_construction_extent({
      records: 0L,
      record_references: 0L,
      record_words: 0L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 1L,
      scalar_items: 3L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(prefix_frame) else {
    return None
  }
  let mut remaining = max_work
  for cost in pipeline_preparation_prefix_costs(resolved, stages) {
    if cost > remaining {
      return Some({ returned: early, temporary: prefix_frame, })
    }
    remaining -= cost
  }
  let s = stages.to_int64()
  let n = entries.to_int64()
  // PipelineInputs1H2R1W + Ok1H1R1W. PipelineEntry1H2R per selected
  // occurrence, the outer array and every actual Stage group coexist. The
  // original error/flat-kind alternative2H1R2W is conservatively co-counted.
  // A name-work refusal may leave any prefix of entries, never fewer groups.
  guard @shape.collection_construction_extent({
      records: 4L + n,
      record_references: 4L + 2L * n,
      record_words: 4L,
      reference_arrays: 1L + s,
      reference_items: s + n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(returned) else {
    return None
  }
  // Noncapturing makei callback1H. Carrier lookup borrows an existing token,
  // with at most one live Some1H1R1W; no carrier/schema is reconstructed.
  let carrier : @shape.CollectionConstructionExtent = if entries == 0 {
    { record_headers: 1L, reference_slots: 0L, scalar_words: 0L, }
  } else {
    { record_headers: 2L, reference_slots: 1L, scalar_words: 1L, }
  }
  guard @shape.add_collection_construction_extents(prefix_frame, carrier)
    is Some(temporary) else {
    return None
  }
  Some({ returned, temporary, })
}
