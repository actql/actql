///|
priv struct ExpressionRoots {
  budget : LogicalBudget
  slots : Array[LogicalRoot?]
  free : Array[Int]
  limit : Int
}

///|
priv struct ExpressionRootLease {
  scope : ExpressionRoots
  slot : Int
  root : LogicalRoot
}

///|
fn expression_roots(budget : LogicalBudget, frames : Int) -> ExpressionRoots {
  { budget, slots: [], free: [], limit: Int::min(frames, 2147483645) + 2, }
}

///|
fn track_expression_root(
  scope : ExpressionRoots,
  value : Value,
  produced : Bool,
) -> Result[ExpressionRootLease, LogicalBudgetIssue] {
  if scope.free.is_empty() && scope.slots.length() >= scope.limit {
    scope.budget.failed = true
    return Err(LiveValueLimit)
  }
  let root = if produced {
    match retain_logical_value(scope.budget, value) {
      Ok(root) => root
      Err(e) => return Err(e)
    }
  } else {
    // Only an implementation accumulator: reserve its logical lifetime without
    // inventing another semantic expression result or operand charge.
    let b = scope.budget
    let m = match
      measure_logical_value(
        value,
        9007199254740991L,
        Int64::min(b.limits.max_value_bytes, b.host_bytes.to_int64()).to_int(),
        b.host_nodes,
        b.host_depth,
      ) {
      Ok(m) => m
      Err(e) => {
        b.failed = true
        return Err(ValueMeasure(e))
      }
    }
    match reserve_logical_bytes(b, m.wire_bytes.to_int64()) {
      Ok(root) => {
        root.measurement = Some(m)
        root
      }
      Err(issue) => return Err(issue)
    }
  }
  register_scope_root(scope, root)
}

///|
fn register_scope_root(
  scope : ExpressionRoots,
  root : LogicalRoot,
) -> Result[ExpressionRootLease, LogicalBudgetIssue] {
  if !physical_equal(scope.budget, root.owner) || root.released {
    scope.budget.failed = true
    return Err(InvalidRootLifetime)
  }
  if scope.free.is_empty() && scope.slots.length() >= scope.limit {
    release_logical_root(scope.budget, root) |> ignore
    scope.budget.failed = true
    return Err(LiveValueLimit)
  }
  let slot = match scope.free.pop() {
    Some(i) => {
      scope.slots[i] = Some(root)
      i
    }
    None => {
      let i = scope.slots.length()
      scope.slots.push(Some(root))
      i
    }
  }
  Ok({ scope, slot, root, })
}

///|
/// Immutable expression results can reuse their exact measurement, but every
/// semantic consumption still pays its full weight. A revoked/foreign lease
/// cannot supply a proof for another root or budget.
fn consume_expression_value(
  budget : LogicalBudget,
  value : Value,
  root : ExpressionRootLease?,
) -> Result[LogicalValueMeasure, LogicalBudgetIssue] {
  if root is Some(root) && root.root.measurement is Some(measurement) {
    guard physical_equal(root.scope.budget, budget) &&
      !root.root.released &&
      root.scope.slots.get(root.slot) is Some(Some(live)) &&
      physical_equal(live, root.root) else {
      budget.failed = true
      return Err(InvalidRootLifetime)
    }
    if budget.failed {
      return Err(FailedLogicalBudget)
    }
    if measurement.weight > budget.limits.max_work - budget.work {
      budget.failed = true
      return Err(ValueMeasure(LogicalWorkLimit))
    }
    budget.work += measurement.weight
    Ok(measurement)
  } else {
    charge_logical_value(budget, value)
  }
}

///|
/// A private object accumulator grows within the same root owner. It is not
/// exposed as a Value or completion and cannot bypass per-value/live ceilings.
fn grow_object_root(
  root : ExpressionRootLease,
  bytes : Int64,
) -> Result[Unit, LogicalBudgetIssue] {
  let budget = root.scope.budget
  let limit = Int64::min(
    budget.limits.max_value_bytes,
    budget.host_bytes.to_int64(),
  )
  if budget.failed {
    return Err(FailedLogicalBudget)
  }
  guard physical_equal(root.root.owner, budget) &&
    root.scope.slots.get(root.slot) is Some(Some(live)) &&
    physical_equal(live, root.root) &&
    !root.root.released else {
    budget.failed = true
    return Err(InvalidRootLifetime)
  }
  if root.root.released ||
    root.root.measurement is Some(_) ||
    bytes < 0L ||
    bytes > limit - root.root.bytes {
    budget.failed = true
    return Err(ValueMeasure(WireMeasureFailure))
  }
  if bytes > budget.limits.max_live_value_bytes - budget.live {
    budget.failed = true
    return Err(LiveValueLimit)
  }
  if budget.all_expression_roots &&
    budget.root_result_bytes is Some(ceiling) &&
    bytes > ceiling - root.root.bytes {
    budget.failed = true
    return Err(ValueMeasure(WireMeasureFailure))
  }
  root.root.bytes += bytes
  budget.live += bytes
  budget.peak = Int64::max(budget.peak, budget.live)
  Ok(())
}

///|
fn detach_expression_root(
  lease : ExpressionRootLease,
) -> Result[LogicalRoot, LogicalBudgetIssue] {
  let s = lease.scope
  guard s.slots.get(lease.slot) is Some(Some(root)) else {
    s.budget.failed = true
    return Err(InvalidRootLifetime)
  }
  if !physical_equal(root, lease.root) {
    s.budget.failed = true
    return Err(InvalidRootLifetime)
  }
  s.slots[lease.slot] = None
  s.free.push(lease.slot)
  Ok(root)
}

///|
fn release_expression_root(
  lease : ExpressionRootLease,
) -> Result[Unit, LogicalBudgetIssue] {
  let root = match detach_expression_root(lease) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  release_logical_root(lease.scope.budget, root)
}

///|
fn cleanup_expression_roots(scope : ExpressionRoots) -> Unit {
  for i = 0; i < scope.slots.length(); i = i + 1 {
    if scope.slots[i] is Some(root) {
      release_logical_root(scope.budget, root) |> ignore
      scope.slots[i] = None
    }
  }
  scope.free.clear()
}

///|
priv struct EvaluatedValue {
  value : Value
  root : LogicalRoot?
}
