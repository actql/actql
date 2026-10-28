///|
/// Constructor-owned collection counts. Keys/element bodies and String backing
/// stay with their original owners. These DATA units carry no byte tariff,
/// capacity policy, allocation, semantic verdict or permission.
pub(all) struct CollectionConstructionInventory {
  records : Int64
  record_references : Int64
  record_words : Int64
  reference_arrays : Int64
  reference_items : Int64
  scalar_arrays : Int64
  scalar_items : Int64
  maps : Int64
  map_entries : Int64
} derive(Eq, Debug)

///|
pub(all) struct CollectionConstructionExtent {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
} derive(Eq, Debug)

///|
pub fn compose_collection_construction_inventories(
  values : Array[CollectionConstructionInventory],
) -> CollectionConstructionInventory? {
  let mut h = 0L
  let mut r = 0L
  let mut w = 0L
  let mut a = 0L
  let mut n = 0L
  let mut s = 0L
  let mut t = 0L
  let mut m = 0L
  let mut e = 0L
  for v in values {
    guard @counts.checked_nonnegative_add_product(h, v.records, 1L) is Some(h1) &&
      @counts.checked_nonnegative_add_product(r, v.record_references, 1L)
      is Some(r1) &&
      @counts.checked_nonnegative_add_product(w, v.record_words, 1L) is Some(w1) &&
      @counts.checked_nonnegative_add_product(a, v.reference_arrays, 1L)
      is Some(a1) &&
      @counts.checked_nonnegative_add_product(n, v.reference_items, 1L)
      is Some(n1) &&
      @counts.checked_nonnegative_add_product(s, v.scalar_arrays, 1L)
      is Some(s1) &&
      @counts.checked_nonnegative_add_product(t, v.scalar_items, 1L) is Some(t1) &&
      @counts.checked_nonnegative_add_product(m, v.maps, 1L) is Some(m1) &&
      @counts.checked_nonnegative_add_product(e, v.map_entries, 1L) is Some(e1) else {
      return None
    }
    h = h1
    r = r1
    w = w1
    a = a1
    n = n1
    s = s1
    t = t1
    m = m1
    e = e1
  }
  Some({
    records: h,
    record_references: r,
    record_words: w,
    reference_arrays: a,
    reference_items: n,
    scalar_arrays: s,
    scalar_items: t,
    maps: m,
    map_entries: e,
  })
}

///|
/// Logical pinned builtin construction peak. Grow-only Array wrapper/backing
/// plus old/new growth is3H, with <=12+3N slots and2 wrapper words. Reference
/// and scalar slots remain distinct; the Map recipe is its existing owner.
/// This is not retained/no-growth storage, RSS or a physical release report.
pub fn collection_construction_extent(
  v : CollectionConstructionInventory,
) -> CollectionConstructionExtent? {
  guard map_construction_extent(v.maps, v.map_entries) is Some(map) &&
    @counts.checked_nonnegative_add_product(v.records, v.reference_arrays, 3L)
    is Some(h) &&
    @counts.checked_nonnegative_add_product(h, v.scalar_arrays, 3L) is Some(h) &&
    @counts.checked_nonnegative_add_product(h, map.record_headers, 1L)
    is Some(h) &&
    @counts.checked_nonnegative_add_product(
      v.record_references,
      v.reference_arrays,
      13L,
    )
    is Some(r) &&
    @counts.checked_nonnegative_add_product(r, v.reference_items, 3L) is Some(r) &&
    @counts.checked_nonnegative_add_product(r, v.scalar_arrays, 1L) is Some(r) &&
    @counts.checked_nonnegative_add_product(r, map.reference_slots, 1L)
    is Some(r) &&
    @counts.checked_nonnegative_add_product(
      v.record_words,
      v.reference_arrays,
      2L,
    )
    is Some(w) &&
    @counts.checked_nonnegative_add_product(w, v.scalar_arrays, 14L) is Some(w) &&
    @counts.checked_nonnegative_add_product(w, v.scalar_items, 3L) is Some(w) &&
    @counts.checked_nonnegative_add_product(w, map.scalar_words, 1L) is Some(w) else {
    return None
  }
  Some({ record_headers: h, reference_slots: r, scalar_words: w, })
}

///|
/// Add already expanded units without expanding their Map/Array backing twice.
/// This remains DATA composition, not another tariff, allocator or grant.
pub fn add_collection_construction_extents(
  a : CollectionConstructionExtent,
  b : CollectionConstructionExtent,
) -> CollectionConstructionExtent? {
  guard @counts.checked_nonnegative_add_product(
      a.record_headers,
      b.record_headers,
      1L,
    )
    is Some(h) &&
    @counts.checked_nonnegative_add_product(
      a.reference_slots,
      b.reference_slots,
      1L,
    )
    is Some(r) &&
    @counts.checked_nonnegative_add_product(a.scalar_words, b.scalar_words, 1L)
    is Some(w) else {
    return None
  }
  Some({ record_headers: h, reference_slots: r, scalar_words: w, })
}
