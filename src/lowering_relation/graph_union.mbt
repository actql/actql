///|
/// Prepared canonical Graph union. The authored finite input list remains one
/// operation occurrence; this view does not introduce a binary fold tree.
struct PreparedGraphUnion {
  node : PreparedNode
}

///|
fn prepare_graph_union_node(
  node : PreparedNode,
) -> Result[PreparedGraphUnion, SequenceIssue] {
  guard node.payload is GraphUnion(_) else { return Err(SequenceLimit) }
  Ok({ node, })
}

///|
fn emit_graph_union_node(
  prepared : PreparedGraphUnion,
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
  @encode.string_value(out, "SGA.union_structural")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.end_object(out)
  @encode.end_object(out)
}
