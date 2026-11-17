///|
/// Retained audit-owned material only. Checked Program/requirements/parameters
/// and operation/order originals are borrowed; completed slot/sort scratch is
/// absent after the original audit frame has returned.
pub fn local_common_normalization_retained_extent(
  original : LocalCommonNormalizationInventory,
) -> (@shape.CollectionConstructionExtent, Int64, Int64)? {
  guard @shape.reference_array_retained_extent(
      1L,
      original.entries.capacity().to_int64(),
    )
    is Some(array) else {
    return None
  }
  let count = original.entries.length().to_int64()
  let mut units = 0L
  let mut orders = 0L
  for entry in original.entries {
    if entry.order is Some(_) {
      orders += 1L
    }
    for text in [entry.path, entry.authored, entry.canonical] {
      guard @counts.checked_nonnegative_add_product(
          units,
          text.length().to_int64(),
          1L,
        )
        is Some(next) else {
        return None
      }
      units = next
    }
  }
  // Inventory 1H/4R/1W. Each entry borrows five references, owns three final
  // Strings plus SortOrder/strategy/Some views (3H/5R/1W) when selected. Spare array slots remain.
  Some(
    (
      {
        record_headers: array.record_headers + 1L + count * 4L + orders * 3L,
        reference_slots: array.reference_slots + 4L + count * 5L + orders * 5L,
        scalar_words: array.scalar_words + 1L + count * 3L + orders,
      },
      units,
      1L + count * 4L,
    ),
  )
}
