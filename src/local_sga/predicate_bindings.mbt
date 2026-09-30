///|
fn graph_node_predicate_binding_count(graph : @carrier.Graph) -> Int {
  let identity = if @carrier.graph_names(graph) is Some(_) { 1 } else { 0 }
  identity + @carrier.field_count(@carrier.graph_node_properties(graph))
}

///|
fn graph_node_predicate_binding_read(
  graph : @carrier.Graph,
  source : GraphReadSource,
  node : Int,
  index : Int,
) -> (String, @execution.Value)? {
  let mut property = index
  match @carrier.graph_names(graph) {
    Some(names) => {
      let (identity_name, _, _, _) = @carrier.graph_row_fields(names)
      if property == 0 {
        return graph_read_node_identity(source, node).map(value => {
          (
            @schema.reference_name(identity_name),
            @execution.capture(value.value),
          )
        })
      }
      property -= 1
    }
    None => ()
  }
  let properties = @carrier.graph_node_properties(graph)
  guard @carrier.field_at(properties, property) is Some(field) &&
    graph_read_node_property(source, node, property) is Some(value) else {
    return None
  }
  Some((@schema.reference_name(field.name), @execution.capture(value.value)))
}

///|
fn graph_edge_predicate_binding_count(graph : @carrier.Graph) -> Int {
  let aliases = match @carrier.graph_names(graph) {
    Some(names) => {
      let (_, _, _, label) = @carrier.graph_row_fields(names)
      if label is Some(_) {
        3
      } else {
        2
      }
    }
    None => 0
  }
  aliases + @carrier.field_count(@carrier.graph_edge_properties(graph))
}

///|
fn graph_edge_predicate_binding_read(
  graph : @carrier.Graph,
  source : GraphReadSource,
  edge : Int,
  index : Int,
) -> (String, @execution.Value)? {
  let mut remaining = index
  match @carrier.graph_names(graph) {
    Some(names) => {
      let (_, source_name, target_name, label_name) = @carrier.graph_row_fields(
        names,
      )
      guard graph_read_edge_endpoints(source, edge) is Some((from, to)) else {
        return None
      }
      if remaining == 0 {
        return graph_read_node_identity(source, from).map(value => {
          (@schema.reference_name(source_name), @execution.capture(value.value))
        })
      }
      remaining -= 1
      if remaining == 0 {
        return graph_read_node_identity(source, to).map(value => {
          (@schema.reference_name(target_name), @execution.capture(value.value))
        })
      }
      remaining -= 1
      match label_name {
        Some(name) => {
          if remaining == 0 {
            return match graph_read_edge_label(source, edge) {
              Some(Some(value)) =>
                Some(
                  (
                    @schema.reference_name(name),
                    @execution.capture(value.value),
                  ),
                )
              Some(None) =>
                Some((@schema.reference_name(name), @execution.Null))
              None => None
            }
          }
          remaining -= 1
        }
        None => ()
      }
    }
    None => ()
  }
  let properties = @carrier.graph_edge_properties(graph)
  guard @carrier.field_at(properties, remaining) is Some(field) &&
    graph_read_edge_property(source, edge, remaining) is Some(value) else {
    return None
  }
  Some((@schema.reference_name(field.name), @execution.capture(value.value)))
}
