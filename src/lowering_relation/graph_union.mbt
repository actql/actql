///|
struct PreparedGraphUnion {
  node : PreparedNode
  checked : @graph.CheckedUnion
}

///|
pub(all) enum GraphUnionIssue {
  InvalidGraphUnionWiring
} derive(Eq, Debug)

///|
fn prepare_graph_union_node(
  node : PreparedNode,
) -> Result[PreparedGraphUnion, GraphUnionIssue] {
  let checked = match node.payload {
    GraphUnionValue(checked) => checked
    GraphSubtractionValue(checked) => @graph.subtraction_composition(checked)
    _ => return Err(InvalidGraphUnionWiring)
  }
  guard node.inputs.length() == @graph.union_input_count(checked) &&
    node.inputs.length() >= 2 &&
    node.output_schema is None &&
    node.output_carrier is @carrier.GraphValue(_) else {
    return Err(InvalidGraphUnionWiring)
  }
  Ok({ node, checked, })
}

///|
pub fn graph_union_checked(value : PreparedGraphUnion) -> @graph.CheckedUnion {
  value.checked
}

///|
fn emit_graph_union_node(
  value : PreparedGraphUnion,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, value.node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  for input in value.node.inputs {
    @encode.string_value(out, input)
  }
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, operation(value.node))
  @encode.key(out, "params")
  @encode.begin_object(out)
  for edge in [false, true] {
    let count = @graph.union_strategy_count(value.checked, edge~)
    if count > 0 {
      @encode.key(out, if edge { "edge_properties" } else { "node_properties" })
      @encode.begin_object(out)
      for index in 0..<count {
        let (name, strategy) = @graph.union_strategy_at(
          value.checked,
          index,
          edge~,
        ).unwrap()
        @encode.key(out, name)
        @encode.string_value(out, @graph.union_strategy_name(strategy))
      }
      @encode.end_object(out)
    }
  }
  @encode.end_object(out)
  @encode.end_object(out)
}
