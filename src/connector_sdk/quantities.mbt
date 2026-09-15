///|
/// Non-time quantities remain separate and do not become hard bounds. The
/// money unit is Host-context-specific; it is never added to bytes or latency.
pub(all) struct QueryQuantities {
  transfer_bytes : Int64?
  retained_bytes : Int64?
  money_units : Int64?
}

///|
pub fn valid_quantity(value : Int64?) -> Bool {
  match value {
    None => true
    Some(n) => n >= 0L
  }
}
