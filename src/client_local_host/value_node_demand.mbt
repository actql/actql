///|
/// Checked cells represented by one JSON leaf. Text bytes keep their separate
/// admitted envelope. Nested/opaque domains need their own recursive proof.
fn client_local_json_leaf_schema(schema : @schema.Schema) -> Bool {
  let count = @schema.field_count(schema)
  if count > client_local_schema_proof_work() {
    return false
  }
  for index in 0..<count {
    guard @schema.field_at(schema, index) is Some(field) else { return false }
    match @schema.field_contract(field).shape {
      @contract.Number | @contract.Boolean | @contract.Text(_) => ()
      _ => return false
    }
  }
  true
}

///|
/// Same-original node demand only: this does not prove numeric wire length,
/// remove text admission, or permit a different Program/Result inventory.
priv struct ClientLocalValueNodeDemand {
  original : ClientLocalSchemaProofInventory
  rows : Int
  nodes : Int
}

///|
fn client_local_value_node_demand(
  original : ClientLocalSchemaProofInventory,
  rows : Int,
) -> ClientLocalValueNodeDemand? {
  match client_local_inventory_nodes(original, rows) {
    Some(nodes) => Some({ original, rows, nodes, })
    None => None
  }
}
