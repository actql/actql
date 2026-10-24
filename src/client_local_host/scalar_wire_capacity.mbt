///|
/// Canonical finite Number/Boolean rows only. The pinned binary64 formatter
/// emits at most 25 ASCII bytes (the negative fixed-notation -6 exponent case).
/// Decimal, strings, references and nested values never enter this proof.
fn client_local_scalar_wire_bytes(
  sequences : Array[@execution.GeneratedSequence],
  max_rows : Int,
) -> Int? {
  if sequences.is_empty() || sequences.length() > 32 || max_rows < 1 || max_rows > 20000 { return None }
  let mut fields = 0
  let mut names = 0
  for sequence in sequences {
    let prepared = @lower.bound_preparation(@execution.generated_sequence_owner(sequence))
    for index in 0..<@lower.preparation_input_count(prepared) {
      guard @lower.preparation_input_schema(prepared,index) is Some(schema) && client_local_scalar_schema_width(schema) is Some(width) else { return None }
      fields = Int::max(fields,width)
      names = Int::max(names,@schema.field_reference_name_bytes(schema))
    }
    for index in 0..<@lower.node_count(prepared) {
      guard @lower.node_at(prepared,index) is Some(node) && @lower.node_relation_schema(node) is Some(schema) && client_local_scalar_schema_width(schema) is Some(width) else { return None }
      fields = Int::max(fields,width)
      names = Int::max(names,@schema.field_reference_name_bytes(schema))
    }
  }
  client_local_scalar_wire_byte_bound(fields,names,max_rows)
}

///|
fn client_local_scalar_wire_byte_bound(fields : Int, names : Int, rows : Int) -> Int? {
  if fields < 0 || fields > 100 || names < 0 || names > 1000000 || rows < 0 || rows > 20000 { return None }
  // Two outer-array bytes plus the 28-byte logical Relation wrapper. Per row:
  // braces/separator 3; each key quote/colon/comma 4 plus Number 25; escaped
  // field names expand by at most six per original UTF-8 byte.
  let bytes = 30L + rows.to_int64() * (3L + 6L * names.to_int64() + 29L * fields.to_int64())
  if bytes > 1000000L { None } else { Some(bytes.to_int()) }
}
