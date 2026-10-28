///|
// Call-expanded allocated controls of collect_construction_inventory itself,
// not the collection body it describes. Sequential alternatives are co-counted.
// Generic expansion21H2R42W; sum5H1R10W; Map8H1R16W; path23H2R53W;
// open14H2R29W; closed54H6R125W; issue29H3R66W; order135H16R303W.
// Original call sites: zero1H3W, NFC output1H2W, retained order1H3W,
// three collection inputs/expansions66H6R153W, fields closure1H1R,
// five open70H10R145W, four closed+field Some220H24R508W,
// order135H16R303W, issue29H3R66W, NFC scratch5H2R14W,
// normalization projection1H3W, thirteen-part Array3H52R2W,
// thirteen sums65H13R130W, result2H3R3W and text-map2H2W.
// No input-sized quote array, callback, tariff or resource allowance is added.
let collection_quote_extent : @shape.CollectionConstructionExtent = {
  let expansion = @shape.collection_construction_quotation_extent()
  {
    record_headers: 539L + 3L * expansion.record_headers,
    reference_slots: 124L + 3L * expansion.reference_slots,
    scalar_words: 1211L + 3L * expansion.scalar_words,
  }
}

///|
/// Installed logical constructor DATA for the original quotation call tree.
/// Callers back it before quotation, then retain their actual returned quote.
pub fn collect_construction_quotation_extent() -> @shape.CollectionConstructionExtent {
  collection_quote_extent
}
