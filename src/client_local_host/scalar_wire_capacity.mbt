///|
fn client_local_scalar_wire_byte_bound(
  fields : Int,
  names : Int,
  rows : Int,
) -> Int? {
  if fields < 0 ||
    fields > client_local_schema_proof_work() ||
    names < 0 ||
    rows < 0 {
    return None
  }
  // Two outer-array bytes plus the 28-byte logical Relation wrapper. Per row:
  // braces/separator 3; each key quote/colon/comma 4 plus Number 25; escaped
  // field names expand by at most six per original UTF-8 byte.
  let row_bytes = 3L + 6L * names.to_int64() + 29L * fields.to_int64()
  if rows > 0 && row_bytes > (2147483647L - 30L) / rows.to_int64() {
    return None
  }
  Some((30L + rows.to_int64() * row_bytes).to_int())
}
