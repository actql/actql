///|
struct PreparedGraphBasic {
  node : PreparedNode
  checked : @graph.CheckedGraph
}

///|
fn prepare_graph_basic_node(
  node : PreparedNode,
) -> Result[PreparedGraphBasic, SequenceIssue] {
  guard node.payload is BasicGraph(checked) else { return Err(SequenceLimit) }
  Ok({ node, checked, })
}

///|
fn emit_graph_basic_params(
  checked : @graph.CheckedGraph,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  match @graph.options(checked) {
    @graph.Normalize => ()
    @graph.DegreeOptions(direction) => {
      @encode.key(out, "direction")
      @encode.string_value(
        out,
        match direction {
          @graph.Incoming => "in"
          @graph.Outgoing => "out"
          @graph.Both => "both"
        },
      )
    }
    _ => ()
  }
  @encode.end_object(out)
}

///|
fn emit_graph_basic_node(
  prepared : PreparedGraphBasic,
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
  emit_graph_basic_params(prepared.checked, out)
  @encode.end_object(out)
}
