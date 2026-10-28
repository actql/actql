///|
/// The original Index and References remain borrowed. This describes the
/// actual all-or-failure resolver, not a Reference admission or new Index.
pub(all) struct ResolveConstructionInventory {
  retained : @shape.CollectionConstructionExtent
  scratch : @shape.CollectionConstructionExtent
} derive(Eq, Debug)

///|
pub fn resolve_construction_inventory(
  references : Int,
) -> ResolveConstructionInventory? {
  if references < 0 {
    return None
  }
  let n = references.to_int64()
  // Each ResolvedInput1H3R1W plus Resolved1H3R and Usage1H2W. The
  // original selected Cursor and Reference instances are retained unchanged.
  let retained = @shape.collection_construction_extent({
    records: n + 2L,
    record_references: 3L * n + 3L,
    record_words: n + 2L,
    reference_arrays: 1L,
    reference_items: n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let utf8 = @scalar.utf8_length_admission_construction_units()
  // Budget, three lookup Some, original typed failure/Stop/Result and one
  // iteration/UTF8-result family14H12R17W. The seen-Map is not returned;
  // stringify returns the same retained Reference text without a String copy.
  let scratch = @shape.collection_construction_extent({
    records: 14L + utf8.0,
    record_references: 12L + utf8.1,
    record_words: 17L + utf8.2,
    reference_arrays: 0L,
    reference_items: 0L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L,
    map_entries: n,
  }).unwrap()
  Some({ retained, scratch, })
}
