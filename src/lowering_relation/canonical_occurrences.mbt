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
  if sequence.steps.get(step) is Some(NestStep(kernel)) {
    return Some(
      11 +
      (if kernel.parent_references.is_empty() { 0 } else { 1 }) +
      (if kernel.child_references.is_empty() { 0 } else { 1 }) +
      (if kernel.inherited_order || kernel.order.is_empty() { 0 } else { 1 }),
    )
  }
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
  if sequence.steps.get(step) is Some(NestStep(kernel)) {
    let values : Array[(String, String)] = []
    if !kernel.parent_references.is_empty() {
      values.push((nest_generated_id(kernel, "parent_refs"), "REL.derive"))
    }
    if !kernel.child_references.is_empty() {
      values.push((nest_generated_id(kernel, "child_refs"), "REL.derive"))
    }
    values.push((nest_generated_id(kernel, "matched"), "REL.join"))
    values.push((nest_generated_id(kernel, "children"), "REL.select"))
    if !kernel.inherited_order && !kernel.order.is_empty() {
      values.push((nest_generated_id(kernel, "ordered"), "REL.orderByStable"))
    }
    values.push((nest_generated_id(kernel, "grouped"), "REL.groupBy"))
    values.push((nest_generated_id(kernel, "none"), "REL.where"))
    values.push((nest_generated_id(kernel, "empty"), "REL.groupBy"))
    values.push((nest_generated_id(kernel, "attached"), "REL.join"))
    values.push((nest_generated_id(kernel, "parents"), "REL.select"))
    values.push((nest_generated_id(kernel, "empty_attached"), "REL.join"))
    values.push((nest_generated_id(kernel, "flat"), "REL.select"))
    values.push((nest_generated_id(kernel, "filled"), "REL.derive"))
    values.push((node.id, "REL.select"))
    return values
      .get(index)
      .map(value => { source_step: step, id: value.0, operation: value.1, })
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
