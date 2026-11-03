///|
/// Successful item cardinality of the SAME checked node. For Relation this is
/// rows; for Events/Vectors it is records; for Graph it is the total of node
/// and edge occurrences. This fact does not convert a Carrier into a Relation
/// or replace its provider's independent storage/constructor limits.
pub fn node_closed_item_count_bound(
  node : PreparedNode,
  inputs : Array[Int],
) -> Int? {
  if inputs.length() != node.input_targets.length() ||
    inputs.any(count => count < 0) {
    return None
  }
  match node.payload {
    GraphConstructionValue(graph) => {
      // Each checked definition has its OWN positional input, including two
      // roles backed by the same original rows. Do not deduplicate those roles.
      if inputs.length() !=
        @graph.construction_node_count(graph) +
        @graph.construction_edge_count(graph) {
        return None
      }
      let mut total = 0L
      for count in inputs {
        total += count.to_int64()
      }
      if total > 2147483647L {
        None
      } else {
        Some(total.to_int())
      }
    }
    GraphMatchRows(_) =>
      if inputs.length() == 1 {
        Some(inputs[0])
      } else {
        None
      }
    EventValue(event) =>
      match @event.options(event) {
        @event.ToEvents | @event.Watermark(_, _) =>
          if inputs.length() == 1 {
            Some(inputs[0])
          } else {
            None
          }
        _ => None
      }
    VectorValue(vector) =>
      match @vector.operation(vector) {
        @vector.ToVectors | @vector.NormalizeVectors =>
          if inputs.length() == 1 {
            Some(inputs[0])
          } else {
            None
          }
        _ => None
      }
    CarrierProjection(projection) =>
      match @projection.operation(projection) {
        @projection.Events | @projection.Vectors =>
          if inputs.length() == 1 {
            Some(inputs[0])
          } else {
            None
          }
        _ => None
      }
    _ => node_row_count_bound(node, inputs)
  }
}
