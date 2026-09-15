///|
/// Read-only correspondence between one owned semantic operation occurrence
/// and its canonical nodes. This is not a separate IR or a fragment identity.
/// Claims on source_step apply even when a backend fuses its expanded nodes.
pub struct CanonicalOccurrence {
  source_step : Int
  id : String
  operation : String
}

///|
pub fn sequence_canonical_node_count(
  sequence : PreparedSequence,
  step : Int,
) -> Int? {
  sequence.owner.prepared.nodes
  .get(step)
  .map(node => {
    1 +
    (if node.aggregation_id is Some(_) { 1 } else { 0 }) +
    (if node.order_id is Some(_) { 1 } else { 0 }) +
    (if node.projection_id is Some(_) { 1 } else { 0 })
  })
}

///|
/// Uses the collision-checked identifiers retained by wire emission. No
/// allocation of alternative node IDs, rewriting or source re-interpretation.
pub fn sequence_canonical_node_at(
  sequence : PreparedSequence,
  step : Int,
  index : Int,
) -> CanonicalOccurrence? {
  guard index >= 0 && sequence.owner.prepared.nodes.get(step) is Some(node) else {
    return None
  }
  let mut remaining = index
  if node.aggregation_id is Some(id) {
    if remaining == 0 {
      return Some({ source_step: step, id, operation: "REL.groupBy", })
    }
    remaining -= 1
  }
  if node.order_id is Some(id) {
    if remaining == 0 {
      return Some({ source_step: step, id, operation: "REL.orderByStable", })
    }
    remaining -= 1
  }
  if node.projection_id is Some(id) {
    if remaining == 0 {
      return Some({
        source_step: step,
        id,
        operation: if node.payload is InnerJoin(_) {
          "REL.join"
        } else {
          "REL.select"
        },
      })
    }
    remaining -= 1
  }
  if remaining != 0 {
    return None
  }
  Some({
    source_step: step,
    id: node.id,
    operation: match node.payload {
      CountGroup(_) => "REL.orderByStable"
      InnerJoin(_) => "REL.select"
      _ => operation(node)
    },
  })
}
