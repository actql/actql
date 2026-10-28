///|
/// Original remaining Local constructor Usage only. None keeps missing failed
/// nested work distinct from zero. This scalar fact survives Source take/clear;
/// it never grants capacity, refunds prior work or acknowledges physical stop.
pub fn source_registration_local_tail_work(
  read : SourceRegistrationRead,
) -> Int? {
  read.local_tail_work
}

///|
pub fn source_registration_local_tail_work_bound(
  read : SourceRegistrationRead,
) -> Int? {
  read.local_child.bind(@local_inputs.local_environment_tail_work_bound)
}

///|
pub fn source_registration_local_tail_work_observation_extent() -> @shape.CollectionConstructionExtent {
  @local_inputs.local_environment_tail_work_observation_extent()
}

///|
pub fn source_registration_local_tail_inspection_bound(
  read : SourceRegistrationRead,
) -> Int64? {
  read.local_child.bind(@local_inputs.local_environment_tail_inspection_bound)
}

///|
pub fn source_registration_local_tail_inspection_extent(
  read : SourceRegistrationRead,
) -> @shape.CollectionConstructionExtent? {
  read.local_child.bind(@local_inputs.local_environment_tail_inspection_extent)
}

///|
pub fn source_registration_local_tail_inspection_retained_extent() -> @shape.CollectionConstructionExtent {
  @local_inputs.local_environment_tail_inspection_retained_extent()
}

///|
pub fn observe_source_registration_local_tail_construction(
  read : SourceRegistrationRead,
) -> @local_inputs.LocalCompletionConstructionInventory? {
  read.local_child.bind(
    @local_inputs.observe_local_environment_tail_construction,
  )
}

///|
pub fn source_registration_local_tail_construction(
  read : SourceRegistrationRead,
) -> @local_inputs.LocalCompletionConstructionInventory? {
  read.local_child.bind(@local_inputs.local_environment_tail_construction)
}
