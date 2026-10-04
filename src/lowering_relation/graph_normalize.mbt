///|
/// Normalization has no operation parameters. Its exact checked input edge
/// and Graph output contract remain on the prepared owner.
fn emit_graph_normalize_node(
  owner : BoundPrepared,
  index : Int,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  guard owner.prepared.nodes.get(index) is Some(node) &&
    node.payload is GraphNormalizeValue(_) &&
    node.inputs.length() == 1 else {
    raise @encode.InvalidStructure
  }
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.string_value(out, node.inputs[0])
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "SGA.normalize")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.end_object(out)
  @encode.end_object(out)
}
