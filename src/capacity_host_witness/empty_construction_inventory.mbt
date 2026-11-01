///|
/// bind_claim_sources over the original empty mixed ProgramClaims. Default
/// claims stay constructor DATA, not a Host policy, execution grant or source
/// authority. The original factories and their checks remain unchanged.
pub fn empty_host_sources_construction_inventory() -> @shape.CollectionConstructionInventory {
  empty_host_sources_inventory
}

///|
let empty_host_sources_inventory : @shape.CollectionConstructionInventory = @shape.compose_collection_construction_inventories([
    @wire.empty_mixed_program_construction_inventory(),
    // HostSources, SourceOrigin and Result; sources/dependencies arrays and the
    // actual original by-policy-CID Map. Literal policies/Limits are caller-owned.
    {
      records: 3L,
      record_references: 6L,
      record_words: 6L,
      reference_arrays: 2L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: 0L,
    },
  ],
).unwrap()
