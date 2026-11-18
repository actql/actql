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
  let mut relations = 0L
  let mut sources = 0L
  let mut units = 0L
  let mut orders = 0L
  for entry in original.entries {
    let texts = match entry.original {
      Relation(value) => {
        relations += 1L
        if value.order is Some(_) {
          orders += 1L
        }
        [entry.path, entry.authored, entry.canonical]
      }
      Source(_) => {
        sources += 1L
        // The actual selected view name and absent marker are borrowed.
        [entry.path]
      }
    }
    for text in texts {
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
  // Inventory 1H/4R/1W. Relation adds its original entry plus the common
  // record (1H/4R) and tagged original (1H/1R/1W). Source owns only its
  // pointer String beside that common record/tag; resolver/name are borrowed.
  // SortOrder/strategy/Some and spare array slots retain their existing cost.
  Some(
    (
      {
        record_headers: array.record_headers +
        1L +
        relations * 6L +
        sources * 3L +
        orders * 3L,
        reference_slots: array.reference_slots +
        4L +
        relations * 10L +
        sources * 5L +
        orders * 5L,
        scalar_words: array.scalar_words +
        1L +
        relations * 4L +
        sources * 2L +
        orders,
      },
      units,
      1L + relations * 4L + sources * 2L,
    ),
  )
}
