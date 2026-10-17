///|
/// An element must retain its identity through the provider's delimiter.
/// Empty representation remains an explicit vendor boundary, not a grant.
fn multipicklist_item_valid(value : String) -> Bool {
  !value.is_empty() && !value.contains(";")
}
