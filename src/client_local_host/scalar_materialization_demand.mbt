///|
/// Typed demand from one checked schema inventory and its independent relation
/// row bound. This is not a grant: the original provider/Run capacity quote must
/// still admit the complete live inventory on its original Ledger.
priv struct ClientLocalScalarDemand {
  original : ClientLocalSchemaProofInventory
  rows : Int
  value_nodes : Int
  name_bytes : Int
  wire_bytes : Int
}

///|
fn client_local_scalar_product(
  width : Int64,
  rows : Int,
  headroom : Int,
) -> Int? {
  if width < 0L ||
    rows < 1 ||
    headroom < 0 ||
    width > (2147483647L - headroom.to_int64()) / rows.to_int64() {
    return None
  }
  Some((width * rows.to_int64()).to_int())
}

///|
fn client_local_scalar_demand(
  original : ClientLocalSchemaProofInventory,
  rows : Int,
) -> ClientLocalScalarDemand? {
  guard client_local_scalar_product(original.max_node_width, rows, 3)
    is Some(nodes) &&
    client_local_scalar_product(original.max_name_width, rows, 0) is Some(names) &&
    client_local_scalar_wire_byte_bound(original.fields, original.names, rows)
    is Some(wire) else {
    return None
  }
  Some({
    original,
    rows,
    value_nodes: nodes,
    name_bytes: names,
    wire_bytes: wire,
  })
}
