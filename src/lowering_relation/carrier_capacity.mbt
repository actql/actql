///|
/// Successful item cardinality of the SAME checked node. For Relation this is
/// rows; for Events/Vectors it is records; for Graph it is the total of node
/// and edge occurrences. This fact does not convert a Carrier into a Relation
/// or replace its provider's independent storage/constructor limits.
pub fn node_closed_item_count_bound(
  node : PreparedNode,
  count : Int,
  input_at : (Int) -> Int?,
) -> Int? {
  guard count == node.input_targets.length() &&
    collect_node_cardinality_inputs(count, input_at) is Some(inputs) else {
    return None
  }
  match node.payload {
    GraphConstructionValue(graph) => {
      // Each checked definition has its OWN positional input, including two
      // roles backed by the same original rows. Do not deduplicate those roles.
      if inputs.count !=
        @graph.construction_node_count(graph) +
        @graph.construction_edge_count(graph) {
        return None
      }
      if inputs.total > 2147483647L {
        None
      } else {
        Some(inputs.total.to_int())
      }
    }
    GraphMatchRows(_) =>
      if inputs.count == 1 {
        Some(inputs.first)
      } else {
        None
      }
    EventValue(event) =>
      match @event.options(event) {
        @event.ToEvents | @event.Watermark(_, _) =>
          if inputs.count == 1 {
            Some(inputs.first)
          } else {
            None
          }
        _ => None
      }
    VectorValue(vector) =>
      match @vector.operation(vector) {
        @vector.ToVectors | @vector.NormalizeVectors =>
          if inputs.count == 1 {
            Some(inputs.first)
          } else {
            None
          }
        _ => None
      }
    CarrierProjection(projection) =>
      match @projection.operation(projection) {
        @projection.Events | @projection.Vectors =>
          if inputs.count == 1 {
            Some(inputs.first)
          } else {
            None
          }
        _ => None
      }
    _ => node_row_count_bound_from_inputs(node, inputs)
  }
}
