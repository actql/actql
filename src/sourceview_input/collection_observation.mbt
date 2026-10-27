///|
/// Additional observer controls only: Ref[Int]1H1W, its Some1H1R1W and
/// returned (Result,spent) tuple1H1R1W. The original collector's Budget,
/// Cursors, arrays/Map, NFC/order construction and input backing are separate.
/// This installed DATA has no byte price and is not a complete collection quote.
pub fn collection_observation_control_extent() -> @shape.CollectionConstructionExtent {
  collection_observation_controls
}

///|
let collection_observation_controls : @shape.CollectionConstructionExtent = {
  record_headers: 3L,
  reference_slots: 2L,
  scalar_words: 3L,
}
