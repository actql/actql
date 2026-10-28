///|
pub fn source_registration_local_snapshot_inspection_extent() -> @shape.CollectionConstructionExtent {
  @local_inputs.local_environment_snapshot_construction_inspection_extent()
}

///|
pub fn source_registration_local_snapshot_inspection_retained_extent() -> @shape.CollectionConstructionExtent {
  @local_inputs.local_environment_snapshot_construction_retained_extent()
}

///|
pub fn source_registration_local_snapshot_limits(
  read : SourceRegistrationRead,
) -> @snapshot.Limits? {
  read.local_child.bind(
    @local_inputs.local_environment_snapshot_construction_limits,
  )
}

///|
/// Actual Local max_work debit of the last attempted member. Retained through
/// take/clear; no parse/schema work or writer measurement is substituted.
pub fn source_registration_local_snapshot_work(
  read : SourceRegistrationRead,
) -> Int? {
  read.local_snapshot_work
}

///|
pub fn source_registration_local_snapshots_work_bound(
  read : SourceRegistrationRead,
) -> Int? {
  read.local_child.bind(@local_inputs.local_environment_snapshots_work_bound)
}

///|
pub fn source_registration_local_snapshot_work_observation_extent() -> @shape.CollectionConstructionExtent {
  @local_inputs.local_environment_snapshot_work_observation_extent()
}

///|
/// SAME captured Member quantity; not a selector verdict or body permission.
pub fn source_registration_local_snapshot_selector_construction(
  read : SourceRegistrationRead,
) -> @shape.CollectionConstructionExtent? {
  read.local_child.bind(
    @local_inputs.local_environment_snapshot_selector_construction,
  )
}

///|
pub fn source_registration_local_snapshot_reference_inspection_bound(
  read : SourceRegistrationRead,
) -> Int64? {
  read.local_child.bind(
    @local_inputs.local_environment_snapshot_reference_inspection_bound,
  )
}

///|
pub fn observe_source_registration_local_snapshot_reference_construction(
  read : SourceRegistrationRead,
) -> (@local_ref.ReferenceReadConstructionInventory?, Int64)? {
  read.local_child.bind(
    @local_inputs.observe_local_environment_snapshot_reference_construction,
  )
}

///|
pub fn source_registration_local_snapshot_reference_construction(
  read : SourceRegistrationRead,
) -> (@local_ref.ReferenceReadConstructionInventory?, Int64)? {
  read.local_child.bind(
    @local_inputs.local_environment_snapshot_reference_construction,
  )
}

///|
pub fn source_registration_local_snapshot_reference_inspection_extent() -> @shape.CollectionConstructionExtent {
  @local_inputs.local_environment_snapshot_reference_inspection_extent()
}

///|
pub fn source_registration_local_snapshot_reference_retained_extent() -> @shape.CollectionConstructionExtent {
  @local_inputs.local_environment_snapshot_reference_retained_extent()
}
