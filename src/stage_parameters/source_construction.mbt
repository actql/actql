///|
/// Constructor DATA for prepare_from_declaration_read. Original Program,
/// declaration/limits/indexed-tree backing stay borrowed and separately
/// charged. The generic collection owner supplies Map/Array growth rules.
pub(all) struct SourceConstructionInventory {
  returned : @shape.CollectionConstructionExtent
  temporary : @shape.CollectionConstructionExtent
  maximum_work : Int64
} derive(Eq, Debug)

///|
pub fn source_construction_inventory(
  program : @stage.Program,
) -> SourceConstructionInventory? {
  let body = @stage.program_body(program)
  guard @decode.object_length(body) is Some(fields) else { return None }
  let stages = @stage.stage_count(program)
  // Source6R; Some(program)1R1W. The Stage copy is the one generic reference
  // array. Limits and all declaration objects are the original borrowed data.
  guard @shape.collection_construction_extent({
      records: 2L,
      record_references: 7L,
      record_words: 1L,
      reference_arrays: 1L,
      reference_items: stages.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(returned) else {
    return None
  }
  // Root ObjectView/open Result2H3R1W; two coordinate Options2H2W;
  // completed read Some1H1R1W; success/typed-error carriers3H3R3W;
  // returned (Result,work) tuple1H1R1W. Keys/values are borrowed.
  guard @shape.collection_construction_extent({
      records: 9L,
      record_references: 8L,
      record_words: 8L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: fields.to_int64(),
    })
    is Some(controls) &&
    @shape.add_collection_construction_extents(
      controls,
      @decode.indexed_child_construction_extent(),
    )
    is Some(controls) &&
    @shape.add_collection_construction_extents(returned, controls)
    is Some(temporary) else {
    return None
  }
  Some({
    returned,
    temporary,
    maximum_work: fields.to_int64() + stages.to_int64() + 1L,
  })
}

///|
/// The SAME Source snapshot plus binding Some, without another Stage array.
/// Original completed reader/declarations/values/limits remain charged by
/// their prior owners. Returned Result/error/observation carriers are temporary.
pub fn source_binding_construction_inventory() -> SourceConstructionInventory {
  {
    returned: { record_headers: 2L, reference_slots: 7L, scalar_words: 1L, },
    temporary: { record_headers: 5L, reference_slots: 10L, scalar_words: 4L, },
    maximum_work: 0L,
  }
}
