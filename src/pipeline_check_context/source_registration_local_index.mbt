///|
/// The SAME private Local child and its originally captured index limits.
pub fn source_registration_local_index_work_bound(
  read : SourceRegistrationRead,
) -> Int? {
  read.local_child.bind(@local_inputs.local_environment_index_work_bound)
}

///|
pub fn source_registration_local_index_inspection_extent() -> @shape.CollectionConstructionExtent {
  @local_inputs.local_environment_index_inspection_extent()
}

///|
pub fn source_registration_local_index_inspection_retained_extent() -> @shape.CollectionConstructionExtent {
  @local_inputs.local_environment_index_inspection_retained_extent()
}

///|
// On failed Index, the SAME child result is taken by the existing Source
// reader: take Some/LocalHandedOff/LocalInputs/Err/RegistrationDone5H4R5W.
// No new successful carrier is constructed: the original Usage Some is
// forwarded unchanged to this read before the child can be taken or cleared.
let source_local_index_driver_units : @shape.CollectionConstructionExtent = {
  let original = @local_inputs.local_environment_index_driver_extent()
  {
    record_headers: original.record_headers + 5L,
    reference_slots: original.reference_slots + 4L,
    scalar_words: original.scalar_words + 5L,
  }
}

///|
pub fn source_registration_local_index_driver_extent() -> @shape.CollectionConstructionExtent {
  source_local_index_driver_units
}

///|
pub fn source_registration_local_index_driver_retained_extent() -> @shape.CollectionConstructionExtent {
  @local_inputs.local_environment_index_driver_retained_extent()
}

///|
pub fn source_registration_local_index_quotation_extent() -> @shape.CollectionConstructionExtent {
  @local_inputs.local_environment_index_quotation_extent()
}
