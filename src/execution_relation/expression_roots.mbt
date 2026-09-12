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
      Ok(r) => r
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
      Ok(r) => r
      Err(e) => return Err(e)
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
