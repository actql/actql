///|
// Call-expanded pipeline_preparation_construction quotation controls:
// early1H3W, zero1H3W, two collection inputs/expansions44H4R102W,
// the original three-cost scalar Array3H1R23W, carrier1H3W,
// sum5H1R10W and result/Some2H3R1W. These describe only the quotation;
// actual Stage arrays, entries and borrowed carriers belong to its result.
let pipeline_quote_extent : @shape.CollectionConstructionExtent = {
  let expansion = @shape.collection_construction_quotation_extent()
  {
    record_headers: 15L + 2L * expansion.record_headers,
    reference_slots: 5L + 2L * expansion.reference_slots,
    scalar_words: 61L + 2L * expansion.scalar_words,
  }
}

///|
pub fn pipeline_preparation_quotation_extent() -> @shape.CollectionConstructionExtent {
  pipeline_quote_extent
}
