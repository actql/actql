///|
/// Physical retention metadata only. Does not admit expressions, registry
/// contracts, input proofs or an executable fragment. Every prepared node
/// remains scheduled, including nodes with no later consumers.
priv struct Wiring {
  owner : @lower.BoundPrepared
  input_count : Int
  ids : Array[String]
  routes : Array[Array[Int]]
  last_use : Array[Int]
  retained : Array[Bool]
}

///|
pub(all) enum WiringIssue {
  InvalidLimits
  Limit
  InvalidReference
  UnknownRetainedTarget(String)
}

///|
/// Retained IDs are internal fragment outputs supplied by the future driver,
/// not a choice of Program Results or execution roots. The caller cannot prune
/// operations through this list. All references resolve against this owner.
fn prepare_wiring(
  owner : @lower.BoundPrepared,
  retained_ids : Array[String],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Wiring, WiringIssue] {
  if control.remaining < 0 ||
    workspace.limit < 0 ||
    workspace.live != 0 ||
    workspace.peak != 0 {
    return Err(InvalidLimits)
  }
  let prepared = @lower.bound_preparation(owner)
  let inputs = @lower.preparation_input_count(prepared)
  let nodes = @lower.node_count(prepared)
  let ids : Array[String] = []
  let last_use : Array[Int] = []
  let retained : Array[Bool] = []
  let routes : Array[Array[Int]] = []
  let positions : Map[String, Int] = Map([])
  // Input registration is separate from node registration, so a forward node
  // reference cannot become valid merely because its ID is known eventually.
  for i = 0; i < inputs; i = i + 1 {
    guard @lower.input_id(prepared, i) is Some(id) else {
      return Err(InvalidReference)
    }
    if !spend_control(control, 1) ||
      !spend_control_text(control, id) ||
      !reserve_slots(workspace, 4) {
      return Err(Limit)
    }
    if positions.contains(id) {
      return Err(InvalidReference)
    }
    positions[id] = ids.length()
    ids.push(id)
    last_use.push(-1)
    retained.push(false)
  }
  for i = 0; i < nodes; i = i + 1 {
    if !spend_control(control, 1) {
      return Err(Limit)
    }
    guard @lower.node_at(prepared, i) is Some(node) else {
      return Err(InvalidReference)
    }
    // The checked occurrence count admits the copied reference view without
    // repeating operation-specific arity rules or parsing source JSON.
    let arity = @lower.node_input_count(node)
    if !reserve_slots(workspace, arity) {
      return Err(Limit)
    }
    let refs = @lower.input_ids(node)
    if refs.length() != arity {
      return Err(InvalidReference)
    }
    let route : Array[Int] = []
    for id in refs {
      if !spend_control(control, 1) ||
        !spend_control_text(control, id) ||
        !reserve_slots(workspace, 1) {
        return Err(Limit)
      }
      guard positions.get(id) is Some(slot) else {
        return Err(InvalidReference)
      }
      route.push(slot)
      last_use[slot] = i
    }
    release_slots(workspace, arity)
    let id = @lower.node_id(node)
    if !spend_control_text(control, id) || !reserve_slots(workspace, 5) {
      return Err(Limit)
    }
    if positions.contains(id) {
      return Err(InvalidReference)
    }
    positions[id] = ids.length()
    ids.push(id)
    // Unconsumed output dies only AFTER its producing operation executes.
    last_use.push(i)
    retained.push(false)
    routes.push(route)
  }
  for id in retained_ids {
    if !spend_control(control, 1) || !spend_control_text(control, id) {
      return Err(Limit)
    }
    guard positions.get(id) is Some(slot) else {
      return Err(UnknownRetainedTarget(id))
    }
    retained[slot] = true
  }
  release_slots(workspace, positions.length())
  Ok({ owner, input_count: inputs, ids, routes, last_use, retained, })
}
