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
) -> Result[Unit, EvalIssue] {
  if logical is Some(b) {
    match charge_logical_value(b, value) {
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
) -> Result[ExpressionRootLease?, EvalIssue] {
  if scope is Some(s) && root is None {
    match track_expression_root(s, value, true) {
      Err(issue) => Err({ kind: LogicalValue(issue), expression: expr, })
      Ok(root) => Ok(Some(root))
    }
  } else {
    match expression_event_consume(scope.map(s => s.budget), value, expr) {
      Err(issue) => Err(issue)
      Ok(_) => Ok(root)
    }
  }
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
  for value in [left, right] {
    match expression_event_consume(logical, value, expr) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if !charge_comparison_operand(control, left) ||
    !charge_comparison_operand(control, right) {
    return Err({ kind: ControlLimit, expression: expr, })
  }
  let value = match binary(op, left, right) {
    Err(issue) => return Err({ kind: Scalar(issue), expression: expr, })
    Ok(value) => value
  }
  for root in [left_root, right_root] {
    match expression_event_release(root, expr) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
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
  match expression_event_consume(logical, value, expr) {
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
