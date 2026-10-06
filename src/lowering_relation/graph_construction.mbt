///|
pub(all) enum GraphConstructionIssue {
  InvalidGraphConstruction
} derive(Eq, Debug)

///|
fn begin_graph_construction_node(
  out : @encode.Writer,
  id : String,
  inputs : Array[String],
  operation : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  for input in inputs {
    @encode.string_value(out, input)
  }
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, operation)
  @encode.key(out, "params")
  @encode.begin_object(out)
}

///|
fn end_graph_construction_node(
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.end_object(out)
  @encode.end_object(out)
}
