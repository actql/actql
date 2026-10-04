///|
struct PreparedGraphEquality {
  node : PreparedNode
  checked : @graph.CheckedPropertyEquality
}

///|
pub(all) enum GraphEqualityIssue {
  InvalidGraphEqualityWiring
} derive(Eq, Debug)

///|
fn prepare_graph_equality_node(
  node : PreparedNode,
) -> Result[PreparedGraphEquality, GraphEqualityIssue] {
  guard node.payload is GraphEqualityRows(checked) &&
    node.inputs.length() == 2 &&
    node.output_schema is Some(_) &&
    @carrier.kind(node.output_carrier) == @carrier.RelationKind else {
    return Err(InvalidGraphEqualityWiring)
  }
  Ok({ node, checked, })
}

///|
pub fn graph_equality_output_schema(
  value : PreparedGraphEquality,
) -> @schema.Schema {
  value.node.output_schema.unwrap()
}

///|
pub fn graph_equality_checked(
  value : PreparedGraphEquality,
) -> @graph.CheckedPropertyEquality {
  value.checked
}

///|
fn emit_graph_equality_node(
  prepared : PreparedGraphEquality,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, prepared.node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  for input in prepared.node.inputs {
    @encode.string_value(out, input)
  }
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, operation(prepared.node))
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.end_object(out)
  @encode.end_object(out)
}
