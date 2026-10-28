///|
pub fn source_registration_local_groups_work_bound(
  read : SourceRegistrationRead,
) -> Int? {
  read.local_child.bind(@local_inputs.local_environment_groups_work_bound)
}

///|
// Same failure forwarding as Index: take Some/LocalHandedOff/LocalInputs/
// Err/RegistrationDone5H4R5W. No successful body is copied here.
let source_local_groups_driver_units : @shape.CollectionConstructionExtent = {
  let original = @local_inputs.local_environment_groups_driver_extent()
  {
    record_headers: original.record_headers + 5L,
    reference_slots: original.reference_slots + 4L,
    scalar_words: original.scalar_words + 5L,
  }
}

///|
pub fn source_registration_local_groups_driver_extent() -> @shape.CollectionConstructionExtent {
  source_local_groups_driver_units
}

///|
pub fn source_registration_local_groups_quotation_extent() -> @shape.CollectionConstructionExtent {
  @local_inputs.local_environment_groups_quotation_extent()
}
