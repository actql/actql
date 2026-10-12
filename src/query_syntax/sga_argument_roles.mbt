///|
// These are source roles from the installed common operation signatures.
// They never infer a reference from the contents of a String value.
fn sga_field_argument(operation : String, path : Array[String]) -> Bool {
  let direct = match operation {
    "reach" | "traverse" => path == ["start", "id"]
    "shortest_path" =>
      path == ["source", "id"] || path == ["target", "id"] || path == ["weight"]
    "subgraph" => path == ["nodes", "id"]
    "apply_graph_delta" => path == ["field"]
    "match_nodes" | "match_edges" => path == ["fields"]
    "to_vectors" => path == ["id"] || path == ["vector"]
    "pool_vectors" => path == ["by"] || path == ["vector"]
    "to_events" => path == ["id"] || path == ["time"]
    "row_window" => path == ["time"]
    "session" => path == ["id"] || path == ["time"] || path == ["by"]
    _ => false
  }
  direct ||
  (sga_expression_position(operation, path) && path.last() == Some("field"))
}

///|
fn sga_output_argument(operation : String, path : Array[String]) -> Bool {
  (operation == "pool_vectors" && path == ["output_id"]) ||
  (
    (operation == "match_nodes" || operation == "match_edges") &&
    (
      path == ["bindings", "identity"] ||
      path == ["bindings", "source"] ||
      path == ["bindings", "target"]
    )
  )
}

///|
// Only an operand selector qualifier denotes a lexical producer. An ordinary
// expression receiver or a single field name stays in its declared row scope.
fn sga_operand_field_argument(operation : String, path : Array[String]) -> Bool {
  match operation {
    "reach" | "traverse" => path == ["start", "id"]
    "shortest_path" => path == ["source", "id"] || path == ["target", "id"]
    "subgraph" => path == ["nodes", "id"]
    "apply_graph_delta" => path == ["field"]
    _ => false
  }
}

///|
// Lists retain their enclosing source role. Only the signature's expression
// positions expose field leaves; a literal subtree is opaque authored data.
fn sga_expression_position(operation : String, path : Array[String]) -> Bool {
  if path.is_empty() || path.contains("literal") {
    return false
  }
  match operation {
    "match_nodes" | "match_edges" => path[0] == "where"
    "reach" => path.length() >= 2 && path[0] == "start" && path[1] == "where"
    "traverse" =>
      path[0] == "node_where" ||
      path[0] == "edge_where" ||
      (
        path.length() >= 2 &&
        (
          (path[0] == "start" && path[1] == "where") ||
          (path[0] == "hops" && ["node_where", "edge_where"].contains(path[1]))
        )
      )
    "shortest_path" =>
      path.length() >= 2 &&
      ["source", "target"].contains(path[0]) &&
      path[1] == "where"
    "subgraph" =>
      path[0] == "edges" ||
      (path.length() >= 2 && path[0] == "nodes" && path[1] == "where")
    _ => false
  }
}
