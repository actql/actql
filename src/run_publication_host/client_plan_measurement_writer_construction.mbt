///|
/// Fixed original static-plan measuring-writer sites. This quotes each actual
/// literal frame/key family, NOT ten copies of a policy-sized writer. Embedded
/// emit_measurement children update usage metrics without creating frames.
/// Carrier measuring writers/cursors, scalar scanner/control stack, returned
/// geometry records and transient observations remain independent obligations.
pub fn client_static_plan_measurement_writers_extent() -> @shape.CollectionConstructionExtent? {
  let mut total : @shape.CollectionConstructionExtent = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
  }
  // all_steps; step_key; ports; port_key; port; names; step; map_body;
  // sealed_map; view (root + capability object + quantity object).
  // Conservatively retain every site's maximum through measurement. Sequential
  // loop instances retire at lexical exit; no per-step accumulation/refill.
  for
    (keys, depth) in [
      (0, 1),
      (7, 2),
      (0, 1),
      (6, 1),
      (11, 2),
      (0, 1),
      (8, 1),
      (4, 1),
      (5, 1),
      (18, 3),
    ] {
    guard @encode.measuring_writer_construction_extent(keys, depth)
      is Some(part) &&
      @shape.add_collection_construction_extents(total, part) is Some(next) else {
      return None
    }
    total = next
  }
  Some(total)
}
