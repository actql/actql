///|
/// Logical builtin linked Map construction, including old/new bucket backing
/// during growth. Domains supply map/entry multiplicity and lifetime, then add
/// their own wrappers. This owns no byte tariff, key verdict or allocation.
pub(all) struct MapConstructionExtent {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
} derive(Eq, Debug)

///|
pub fn map_construction_extent(
  maps : Int64,
  entries : Int64,
) -> MapConstructionExtent? {
  // Map record/backing and tagged links:7H18R21W per growing map;
  // Entry/link alternatives and growing bucket slots:4H11R13W per entry.
  // Keys and values borrow their original owners. Retained/no-growth maps
  // have a different overlap and must not be substituted by equal totals.
  guard @counts.checked_nonnegative_add_product(0L, maps, 7L) is Some(h) &&
    @counts.checked_nonnegative_add_product(h, entries, 4L) is Some(h) &&
    @counts.checked_nonnegative_add_product(0L, maps, 18L) is Some(r) &&
    @counts.checked_nonnegative_add_product(r, entries, 11L) is Some(r) &&
    @counts.checked_nonnegative_add_product(0L, maps, 21L) is Some(w) &&
    @counts.checked_nonnegative_add_product(w, entries, 13L) is Some(w) else {
    return None
  }
  Some({ record_headers: h, reference_slots: r, scalar_words: w, })
}
