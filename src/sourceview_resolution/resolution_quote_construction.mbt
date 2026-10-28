///|
// Original resolution_construction_inventory quote call tree: zero1H3W,
// returned NFC bound1H2W, two collection inputs/expansions44H4R102W,
// two open28H4R58W, three sums15H3R30W, NFC scratch5H2R14W,
// normalization projection1H3W, four fragment checks4H8W, text-map2H2W,
// two text checks2H4W and result2H3R3W. Alternatives are co-counted;
// these fixed quotation objects do not include the described resolver bodies.
let resolution_quote_extent : @shape.CollectionConstructionExtent = {
  let expansion = @shape.collection_construction_quotation_extent()
  {
    record_headers: 63L + 2L * expansion.record_headers,
    reference_slots: 12L + 2L * expansion.reference_slots,
    scalar_words: 145L + 2L * expansion.scalar_words,
  }
}

///|
pub fn resolution_construction_quotation_extent() -> @shape.CollectionConstructionExtent {
  resolution_quote_extent
}
