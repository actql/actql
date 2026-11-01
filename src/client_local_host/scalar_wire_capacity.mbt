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
  client_local_json_leaf_wire_byte_bound(
    fields,
    rows,
    rows.to_int64() * names.to_int64(),
  )
}

///|
// One wire formula for flat JSON leaves. The original value budget includes
// both field-name and Text payload bytes. Numeric-only schemas supply their
// exact name-byte envelope above; no Text policy or capacity is changed.
fn client_local_json_leaf_wire_byte_bound(
  fields : Int,
  rows : Int,
  total_text_bytes : Int64,
) -> Int? {
  if fields < 0 ||
    fields > client_local_schema_proof_work() ||
    rows < 0 ||
    total_text_bytes < 0L ||
    total_text_bytes > (2147483647L - 30L) / 6L {
    return None
  }
  // Two array bytes plus the 28-byte Relation wrapper. Per row: braces and
  // separator3; per leaf: key quotes/colon/comma4 and at most Number25 syntax.
  // Text quotes also fit that syntax envelope; UTF-8 content escapes at most6.
  let text = 6L * total_text_bytes
  let row_bytes = 3L + 29L * fields.to_int64()
  if rows > 0 && row_bytes > (2147483647L - 30L - text) / rows.to_int64() {
    return None
  }
  Some((30L + text + rows.to_int64() * row_bytes).to_int())
}
