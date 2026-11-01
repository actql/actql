///|
// This optional proof reads successful values' checked type, not value data.
// It borrows fields without copying them. Unbounded or opaque shapes preserve
// the general policy. Original compilation depth and proof work bound frames;
// no new acceptance limit, compiler or graph traversal is introduced.
fn client_local_json_contract_nodes(
  contract : @contract.Contract,
  work : Ref[Int],
  depth : Int,
) -> Int64? {
  if work.val < 1 || depth < 0 {
    return None
  }
  work.val -= 1
  match contract.shape {
    @contract.Number | @contract.Boolean | @contract.Text(_) => Some(1L)
    @contract.Array(item, max_items~) => {
      guard max_items is Some(count) && count >= 0L else { return None }
      if count == 0L {
        return Some(1L)
      }
      guard client_local_json_contract_nodes(item, work, depth - 1)
        is Some(nodes) &&
        count <= (2147483647L - 1L) / nodes else {
        return None
      }
      Some(1L + count * nodes)
    }
    @contract.Object(fields) => {
      let mut nodes = 1L
      for index in 0..<@contract.field_count(fields) {
        guard @contract.field_at(fields, index) is Some(field) &&
          client_local_json_contract_nodes(field.contract, work, depth - 1)
          is Some(child) &&
          nodes <= 2147483647L - child else {
          return None
        }
        nodes += child
      }
      Some(nodes)
    }
    _ => None
  }
}

///|
fn client_local_json_schema_nodes(
  schema : @schema.Schema,
  max_work : Int,
  depth : Int,
) -> (Int64, Int)? {
  // The outer inventory already charged every root field. Only additional
  // nested contracts spend its remaining work; this is not Ledger work or a
  // physical refund. Keep the old leaf proof's exact exhausted-work behavior.
  let roots = @schema.field_count(schema)
  if max_work < 0 || roots > 2147483647 - max_work {
    return None
  }
  let work = Ref(max_work + roots)
  let mut nodes = 1L
  for index in 0..<@schema.field_count(schema) {
    guard @schema.field_at(schema, index) is Some(field) &&
      client_local_json_contract_nodes(
        @schema.field_contract(field),
        work,
        depth,
      )
      is Some(child) &&
      nodes <= 2147483647L - child else {
      return None
    }
    nodes += child
  }
  Some((nodes, max_work - work.val))
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
