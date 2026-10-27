///|
/// member_at's entry Some, captured lookup closure and returned Some, excluding
/// the Member itself. Closure captures original owner, section and index; only
/// owner is a reference. Consumer inventories own each retained Member record.
pub fn member_access_construction_extent() -> @shape.CollectionConstructionExtent {
  member_access_controls
}

///|
let member_access_controls : @shape.CollectionConstructionExtent = {
  record_headers: 3L,
  reference_slots: 3L,
  scalar_words: 2L,
}
