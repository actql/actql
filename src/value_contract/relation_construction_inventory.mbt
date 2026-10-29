///|
/// Same original comparison/join stacks. Input Contract bodies and their
/// Strings remain borrowed. Joined records can coexist with those originals.
pub(all) struct RelationConstructionInventory {
  joined : @shape.CollectionConstructionExtent
  scratch : @shape.CollectionConstructionExtent
} derive(Eq, Debug)

///|
pub fn relation_construction_inventory(
  source_nodes : Int,
) -> RelationConstructionInventory? {
  if source_nodes < 0 {
    return None
  }
  let n = source_nodes.to_int64()
  // A joined node's Contract/Shape/TextLimits/optional scalar carriers and
  // object Field records. Enum union keeps <=the original total occurrences;
  // it neither normalizes nor owns a new copy of their String backing.
  let joined = @shape.collection_construction_extent({
    records: 9L * n,
    record_references: 6L * n,
    record_words: 9L * n,
    reference_arrays: 2L * n,
    reference_items: 3L * n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  // Visit/Assemble and comparison pair/pop carriers <=4N/6N/2N;
  // pending/results and current entries/ordered arrays are actual join work.
  // Fixed12/10/12 covers budget, enum work/result and typed alternatives.
  let scratch = @shape.collection_construction_extent({
    records: 12L + 4L * n,
    record_references: 10L + 6L * n,
    record_words: 12L + 2L * n,
    reference_arrays: 4L,
    reference_items: 5L * n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  Some({ joined, scratch, })
}
