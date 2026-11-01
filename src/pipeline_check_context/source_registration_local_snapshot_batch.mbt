///|
pub fn source_registration_local_snapshot_batch_inspection_bound(
  read : SourceRegistrationRead,
) -> Int64? {
  read.local_child.bind(
    @local_inputs.local_environment_snapshot_batch_inspection_bound,
  )
}

///|
pub fn source_registration_local_snapshot_batch_inspection_extent(
  read : SourceRegistrationRead,
) -> @shape.CollectionConstructionExtent? {
  read.local_child.bind(
    @local_inputs.local_environment_snapshot_batch_inspection_extent,
  )
}

///|
pub fn source_registration_local_snapshot_batch_retained_extent(
  read : SourceRegistrationRead,
) -> @shape.CollectionConstructionExtent? {
  read.local_child.bind(
    @local_inputs.local_environment_snapshot_batch_retained_extent,
  )
}

///|
pub fn observe_source_registration_local_snapshot_batch_construction(
  read : SourceRegistrationRead,
) -> @snapshot.MemberReadConstructionInventory? {
  read.local_child.bind(
    @local_inputs.observe_local_environment_snapshot_batch_construction,
  )
}

///|
pub fn source_registration_local_snapshot_batch_body_construction(
  read : SourceRegistrationRead,
) -> @snapshot.MemberReadConstructionInventory? {
  read.local_child.bind(
    @local_inputs.local_environment_snapshot_batch_body_construction,
  )
}
