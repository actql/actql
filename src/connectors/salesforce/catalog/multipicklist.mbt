///|
/// Literal separator characters inside one approved element cannot round-trip.
/// Empty elements are otherwise representable except for the exact singleton,
/// which the caller distinguishes from the empty array before physical I/O.
fn multipicklist_item_valid(value : String) -> Bool {
  !value.contains(";")
}
