///|
fn imported_child_port(
  _nonce : Int64,
) -> Result[
  (
    (Int64) -> Int,
    (Int64) -> Int,
    (Int64, Int) -> Int64,
    (Int64, Int) -> Int64,
    (Int64, LedgerUsage) -> Int,
    (Int64) -> Int,
  ),
  ImportedChildLedgerIssue,
] {
  Err(Unavailable)
}
