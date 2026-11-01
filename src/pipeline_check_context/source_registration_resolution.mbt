///|
/// Original selection work envelope AFTER the completed collection prefix.
/// The resolver owns this convention; the caller records only its new work.
pub fn source_registration_resolution_work_bound(
  read : SourceRegistrationRead,
) -> Int? {
  guard read.state is SelectDeclarations &&
    read.arguments is Some(original) &&
    read.collected is Some(inputs) else {
    return None
  }
  Some(@sourceviews.resolution_work_bound(inputs, original.limits.max_work))
}

///|
pub fn source_registration_resolution_quotation_extent() -> @shape.CollectionConstructionExtent {
  let original = @sourceviews.resolution_construction_quotation_extent()
  {
    record_headers: original.record_headers + 1L,
    reference_slots: original.reference_slots,
    scalar_words: original.scalar_words + 3L,
  }
}

///|
// Original observation3H2R3W, selected Limits1H3W, success BuildRegistrations
//1H1R1W and failure Selection/Err/RegistrationDone3H3R3W. The resolver owns
// all Resolved/NFC/URI/issue backing; the read only owns these wrappers.
let source_resolution_driver_extent : @shape.CollectionConstructionExtent = {
  record_headers: 8L,
  reference_slots: 6L,
  scalar_words: 10L,
}

///|
let source_resolution_driver_retained_extent : @shape.CollectionConstructionExtent = {
  record_headers: 1L,
  reference_slots: 1L,
  scalar_words: 1L,
}

///|
pub fn source_registration_resolution_driver_extent() -> @shape.CollectionConstructionExtent {
  source_resolution_driver_extent
}

///|
pub fn source_registration_resolution_driver_retained_extent() -> @shape.CollectionConstructionExtent {
  source_resolution_driver_retained_extent
}
