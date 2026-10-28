///|
/// Original empty mixed/program-claim constructor chain. Its original caller
/// owns literal argument arrays/Limits. Arithmetic source bodies are empty;
/// dependency/cycle backing is still present and explicitly counted. This
/// DATA neither supplies evidence nor validates a nonempty claim collection.
pub fn empty_mixed_program_construction_inventory() -> @shape.CollectionConstructionInventory {
  empty_mixed_program_inventory
}

///|
let empty_mixed_program_inventory : @shape.CollectionConstructionInventory = @shape.compose_collection_construction_inventories([
    @arithmetic.empty_linked_arithmetic_construction_inventory(),
    // Closure and link-reference Limits; Arithmetic/Mixed/Program owners and Result carriers;
    // mixed Some and two makei closures. The seven ref arrays are nodes,
    // witness copy, admitted, two successor tables, bound and indexed proofs.
    // Two indegree and two acyclic-ready arrays contain scalar slots.
    {
      records: 11L,
      record_references: 12L,
      record_words: 15L,
      reference_arrays: 7L,
      reference_items: 0L,
      scalar_arrays: 4L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: 0L,
    },
  ],
).unwrap()
