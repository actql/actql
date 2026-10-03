///|
// Shared by current keyed TRAIL lowering; not a reach execution path.
fn emit_graph_direction(
  direction : @graph.Direction,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.string_value(
    out,
    match direction {
      @graph.Incoming => "in"
      @graph.Outgoing => "out"
      @graph.Both => "both"
    },
  )
}
