///|
// Call-expanded index_construction_inventory quotation: zero/early2H6W,
// two collection input/expansions44H4R102W; early Map8H1R15W,
// projections2H6W/add5H1R10W/result2H3R1W; open14H2R29W,
// three multiplications3H6W, view/control records2H6W, three body adds
// (including scalar-owned UTF8 controls)15H3R30W and result2H3R1W.
// Alternative paths co-count fixed controls; Index/Map/name bodies are separate.
let index_quote_units : @shape.CollectionConstructionExtent = {
  let expansion = @shape.collection_construction_quotation_extent()
  {
    record_headers: 57L + 2L * expansion.record_headers,
    reference_slots: 13L + 2L * expansion.reference_slots,
    scalar_words: 128L + 2L * expansion.scalar_words,
  }
}

///|
pub fn index_construction_quotation_extent() -> @shape.CollectionConstructionExtent {
  index_quote_units
}
