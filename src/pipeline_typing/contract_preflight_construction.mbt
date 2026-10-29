///|
// Contract read1H5R6W, two borrowed optional roots2H2R2W, parent Some1H1R1W.
// The Array and each still referenced original (Contract,depth) tuple are below.
let contract_preflight_controls : @shape.CollectionConstructionExtent = {
  record_headers: 4L,
  reference_slots: 8L,
  scalar_words: 9L,
}

///|
fn contract_preflight_retained(
  read : ContractPreflightRead,
) -> @shape.CollectionConstructionExtent? {
  guard @shape.reference_array_retained_extent(
      1L,
      read.work.capacity().to_int64(),
    )
    is Some(array) &&
    @shape.scale_collection_construction_extent(
      { record_headers: 1L, reference_slots: 1L, scalar_words: 1L, },
      read.retained_tuples.to_int64(),
    )
    is Some(tuples) else {
    return None
  }
  @shape.compose_collection_construction_extents([
    contract_preflight_controls, array, tuples,
  ])
}

///|
fn contract_preflight_entry_construction() -> @shape.CollectionConstructionExtent? {
  guard @shape.collection_construction_extent({
      records: 1L,
      record_references: 1L,
      record_words: 1L,
      reference_arrays: 1L,
      reference_items: 1L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(stack) else {
    return None
  }
  @shape.add_collection_construction_extents(contract_preflight_controls, stack)
}

///|
fn contract_preflight_push_construction(
  read : ContractPreflightRead,
) -> @shape.CollectionConstructionExtent? {
  if !(read.step is PushArray || read.step is PushField) {
    return Some(pipeline_core_zero_extent)
  }
  guard @shape.reference_array_push_construction_extent(
      read.work.length(),
      read.work.capacity(),
    )
    is Some(backing) else {
    return None
  }
  @shape.add_collection_construction_extents(backing, {
    record_headers: 1L,
    reference_slots: 1L,
    scalar_words: 1L,
  })
}
