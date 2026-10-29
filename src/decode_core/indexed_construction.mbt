///|
/// Actual retained Cursor only: tree/usage2R and index1W. Its original tree,
/// strings and admission fact stay borrowed; this wrapper grants no authority.
pub fn cursor_construction_extent() -> @shape.CollectionConstructionExtent {
  cursor_controls
}

///|
let cursor_controls : @shape.CollectionConstructionExtent = {
  record_headers: 1L,
  reference_slots: 2L,
  scalar_words: 1L,
}

///|
/// Logical boxed upper bound shared by lookup and element_at: original Int
/// Some, original-cursor closure, child Cursor and returned Some. Its4W are
/// original Int payload1, Cursor index1 and BOTH Option tags2. Specialized
/// targets can erase carriers. Original tree/usage backing stays borrowed;
/// this descriptor is not an allocation, tariff, verdict or physical supply.
pub fn indexed_child_construction_extent() -> @shape.CollectionConstructionExtent {
  indexed_child_controls
}

///|
let indexed_child_controls : @shape.CollectionConstructionExtent = {
  record_headers: cursor_controls.record_headers + 3L,
  reference_slots: cursor_controls.reference_slots + 2L,
  scalar_words: cursor_controls.scalar_words + 3L,
}

///|
/// Original field option, closure, child Cursor, pair and returned option.
/// Its3W are Cursor index1 plus BOTH Option tags2. Original Key/String and
/// admitted tree backing stay borrowed. This is the SAME
/// field_at constructor inventory, not a second collection or tariff rule.
pub fn indexed_field_construction_extent() -> @shape.CollectionConstructionExtent {
  indexed_field_controls
}

///|
let indexed_field_controls : @shape.CollectionConstructionExtent = {
  record_headers: cursor_controls.record_headers + 4L,
  reference_slots: cursor_controls.reference_slots + 5L,
  scalar_words: cursor_controls.scalar_words + 2L,
}
