///|
// Only checked original scalar schemas justify this smaller value envelope.
// Unknown or nested contracts retain the general budget; no rows are sampled.
fn client_local_scalar_schema_width(schema : @schema.Schema) -> Int? {
  let width = @schema.field_count(schema)
  if width > client_local_schema_proof_work() {
    return None
  }
  for index in 0..<width {
    guard @schema.field_at(schema, index) is Some(field) else { return None }
    match @schema.field_contract(field).shape {
      @contract.Number | @contract.Boolean => ()
      _ => return None
    }
  }
  Some(width)
}

///|
fn client_local_scalar_nodes(
  sequences : Array[@execution.GeneratedSequence],
  max_rows : Int,
) -> Int? {
  match client_local_schema_proof_inventory(sequences) {
    Some(inventory) => client_local_inventory_nodes(inventory,max_rows)
    None => None
  }
}

///|
fn client_local_scalar_node_limit(width : Int, max_rows : Int) -> Int? {
  if width<1 {return None}
  client_local_scalar_product(width.to_int64(),max_rows,3)
}
