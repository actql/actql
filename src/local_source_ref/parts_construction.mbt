///|
/// The actual split output family only: at most the complete original format
/// plus its one refusal component. StringViews borrow the original input;
/// iteration/UTF8/untoken/NFC/token/Reference and VM frames remain separate.
/// This is DATA for shared pricing, not a byte tariff or admission verdict.
pub fn reference_parts_construction_extent() -> @shape.CollectionConstructionExtent {
  reference_parts_units
}

///|
let reference_parts_units : @shape.CollectionConstructionExtent = {
  let parts = (reference_component_count + 1).to_int64()
  @shape.collection_construction_extent({
    records: parts,
    record_references: parts,
    record_words: 2L * parts,
    reference_arrays: 1L,
    reference_items: parts,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
}
