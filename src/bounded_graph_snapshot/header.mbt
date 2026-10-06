///|
/// Checked framing only. Records still require the existing value/key/storage
/// admission, and the completed material must match the expected snapshot CID.
struct SnapshotHeader {
  nodes : @decode.Cursor
  edges : @decode.Cursor
  node_count : Int
  edge_count : Int
}

///|
pub fn read_header(
  input : @decode.Cursor,
  expected : @carrier.Graph,
  limits : Limits,
) -> Result[SnapshotHeader, Issue] {
  if !valid_snapshot_limits(limits) {
    return Err(InvalidLimits)
  }
  if @decode.array_length(input) != Some(5) {
    return Err(InvalidSnapshotBody)
  }
  if @decode.text(@decode.element_at(input, 0).unwrap()) !=
    Ok("actql-graph-snapshot/0.1") {
    return Err(InvalidSnapshotBody)
  }
  let usage = @decode.admission_usage(input)
  if usage.nodes > limits.max_identity_nodes ||
    usage.depth > limits.max_identity_depth ||
    usage.total_string_bytes > limits.max_identity_bytes {
    return Err(Identity(@identity.EncodingLimit))
  }
  let caps : @contract_graph.Limits = {
    max_bytes: limits.max_identity_bytes,
    max_nodes: limits.max_identity_nodes,
    max_depth: limits.max_identity_depth,
  }
  guard @contract_graph.admit(@carrier.graph_carrier(expected), caps)
    is Ok(expected_contract) &&
    @contract_graph.read_cursor(@decode.element_at(input, 2).unwrap(), caps)
    is Ok(received) &&
    @decode.text(@decode.element_at(input, 1).unwrap()) is Ok(received_cid) &&
    received_cid == @contract_graph.cid(received) &&
    received_cid == @contract_graph.cid(expected_contract) else {
    return Err(SnapshotContractMismatch)
  }
  let nodes = @decode.element_at(input, 3).unwrap()
  let edges = @decode.element_at(input, 4).unwrap()
  guard @decode.array_length(nodes) is Some(node_count) &&
    @decode.array_length(edges) is Some(edge_count) else {
    return Err(InvalidSnapshotBody)
  }
  Ok({ nodes, edges, node_count, edge_count, })
}

///|
pub fn header_node_count(value : SnapshotHeader) -> Int {
  value.node_count
}

///|
pub fn header_edge_count(value : SnapshotHeader) -> Int {
  value.edge_count
}

///|
pub fn header_node_at(value : SnapshotHeader, index : Int) -> @decode.Cursor? {
  @decode.element_at(value.nodes, index)
}

///|
pub fn header_edge_at(value : SnapshotHeader, index : Int) -> @decode.Cursor? {
  @decode.element_at(value.edges, index)
}
