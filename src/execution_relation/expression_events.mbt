///|
// Shared semantic events for synchronous frames and restricted physical kernels.
// Callers schedule these events in the prescribed row/slot/child order. These
// functions do not authorize speculative evaluation or alternative budget laws.
fn expression_event_entry(
  logical : LogicalBudget?,
  expr : @lower.Expression,
) -> Result[Unit, EvalIssue] {
  if logical is Some(b) {
    match charge_logical_work(b, 1L) {
      Err(issue) => return Err({ kind: LogicalEntry(issue), expression: expr, })
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn expression_event_consume(
  logical : LogicalBudget?,
  value : Value,
  expr : @lower.Expression,
  root? : ExpressionRootLease? = None,
) -> Result[Unit, EvalIssue] {
  if logical is Some(b) {
    match consume_expression_value(b, value, root) {
      Err(issue) => return Err({ kind: LogicalValue(issue), expression: expr, })
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn expression_event_result(
  scope : ExpressionRoots?,
  value : Value,
  root : ExpressionRootLease?,
  expr : @lower.Expression,
  prepaid? : Bool = false,
) -> Result[ExpressionRootLease?, EvalIssue] {
  let result = if prepaid {
    // Only the completed charged cursor can supply this event. Its root must
    // still belong to this exact scope; identity alone is not a work proof.
    guard scope is Some(s) &&
      root is Some(r) &&
      physical_equal(r.scope, s) &&
      physical_equal(r.root.owner, s.budget) &&
      !r.root.released &&
      !s.budget.failed &&
      r.root.measurement is Some(_) &&
      s.slots.get(r.slot) is Some(Some(live)) &&
      physical_equal(live, r.root) else {
      return Err({ kind: LogicalValue(InvalidRootLifetime), expression: expr, })
    }
    Ok(root)
  } else if scope is Some(s) && root is None {
    match track_expression_root(s, value, true) {
      Err(issue) => Err({ kind: LogicalValue(issue), expression: expr, })
      Ok(root) => Ok(Some(root))
    }
  } else {
    match
      expression_event_consume(scope.map(s => s.budget), value, expr, root~) {
      Err(issue) => Err(issue)
      Ok(_) => Ok(root)
    }
  }
  // Acquisition guards include intermediate demanded roots. Reuse the lease's
  // exact measurement: no second evaluation, measurement or logical charge.
  // Failure cleanup remains owned by the enclosing expression frame.
  if result is Ok(Some(lease)) &&
    lease.scope.budget.all_expression_roots &&
    lease.scope.budget.root_result_bytes is Some(ceiling) &&
    lease.root.bytes > ceiling {
    lease.scope.budget.failed = true
    return Err({
      kind: LogicalValue(ValueMeasure(WireMeasureFailure)),
      expression: expr,
    })
  }
  result
}

///|
fn expression_event_release(
  root : ExpressionRootLease?,
  expr : @lower.Expression,
) -> Result[Unit, EvalIssue] {
  if root is Some(r) {
    match release_expression_root(r) {
      Err(issue) => return Err({ kind: LogicalValue(issue), expression: expr, })
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn expression_event_binary(
  logical : LogicalBudget?,
  control : ControlBudget,
  expr : @lower.Expression,
  op : @lower.BinaryOperator,
  left : Value,
  left_root : ExpressionRootLease?,
  right : Value,
  right_root : ExpressionRootLease?,
) -> Result[Value, EvalIssue] {
  match expression_event_consume(logical, left, expr, root=left_root) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match expression_event_consume(logical, right, expr, root=right_root) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match charge_comparison_pair(control, left, right) {
    Ok(_) => ()
    Err(ComparisonChargeLimit) =>
      return Err({ kind: ControlLimit, expression: expr, })
    Err(ComparisonChargeInvalidOperand) =>
      return Err({ kind: Scalar(InvalidOperand), expression: expr, })
  }
  let value = match binary(op, left, right) {
    Err(issue) => return Err({ kind: Scalar(issue), expression: expr, })
    Ok(value) => value
  }
  match expression_event_release(left_root, expr) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match expression_event_release(right_root, expr) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok(value)
}

///|
fn expression_event_choice(
  logical : LogicalBudget?,
  expr : @lower.Expression,
  value : Value,
  root : ExpressionRootLease?,
) -> Result[Bool, EvalIssue] {
  match expression_event_consume(logical, value, expr, root~) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !(value is Null || value is Boolean(_)) {
    return Err({ kind: Scalar(InvalidOperand), expression: expr, })
  }
  match expression_event_release(root, expr) {
    Err(issue) => Err(issue)
    Ok(_) => Ok(value is Boolean(true))
  }
}

///|
/// Consume each evaluated operand exactly once. NULL array means an empty set;
/// it does not erase the left operand's demanded evaluation or value charge.
fn start_membership(
  logical : LogicalBudget?,
  expr : @lower.Expression,
  operation : @lower.BinaryOperator,
  left : Value,
  left_root : ExpressionRootLease?,
  right : Value,
  right_root : ExpressionRootLease?,
) -> Result[MembershipState, EvalIssue] {
  match expression_event_consume(logical, left, expr, root=left_root) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match expression_event_consume(logical, right, expr, root=right_root) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let items = match right {
    Null => None
    Captured(@admitted.Array(items)) => Some(items)
    _ => return Err({ kind: Scalar(InvalidOperand), expression: expr, })
  }
  Ok({
    expression: expr,
    operation,
    left,
    items,
    left_root,
    right_root,
    index: 0,
    matched: false,
    unknown: false,
  })
}

///|
fn membership_compare(
  control : ControlBudget,
  expr : @lower.Expression,
  left : Value,
  right : Value,
) -> Result[Value, EvalIssue] {
  match charge_comparison_pair(control, left, right) {
    Ok(_) => ()
    Err(ComparisonChargeLimit) =>
      return Err({ kind: ControlLimit, expression: expr, })
    Err(ComparisonChargeInvalidOperand) =>
      return Err({ kind: Scalar(InvalidOperand), expression: expr, })
  }
  match binary(@lower.Equal, left, right) {
    Ok(value) => Ok(value)
    Err(issue) => Err({ kind: Scalar(issue), expression: expr, })
  }
}
