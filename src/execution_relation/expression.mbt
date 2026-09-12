///|
/// Private control kernel, not an admission or fragment execution API. Its
/// caller must supply an admitted row frame. Full value/Relation accounting is
/// a separate integration obligation; these limits bound control work only.
priv struct ControlBudget {
  mut remaining : Int
  max_frames : Int
}

///|
fn spend_control(budget : ControlBudget, units : Int) -> Bool {
  if units < 0 || units > budget.remaining {
    return false
  }
  budget.remaining -= units
  true
}

///|
fn spend_control_text(budget : ControlBudget, text : String) -> Bool {
  match @scalar.admit_utf8_length(text, budget.remaining) {
    Ok(bytes) => spend_control(budget, bytes)
    Err(_) => false
  }
}

///|
pub(all) enum EvalIssueKind {
  InvalidControlLimits
  ControlLimit
  WorkspaceLimit
  MissingValue
  Scalar(ScalarIssue)
  LogicalEntry(LogicalBudgetIssue)
  LogicalValue(LogicalBudgetIssue)
} derive(Eq, Debug)

///|
pub struct EvalIssue {
  kind : EvalIssueKind
  expression : @lower.Expression
}

///|
priv enum Continuation {
  Forward(@lower.Expression)
  Unary(@lower.Expression, @lower.UnaryOperator)
  Left(@lower.Expression, @lower.BinaryOperator, @lower.Expression)
  Right(@lower.Expression, @lower.BinaryOperator, Value, ExpressionRootLease?)
  Choose(@lower.Expression, @lower.Expression, @lower.Expression)
  Many(
    @lower.Expression,
    @lower.ManyOperator,
    Array[@lower.Expression],
    Int,
    Value,
    ExpressionRootLease?
  )
  Case(
    @lower.Expression,
    Array[(@lower.Expression, @lower.Expression)],
    Int,
    @lower.Expression
  )
}

///|
priv enum Evaluation {
  Enter(@lower.Expression)
  Return(Value)
}

///|
fn evaluate_expression_with_workspace(
  root : @lower.Expression,
  input : Map[String, Value],
  slots : Array[Value],
  budget : ControlBudget,
  workspace : RowWorkspace,
  logical_work? : LogicalBudget? = None,
) -> Result[Value, EvalIssue] {
  match
    evaluate_expression_retained(
      root,
      input,
      slots,
      budget,
      workspace,
      logical_work~,
    ) {
    Err(e) => Err(e)
    Ok(result) => {
      if result.root is Some(lease) {
        match release_logical_root(lease.owner, lease) {
          Ok(_) => ()
          Err(e) => return Err({ kind: LogicalValue(e), expression: root, })
        }
      }
      Ok(result.value)
    }
  }
}

///|
fn evaluate_expression_retained(
  root : @lower.Expression,
  input : Map[String, Value],
  slots : Array[Value],
  budget : ControlBudget,
  workspace : RowWorkspace,
  logical_work? : LogicalBudget? = None,
) -> Result[EvaluatedValue, EvalIssue] {
  let scope = logical_work.map(b => expression_roots(b, budget.max_frames))
  let result = evaluate_expression_impl(
    root, input, slots, budget, workspace, scope,
  )
  if result is Err(_) && logical_work is Some(logical) {
    logical.failed = true
  }
  // Frames close their temporary roots on success/failure. Invalid frame
  // construction has not created any roots; detached results belong to callers.
  result
}

///|
/// A resumable semantic frame. Advancing is not permission to reorder logical
/// rows/slots: the caller still owns that schedule. Input and slot values are
/// borrowed for the frame lifetime; the expression scope owns temporary roots.
priv struct ExpressionFrame {
  root : @lower.Expression
  input : Map[String, Value]
  slots : Array[Value]
  budget : ControlBudget
  workspace : RowWorkspace
  scope : ExpressionRoots?
  stack : Array[Continuation]
  mut state : Evaluation
  mut active : @lower.Expression
  mut current_root : ExpressionRootLease?
  mut closed : Bool
}

///|
fn expression_frame(
  root : @lower.Expression,
  input : Map[String, Value],
  slots : Array[Value],
  budget : ControlBudget,
  workspace : RowWorkspace,
  scope : ExpressionRoots?,
) -> Result[ExpressionFrame, EvalIssue] {
  if budget.remaining < 0 ||
    budget.max_frames < 0 ||
    workspace.limit < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit {
    return Err({ kind: InvalidControlLimits, expression: root, })
  }
  Ok({
    root,
    input,
    slots,
    budget,
    workspace,
    scope,
    stack: [],
    state: Enter(root),
    active: root,
    current_root: None,
    closed: false,
  })
}

///|
/// Cancellation releases temporary roots, without refunding cumulative work or
/// releasing caller-owned input/slot roots. Successful result roots are detached.
fn close_expression_frame(frame : ExpressionFrame) -> Unit {
  if frame.scope is Some(scope) {
    cleanup_expression_roots(scope)
  }
  frame.stack.clear()
  frame.current_root = None
  frame.state = Return(Null)
  frame.closed = true
}

///|
fn advance_expression_frame(
  frame : ExpressionFrame,
) -> Result[EvaluatedValue?, EvalIssue] {
  if frame.closed {
    return Err({ kind: InvalidControlLimits, expression: frame.root, })
  }
  let result = advance_expression_frame_impl(frame)
  match result {
    Err(_) => {
      if frame.scope is Some(scope) {
        scope.budget.failed = true
      }
      close_expression_frame(frame)
    }
    Ok(Some(_)) => close_expression_frame(frame)
    Ok(None) => ()
  }
  result
}

///|
fn evaluate_expression_impl(
  root : @lower.Expression,
  input : Map[String, Value],
  slots : Array[Value],
  budget : ControlBudget,
  workspace : RowWorkspace,
  scope : ExpressionRoots?,
) -> Result[EvaluatedValue, EvalIssue] {
  let frame = match
    expression_frame(root, input, slots, budget, workspace, scope) {
    Ok(frame) => frame
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_expression_frame(frame) {
      Ok(None) => ()
      Ok(Some(value)) => return Ok(value)
      Err(issue) => return Err(issue)
    }
  } nobreak {
    Err({ kind: ControlLimit, expression: root, })
  }
}

///|
fn advance_expression_frame_impl(
  frame : ExpressionFrame,
) -> Result[EvaluatedValue?, EvalIssue] {
  let input = frame.input
  let slots = frame.slots
  let budget = frame.budget
  let workspace = frame.workspace
  let scope = frame.scope
  let logical_work = scope.map(s => s.budget)
  fn release(root : ExpressionRootLease?) -> LogicalBudgetIssue? {
    match root {
      None => None
      Some(r) =>
        match release_expression_root(r) {
          Ok(_) => None
          Err(e) => Some(e)
        }
    }
  }
  fn charge_value(value : Value) -> LogicalBudgetIssue? {
    match logical_work {
      None => None
      Some(logical) =>
        match charge_logical_value(logical, value) {
          Ok(_) => None
          Err(issue) => Some(issue)
        }
    }
  }
  if budget.remaining == 0 {
    return Err({ kind: ControlLimit, expression: frame.active, })
  }
  budget.remaining = budget.remaining - 1
  match frame.state {
    Enter(expr) => {
      frame.active = expr
      // Input/slot/output row lifetimes belong to the enclosing row kernel.
      if logical_work is Some(logical) {
        match charge_logical_work(logical, 1L) {
          Ok(_) => ()
          Err(issue) =>
            return Err({ kind: LogicalEntry(issue), expression: expr, })
        }
      }
      // Ancestor views stay reserved while descendants evaluate.
      let entries = @lower.expression_view_entries(expr)
      if !reserve_slots(workspace, entries) {
        return Err({ kind: WorkspaceLimit, expression: expr, })
      }
      if !spend_control(budget, entries) {
        return Err({ kind: ControlLimit, expression: expr, })
      }
      let body = @lower.expression_body(expr)
      let leaf = match body {
        Field(_, _) | Literal(_) | TypedNull => true
        Unary(_, _)
        | Binary(_, _, _)
        | Many(_, _)
        | Conditional(_, _, _)
        | Case(_, _) => false
      }
      if !leaf && frame.stack.length() >= budget.max_frames {
        return Err({ kind: ControlLimit, expression: expr, })
      }
      if !leaf && !reserve_slots(workspace, 1) {
        return Err({ kind: WorkspaceLimit, expression: expr, })
      }
      match body {
        Field(name, target) => {
          if !spend_control_text(budget, name) {
            return Err({ kind: ControlLimit, expression: expr, })
          }
          let value = match target {
            @relation.InputField(_) => input.get(name)
            @relation.PriorSlot(i) => slots.get(i)
          }
          guard value is Some(value) else {
            return Err({ kind: MissingValue, expression: expr, })
          }
          frame.state = Return(value)
        }
        Literal(value) => frame.state = Return(capture(value.value))
        TypedNull => frame.state = Return(Null)
        Unary(op, child) => {
          frame.stack.push(Unary(expr, op))
          frame.state = Enter(child)
        }
        Binary(op, left, right) => {
          frame.stack.push(Left(expr, op, right))
          frame.state = Enter(left)
        }
        Conditional(condition, yes, no) => {
          frame.stack.push(Choose(expr, yes, no))
          frame.state = Enter(condition)
        }
        Many(op, children) => {
          guard children.get(0) is Some(first) else {
            return Err({ kind: Scalar(InvalidOperand), expression: expr, })
          }
          let initial = match op {
            And => Boolean(true)
            Or => Boolean(false)
            Coalesce => Null
          }
          frame.stack.push(Many(expr, op, children, 0, initial, None))
          frame.state = Enter(first)
        }
        Case(clauses, otherwise) =>
          if clauses.get(0) is Some((condition, _)) {
            frame.stack.push(Case(expr, clauses, 0, otherwise))
            frame.state = Enter(condition)
          } else {
            frame.stack.push(Forward(expr))
            frame.state = Enter(otherwise)
          }
      }
    }
    Return(value) => {
      // Every Return completes one semantic expression, including selection
      // nodes forwarded from their chosen child. Internal boolean seeds and
      // fold accumulators do not invent extra semantic expression results.
      if scope is Some(s) && frame.current_root is None {
        match track_expression_root(s, value, true) {
          Ok(r) => frame.current_root = Some(r)
          Err(e) =>
            return Err({ kind: LogicalValue(e), expression: frame.active, })
        }
      } else if charge_value(value) is Some(issue) {
        return Err({ kind: LogicalValue(issue), expression: frame.active, })
      }
      guard frame.stack.pop() is Some(continuation) else {
        let retained = match frame.current_root {
          None => None
          Some(r) =>
            match detach_expression_root(r) {
              Ok(root) => Some(root)
              Err(e) =>
                return Err({ kind: LogicalValue(e), expression: frame.active, })
            }
        }
        return Ok(Some({ value, root: retained, }))
      }
      match continuation {
        Forward(expr) => {
          release_slots(workspace, 1)
          frame.active = expr
          if charge_value(value) is Some(issue) {
            return Err({ kind: LogicalValue(issue), expression: expr, })
          }
          frame.state = Return(value)
        }
        Unary(expr, op) => {
          release_slots(workspace, 1)
          frame.active = expr
          if charge_value(value) is Some(issue) {
            return Err({ kind: LogicalValue(issue), expression: expr, })
          }
          match unary(op, value) {
            Ok(v) => {
              if release(frame.current_root) is Some(e) {
                return Err({ kind: LogicalValue(e), expression: expr, })
              }
              frame.current_root = None
              frame.state = Return(v)
            }
            Err(e) => return Err({ kind: Scalar(e), expression: expr, })
          }
        }
        Left(expr, op, right) => {
          frame.stack.push(Right(expr, op, value, frame.current_root))
          frame.current_root = None
          frame.state = Enter(right)
        }
        Right(expr, op, left, left_root) => {
          release_slots(workspace, 1)
          frame.active = expr
          for operand in [left, value] {
            if charge_value(operand) is Some(issue) {
              return Err({ kind: LogicalValue(issue), expression: expr, })
            }
          }
          // Bound variable-size comparison work before the comparison.
          // Values are already canonical: never normalize inside compare.
          if !charge_comparison_operand(budget, left) ||
            !charge_comparison_operand(budget, value) {
            return Err({ kind: ControlLimit, expression: expr, })
          }
          match binary(op, left, value) {
            Ok(v) => {
              for r in [left_root, frame.current_root] {
                if release(r) is Some(e) {
                  return Err({ kind: LogicalValue(e), expression: expr, })
                }
              }
              frame.current_root = None
              frame.state = Return(v)
            }
            Err(e) => return Err({ kind: Scalar(e), expression: expr, })
          }
        }
        Choose(expr, yes, no) => {
          if charge_value(value) is Some(issue) {
            return Err({ kind: LogicalValue(issue), expression: expr, })
          }
          if !(value is Null || value is Boolean(_)) {
            return Err({ kind: Scalar(InvalidOperand), expression: expr, })
          }
          if release(frame.current_root) is Some(e) {
            return Err({ kind: LogicalValue(e), expression: expr, })
          }
          frame.current_root = None
          frame.stack.push(Forward(expr))
          frame.state = Enter(if value is Boolean(true) { yes } else { no })
        }
        Many(expr, op, children, index, previous, previous_root) => {
          frame.active = expr
          if charge_value(value) is Some(issue) {
            return Err({ kind: LogicalValue(issue), expression: expr, })
          }
          let combined = match op {
            Coalesce => value
            And | Or =>
              match boolean_pair(op, previous, value) {
                Ok(v) => v
                Err(e) => return Err({ kind: Scalar(e), expression: expr, })
              }
          }
          if release(previous_root) is Some(e) {
            return Err({ kind: LogicalValue(e), expression: expr, })
          }
          if op == @lower.Coalesce && !(combined is Null) {
            release_slots(workspace, children.length())
            release_slots(workspace, 1)
            frame.state = Return(combined)
          } else if children.get(index + 1) is Some(next) {
            if release(frame.current_root) is Some(e) {
              return Err({ kind: LogicalValue(e), expression: expr, })
            }
            frame.current_root = None
            let accumulator = if op != @lower.Coalesce && scope is Some(s) {
              match track_expression_root(s, combined, false) {
                Ok(r) => Some(r)
                Err(e) =>
                  return Err({ kind: LogicalValue(e), expression: expr, })
              }
            } else {
              None
            }
            frame.stack.push(
              Many(expr, op, children, index + 1, combined, accumulator),
            )
            frame.state = Enter(next)
          } else {
            release_slots(workspace, children.length())
            release_slots(workspace, 1)
            // Coalesce can transfer its final null root unchanged; boolean
            // reduction can change wire size and produces a fresh result.
            if op != @lower.Coalesce {
              if release(frame.current_root) is Some(e) {
                return Err({ kind: LogicalValue(e), expression: expr, })
              }
              frame.current_root = None
            }
            frame.state = Return(combined)
          }
        }
        Case(expr, clauses, index, otherwise) => {
          if charge_value(value) is Some(issue) {
            return Err({ kind: LogicalValue(issue), expression: expr, })
          }
          if !(value is Null || value is Boolean(_)) {
            return Err({ kind: Scalar(InvalidOperand), expression: expr, })
          }
          if release(frame.current_root) is Some(e) {
            return Err({ kind: LogicalValue(e), expression: expr, })
          }
          frame.current_root = None
          if value is Boolean(true) {
            release_slots(workspace, clauses.length())
            frame.stack.push(Forward(expr))
            frame.state = Enter(clauses[index].1)
          } else if clauses.get(index + 1) is Some((condition, _)) {
            frame.stack.push(Case(expr, clauses, index + 1, otherwise))
            frame.state = Enter(condition)
          } else {
            release_slots(workspace, clauses.length())
            frame.stack.push(Forward(expr))
            frame.state = Enter(otherwise)
          }
        }
      }
    }
  }
  Ok(None)
}
