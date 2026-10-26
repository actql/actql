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
