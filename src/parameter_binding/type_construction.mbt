///|
/// Select quantities ONLY from this original reader's current retained facts.
/// No caller geometry/ordinal/equal proof can replace the original association.
pub fn declaration_type_construction_inventory(
  original : DeclarationReadInput,
  root_path_depth : Int,
) -> @contract.ParameterReadPhaseConstructionInventory? {
  if root_path_depth < 0 {
    return None
  }
  guard original.state is ReadingDeclaration(body) &&
    body.syntax is None &&
    body.construction is Some(facts) &&
    facts.entries[body.index] is Some(current) else {
    return None
  }
  guard @contract.parameter_read_phase_construction_inventory(
      current.type_syntax,
      root_path_depth.to_int64() + 1L,
      {
        max_nodes: original.limits.max_nodes,
        max_depth: original.limits.max_depth,
        max_text_bytes: original.limits.max_text_bytes,
      },
    )
    is Some(inventory) else {
    return None
  }
  // Original body's syntax Some1H1R1W; outer Parameter issue/wrapper/state
  // families4H6R6W. Contract owns its own syntax/Decode issues separately.
  let attachment : @shape.CollectionConstructionExtent = {
    record_headers: 1L,
    reference_slots: 1L,
    scalar_words: 1L,
  }
  let issues : @shape.CollectionConstructionExtent = {
    record_headers: 4L,
    reference_slots: 6L,
    scalar_words: 6L,
  }
  guard @shape.add_collection_construction_extents(
      inventory.returned,
      attachment,
    )
    is Some(returned) &&
    @shape.add_collection_construction_extents(inventory.temporary, issues)
    is Some(temporary) else {
    return None
  }
  Some({
    returned,
    temporary,
    normalization: inventory.normalization,
    sort_fields: inventory.sort_fields,
  })
}
