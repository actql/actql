///|
/// Canonical finite Number/Boolean rows only. The pinned binary64 formatter
/// emits at most 25 ASCII bytes (the negative fixed-notation -6 exponent case).
/// Decimal, strings, references and nested values never enter this proof.
fn client_local_scalar_wire_bytes(sequences : Array[@execution.GeneratedSequence],max_rows : Int) -> Int? {
  match client_local_schema_proof_inventory(sequences) {
    Some(inventory) => client_local_scalar_wire_byte_bound(inventory.fields,inventory.names,max_rows)
    None => None
  }
}

///|
fn client_local_scalar_wire_byte_bound(fields : Int, names : Int, rows : Int) -> Int? {
  if fields < 0 || fields > client_local_schema_proof_work() || names < 0 || names > 1000000 || rows < 0 || rows > 20000 { return None }
  // Two outer-array bytes plus the 28-byte logical Relation wrapper. Per row:
  // braces/separator 3; each key quote/colon/comma 4 plus Number 25; escaped
  // field names expand by at most six per original UTF-8 byte.
  let bytes = 30L + rows.to_int64() * (3L + 6L * names.to_int64() + 29L * fields.to_int64())
  if bytes > 1000000L { None } else { Some(bytes.to_int()) }
}
