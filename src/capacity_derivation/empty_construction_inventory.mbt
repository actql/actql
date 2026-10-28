///|
/// Only link_references/check on their original zero-node graph. The original
/// caller owns input nodes/Limits. Four reference arrays are identities,
/// resolved nodes, values and dependents; four scalar arrays are units, leaves,
/// remaining and ready. Two result carriers and the makei closure are included.
/// No arithmetic/law acceptance, byte price or resource owner is issued here.
pub fn empty_linked_arithmetic_construction_inventory() -> @shape.CollectionConstructionInventory {
  empty_linked_arithmetic_inventory
}

///|
let empty_linked_arithmetic_inventory : @shape.CollectionConstructionInventory = {
  records: 5L,
  record_references: 8L,
  record_words: 4L,
  reference_arrays: 4L,
  reference_items: 0L,
  scalar_arrays: 4L,
  scalar_items: 0L,
  maps: 1L,
  map_entries: 0L,
}
