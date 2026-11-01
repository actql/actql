///|
/// Bound the metadata walk on this read's SAME original Source. The caller
/// backs this bound/extent/borrowed frame before entry; this is not work credit.
pub fn source_registration_collection_inspection_bound(
  read : SourceRegistrationRead,
) -> Int64? {
  guard read.state is ReadDeclarations && read.arguments is Some(original) else {
    return None
  }
  Some(@source_inputs.collect_construction_inspection_bound(original.source))
}

///|
/// Observe once on the selected original Source and limits. A repeated borrow
/// returns the same completed work Option, not another input walk or debit.
/// No semantic collection, NFC normalization or Catalog selection runs here.
pub fn observe_source_registration_collection_construction(
  read : SourceRegistrationRead,
) -> Int64? {
  guard read.state is ReadDeclarations && read.arguments is Some(original) else {
    return None
  }
  if read.collection_construction is Some(completed) {
    return completed.work
  }
  let geometry = @source_inputs.observe_collect_construction_geometry(
    original.source,
    {
      max_work: original.limits.max_work,
      max_order_keys: original.max_order_keys,
    },
  )
  let work = Some(geometry.inspection_work)
  read.collection_construction = Some({ geometry, work, })
  work
}

///|
pub fn source_registration_collection_inspection_work(
  read : SourceRegistrationRead,
) -> Int64? {
  match read.collection_construction {
    None => None
    Some(completed) => completed.work
  }
}

///|
/// The original semantic collection budget, separate from metadata visits.
/// Only the original collector reports how much of this envelope it consumed.
pub fn source_registration_collection_work_bound(
  read : SourceRegistrationRead,
) -> Int? {
  guard read.state is ReadDeclarations && read.arguments is Some(original) else {
    return None
  }
  Some(original.limits.max_work)
}

///|
/// Only the original read's completed metadata can quote its constructor.
/// No caller replacement Source, geometry, limit or admission verdict enters.
/// Quote/observer/result controls and outside backing remain distinct duties.
pub fn source_registration_collection_construction(
  read : SourceRegistrationRead,
) -> @source_inputs.CollectionConstructionInventory? {
  guard read.state is ReadDeclarations &&
    read.arguments is Some(original) &&
    read.collection_construction is Some(completed) else {
    return None
  }
  @source_inputs.collect_construction_inventory(completed.geometry, {
    max_work: original.limits.max_work,
    max_order_keys: original.max_order_keys,
  })
}

///|
/// Cache wrapper1H2R, work Some1H2W, stored Some1H1R1W, selected Limits1H2W
/// and bound Some1H2W. The original metadata owner supplies its whole peak.
pub fn source_registration_collection_inspection_extent() -> @shape.CollectionConstructionExtent {
  @shape.add_collection_construction_extents(
    @source_inputs.collect_construction_inspection_extent(),
    { record_headers: 5L, reference_slots: 3L, scalar_words: 7L, },
  ).unwrap()
}

///|
pub fn source_registration_collection_inspection_retained_extent() -> @shape.CollectionConstructionExtent {
  @shape.add_collection_construction_extents(
    @source_inputs.collect_construction_geometry_extent(),
    { record_headers: 3L, reference_slots: 3L, scalar_words: 3L, },
  ).unwrap()
}

///|
/// Existing collection quotation plus this read's selected Limits1H2W only.
/// This does not price the described Inputs, normalized text or constructor.
pub fn source_registration_collection_quotation_extent() -> @shape.CollectionConstructionExtent {
  let original = @source_inputs.collect_construction_quotation_extent()
  {
    record_headers: original.record_headers + 1L,
    reference_slots: original.reference_slots,
    scalar_words: original.scalar_words + 2L,
  }
}

///|
// SAME observe_collect controls3H2R3W, selected Limits1H2W, success Some1H1R1W
// and failure Declarations/Err/RegistrationDone3H3R3W. Co-count alternatives;
// the collector itself owns all Inputs/NFC/order/issue bodies separately.
let source_collection_driver_extent : @shape.CollectionConstructionExtent = {
  record_headers: 8L,
  reference_slots: 6L,
  scalar_words: 9L,
}

///|
let source_collection_driver_retained_extent : @shape.CollectionConstructionExtent = {
  record_headers: 1L,
  reference_slots: 1L,
  scalar_words: 1L,
}

///|
pub fn source_registration_collection_driver_extent() -> @shape.CollectionConstructionExtent {
  source_collection_driver_extent
}

///|
/// Success retains the original collected Inputs Option. A failed reader's
/// issue backing is not covered by this success-only retirement projection.
pub fn source_registration_collection_driver_retained_extent() -> @shape.CollectionConstructionExtent {
  source_collection_driver_retained_extent
}
