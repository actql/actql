///|
/// Work bound from the SAME limits captured before the original index grow.
/// No caller-supplied replacement, second metadata walk or new allowance.
pub fn local_environment_index_work_bound(
  read : LocalEnvironmentPreparation,
) -> Int? {
  guard read.state is ReadIndex && read.index_construction is Some(original) else {
    return None
  }
  Some(original.limits.max_work)
}

///|
// Additional Local index carriers: usage/index Some2H2R2W and next phase1H1W;
// failure Index/failed-phase/Some/LocalDone/Err/returned-phase6H4R6W.
// The index owner supplies its own original observation. Failed usage is
// retained; later member/declaration work is neither known nor replaced by0.
let local_index_driver_units : @shape.CollectionConstructionExtent = {
  let original = @refs.index_preparation_observation_control_extent()
  {
    record_headers: original.record_headers + 9L,
    reference_slots: original.reference_slots + 6L,
    scalar_words: original.scalar_words + 9L,
  }
}

///|
let local_index_driver_retained_units : @shape.CollectionConstructionExtent = {
  record_headers: 3L,
  reference_slots: 2L,
  scalar_words: 3L,
}

///|
pub fn local_environment_index_driver_extent() -> @shape.CollectionConstructionExtent {
  local_index_driver_units
}

///|
pub fn local_environment_index_driver_retained_extent() -> @shape.CollectionConstructionExtent {
  local_index_driver_retained_units
}

///|
pub fn local_environment_index_quotation_extent() -> @shape.CollectionConstructionExtent {
  @refs.index_construction_quotation_extent()
}
