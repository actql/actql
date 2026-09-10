///|
pub(all) struct Limits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum Issue {
  InvalidLimits
  IncompleteGraph
  BudgetExceeded
} derive(Eq, Debug)

///|
struct CheckedContract {
  graph : @carrier.Graph
  cid : String
}

///|
pub fn law_cid() -> String {
  "sha256:ab1ae472462b96ac48e56d3ce0544213cab5d422e6bb198bc9acd5e4d90e0fe4"
}

///|
fn complete(rows : @carrier.Knowledge, max_nodes : Int) -> Bool {
  if @carrier.field_set(rows) != Closed {
    return false
  }
  if @carrier.field_count(rows) > max_nodes {
    return false
  }
  for i in 0..<@carrier.field_count(rows) {
    if @carrier.field_at(rows, i).unwrap().contract is None {
      return false
    }
  }
  true
}

///|
fn properties(
  rows : @carrier.Knowledge,
  w : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(w)
  for i in 0..<@carrier.field_count(rows) {
    let f = @carrier.field_at(rows, i).unwrap()
    @encode.key(w, @row.reference_name(f.name))
    @value.emit_checked(f.contract.unwrap(), w)
  }
  @encode.end_object(w)
}

///|
fn emit(
  graph : @carrier.Graph,
  w : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(w)
  @encode.key(w, "edge_labels")
  match @carrier.graph_label_count(graph) {
    None => @encode.null_value(w)
    Some(n) => {
      @encode.begin_array(w)
      for i in 0..<n {
        @encode.string_value(w, @carrier.graph_label_at(graph, i).unwrap())
      }
      @encode.end_array(w)
    }
  }
  @encode.key(w, "edge_properties")
  properties(@carrier.graph_edge_properties(graph), w)
  @encode.key(w, "identity_law_cid")
  @encode.string_value(w, law_cid())
  @encode.key(w, "node_id_contract")
  @value.emit_checked(@carrier.graph_identity(graph), w)
  @encode.key(w, "node_properties")
  properties(@carrier.graph_node_properties(graph), w)
  @encode.key(w, "value_law_cid")
  @encode.string_value(w, law_cid())
  @encode.key(w, "version")
  @encode.string_value(w, "actql-graph-contract/0.1")
  @encode.end_object(w)
}

///|
pub fn admit(
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedContract, Issue] {
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  guard input is @carrier.GraphValue(graph) else { return Err(IncompleteGraph) }
  for
    rows in [
      @carrier.graph_node_properties(graph),
      @carrier.graph_edge_properties(graph),
    ] {
    if @carrier.field_count(rows) > limits.max_nodes {
      return Err(BudgetExceeded)
    }
    if !complete(rows, limits.max_nodes) {
      return Err(IncompleteGraph)
    }
  }
  try {
    let w = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit(graph, w)
    Ok({ graph, cid: "sha256:" + @encode.finish_hash(w), })
  } catch {
    _ => Err(BudgetExceeded)
  }
}

///|
pub fn cid(c : CheckedContract) -> String {
  c.cid
}

///|
pub fn graph(c : CheckedContract) -> @carrier.Graph {
  c.graph
}

///|
pub fn stringify(
  c : CheckedContract,
  limits : Limits,
) -> String raise @encode.EncodeFailure {
  let w = @encode.writer(limits.max_bytes, limits.max_nodes, limits.max_depth)
  emit(c.graph, w)
  @encode.finish(w)
}
