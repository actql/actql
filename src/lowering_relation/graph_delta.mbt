///|
struct PreparedGraphDelta {
  node : PreparedNode
  checked : @graph.CheckedDelta
}

///|
pub(all) enum GraphDeltaIssue {
  InvalidGraphDeltaWiring
} derive(Eq, Debug)

///|
fn prepare_graph_delta_node(
  node : PreparedNode,
) -> Result[PreparedGraphDelta, GraphDeltaIssue] {
  guard node.payload is GraphDeltaValue(checked) && node.inputs.length() == 2 else {
    return Err(InvalidGraphDeltaWiring)
  }
  match (@graph.delta_operation(checked), node.output_carrier) {
    (Difference, @carrier.Relation(_)) if node.output_schema is Some(_) => ()
    (Application(_), @carrier.GraphValue(_)) => ()
    _ => return Err(InvalidGraphDeltaWiring)
  }
  Ok({ node, checked, })
}

///|
pub fn graph_delta_checked(value : PreparedGraphDelta) -> @graph.CheckedDelta {
  value.checked
}

///|
pub fn graph_delta_output_carrier(
  value : PreparedGraphDelta,
) -> @carrier.Carrier {
  value.node.output_carrier
}

///|
fn emit_graph_delta_node(
  value : PreparedGraphDelta,
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
  if @graph.delta_operation(value.checked) is Application(field) {
    @encode.key(out, "field")
    @encode.string_value(out, @schema.reference_name(field))
  }
  @encode.key(out, "graph_contract_cid")
  @encode.string_value(
    out,
    @graph_contract.cid(@graph.delta_graph(value.checked)),
  )
  @encode.end_object(out)
  @encode.end_object(out)
}
