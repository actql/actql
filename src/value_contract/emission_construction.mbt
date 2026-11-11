///|
/// Logical pending storage of the SAME checked canonical emitter. This does
/// not include the supplied Writer, borrowed Contract/field/enum bodies or text
/// backing. A successful read has at most max_contract_nodes typed nodes.
/// Each Value retains <=6 member pairs/variants; field and enum iteration keep
/// one sibling frame rather than copying their remaining children.
pub fn checked_emission_construction_extent(
  max_contract_nodes : Int,
) -> @shape.CollectionConstructionExtent? {
  if max_contract_nodes < 1 {
    return None
  }
  let n = max_contract_nodes.to_int64()
  // CheckedEmission1H4R3W, member pairs/variants12N H18N R12N W,
  // <=6N+8 pending variant frames2R2W each. The original live <=6-element
  // member sort co-counts three views/two tuples/Some and comparator controls.
  @shape.collection_construction_extent({
    records: 1L + 12L * n + 6L * n + 8L + 7L,
    record_references: 4L + 18L * n + 2L * (6L * n + 8L) + 5L,
    record_words: 3L + 12L * n + 2L * (6L * n + 8L) + 10L,
    reference_arrays: 1L + n,
    reference_items: 6L * n + 8L + 6L * n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  })
}

///|
/// Before one transition of this SAME cursor, bound its live pending backing
/// and one new member/frame family. Field/enum arrays and checked contracts
/// stay borrowed. Earlier Array capacity survives pop; policy max_frames is
/// only an admission limit and does not allocate that many frames.
pub fn checked_emission_next_construction_extent(
  cursor : CheckedEmission,
) -> @shape.CollectionConstructionExtent? {
  if cursor.closed || cursor.pending.capacity() == 2147483647 {
    None
  } else {
    checked_emission_construction_extent(
      Int::max(1, cursor.pending.capacity() + 1),
    )
  }
}
