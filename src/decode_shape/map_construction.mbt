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

///|
// Pinned Map::iter over reference keys/values: Iter1H2R, size Some1H1W,
// closure1H2R and its original mutable entry/remaining cells2H1R1W.
// Original Map entries and their Some links are borrowed, never copied here.
let reference_map_iterator_retained : CollectionConstructionExtent = {
  record_headers: 5L,
  reference_slots: 5L,
  scalar_words: 2L,
}

///|
/// Original retained iterator controls only; not the Map or its entry bodies.
pub fn reference_map_iterator_retained_extent() -> CollectionConstructionExtent {
  reference_map_iterator_retained
}

///|
// Iter::new additionally overlaps the incoming and normalized size-hint Some.
let reference_map_iterator_construction : CollectionConstructionExtent = {
  record_headers: 6L,
  reference_slots: 5L,
  scalar_words: 3L,
}

///|
pub fn reference_map_iterator_construction_extent() -> CollectionConstructionExtent {
  reference_map_iterator_construction
}

///|
// Original next pair1H2R, result Some1H1R1W, new size Some1H1W and
// the next method's explicit result/size match pair1H2R. No entry body grows.
let reference_map_iterator_next : CollectionConstructionExtent = {
  record_headers: 4L,
  reference_slots: 5L,
  scalar_words: 2L,
}

///|
pub fn reference_map_iterator_next_construction_extent() -> CollectionConstructionExtent {
  reference_map_iterator_next
}
