///|
// Actual entry constructors: compile_source_limits14H13R61W, simultaneous
// remaining-budget projection11H12R50W, declaration limits1H4W, original reuse
// Some1H1R1W, registration limits1H4W, Catalog/reference tuples2H5R,
// continuation1H8R2W, returned Ok1H1R1W and typed failure alternatives3H3R3W.
// The registration owner supplies its own constructor packet. Original Source,
// declarations, Program, Catalog and all body backing are borrowed, not copied.
let parsed_source_registration_entry_peak : @shape.CollectionConstructionExtent = {
  let read = @context.source_registration_initial_construction_extent()
  {
    record_headers: 35L + read.record_headers,
    reference_slots: 43L + read.reference_slots,
    scalar_words: 126L + read.scalar_words,
  }
}

///|
// After return: selected limits14H13R61W (including three shared inner records
// from the first projection), registration limits1H4W, the original read's
// owner-supplied retained packet, and continuation1H8R2W. Old checker/Catalog controls and
// Source bodies remain on their original charged parent and are not subtracted.
let parsed_source_registration_entry_retained : @shape.CollectionConstructionExtent = {
  let read = @context.source_registration_retained_construction_extent()
  {
    record_headers: 16L + read.record_headers,
    reference_slots: 21L + read.reference_slots,
    scalar_words: 67L + read.scalar_words,
  }
}

///|
/// Installed logical entry DATA, never a physical grant or semantic limit.
/// Caller quote/current/resize frames must already be backed before this read.
pub fn parsed_source_registration_entry_extent() -> @shape.CollectionConstructionExtent {
  parsed_source_registration_entry_peak
}

///|
pub fn parsed_source_registration_retained_extent() -> @shape.CollectionConstructionExtent {
  parsed_source_registration_entry_retained
}
