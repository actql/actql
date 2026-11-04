///|
/// Exact nonnegative Int64 count composition for preparation representation.
/// This does not construct a language Value: its independent safe-integer
/// admission remains unchanged. Counts, tariffs, original ownership and actual
/// resource backing must still come from their existing domain owners.
pub fn checked_nonnegative_add_product(
  total : Int64,
  count : Int64,
  coefficient : Int64,
) -> Int64? {
  if total < 0L ||
    count < 0L ||
    coefficient <= 0L ||
    count > (9223372036854775807L - total) / coefficient {
    None
  } else {
    Some(total + count * coefficient)
  }
}

///|
/// Pinned logical Array wrapper/backing convention used by preparation
/// inventories. Elements are borrowed references; independently owned entry
/// records and payloads belong to their constructor. This is not a byte price
/// or an engine heap estimate. Growth includes the old/new backing overlap.
pub fn preparation_array_slots(
  count : Int64,
  items : Int64,
  growing : Bool,
) -> (Int64, Int64, Int64)? {
  let headers = if growing { 3L } else { 2L }
  let backing = if growing { 13L } else { 9L }
  let entries = if growing { 3L } else { 2L }
  guard checked_nonnegative_add_product(0L, count, headers) is Some(h) &&
    checked_nonnegative_add_product(0L, count, backing) is Some(r) &&
    checked_nonnegative_add_product(r, items, entries) is Some(r) &&
    checked_nonnegative_add_product(0L, count, 2L) is Some(w) else {
    return None
  }
  Some((h, r, w))
}
