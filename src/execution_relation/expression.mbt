///|
/// Private control kernel, not an admission or fragment execution API. Its
/// caller must supply an admitted row frame. Full value/Relation accounting is
/// a separate integration obligation; these limits bound control work only.
priv struct ControlBudget {
  mut remaining : Int
  max_frames : Int
}

///|
priv enum EvalIssueKind {
  InvalidControlLimits
  ControlLimit
  MissingValue
  Scalar(ScalarIssue)
} derive(Eq, Debug)

///|
priv struct EvalIssue {
  kind : EvalIssueKind
  expression : @lower.Expression
}

///|
priv enum Continuation {
  Unary(@lower.Expression, @lower.UnaryOperator)
  Left(@lower.Expression, @lower.BinaryOperator, @lower.Expression)
  Right(@lower.Expression, @lower.BinaryOperator, Value)
  Choose(@lower.Expression, @lower.Expression, @lower.Expression)
  Many(
    @lower.Expression,
    @lower.ManyOperator,
    Array[@lower.Expression],
    Int,
    Value
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
fn evaluate_expression(
  root : @lower.Expression,
  input : Map[String, Value],
  slots : Array[Value],
  budget : ControlBudget,
) -> Result[Value, EvalIssue] {
  if budget.remaining < 0 || budget.max_frames < 0 {
    return Err({ kind: InvalidControlLimits, expression: root, })
  }
  let stack : Array[Continuation] = []
  let mut state = Enter(root)
  let mut active = root
  while true {
    if budget.remaining == 0 {
      return Err({ kind: ControlLimit, expression: active, })
    }
    budget.remaining = budget.remaining - 1
    match state {
      Enter(expr) => {
        active = expr
        // Lowering bounds the defensive-copy expression view's size;
        // execution-side live-value accounting is
        // still required before this kernel is connected to a fragment API.
        let body = @lower.expression_body(expr)
        let leaf = match body {
          Field(_, _) | Literal(_) | TypedNull => true
          Unary(_, _)
          | Binary(_, _, _)
          | Many(_, _)
          | Conditional(_, _, _)
          | Case(_, _) => false
        }
        if !leaf && stack.length() >= budget.max_frames {
          return Err({ kind: ControlLimit, expression: expr, })
        }
        match body {
          Field(name, target) => {
            let value = match target {
              @relation.InputField(_) => input.get(name)
              @relation.PriorSlot(i) => slots.get(i)
            }
            guard value is Some(value) else {
              return Err({ kind: MissingValue, expression: expr, })
            }
            state = Return(value)
          }
          Literal(value) => state = Return(capture(value.value))
          TypedNull => state = Return(Null)
          Unary(op, child) => {
            stack.push(Unary(expr, op))
            state = Enter(child)
          }
          Binary(op, left, right) => {
            stack.push(Left(expr, op, right))
            state = Enter(left)
          }
          Conditional(condition, yes, no) => {
            stack.push(Choose(expr, yes, no))
            state = Enter(condition)
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
            stack.push(Many(expr, op, children, 0, initial))
            state = Enter(first)
          }
          Case(clauses, otherwise) =>
            if clauses.get(0) is Some((condition, _)) {
              stack.push(Case(expr, clauses, 0, otherwise))
              state = Enter(condition)
            } else {
              state = Enter(otherwise)
            }
        }
      }
      Return(value) => {
        guard stack.pop() is Some(frame) else { return Ok(value) }
        match frame {
          Unary(expr, op) => {
            active = expr
            match unary(op, value) {
              Ok(v) => state = Return(v)
              Err(e) => return Err({ kind: Scalar(e), expression: expr, })
            }
          }
          Left(expr, op, right) => {
            stack.push(Right(expr, op, value))
            state = Enter(right)
          }
          Right(expr, op, left) => {
            active = expr
            match binary(op, left, value) {
              Ok(v) => state = Return(v)
              Err(e) => return Err({ kind: Scalar(e), expression: expr, })
            }
          }
          Choose(expr, yes, no) => {
            if !(value is Null || value is Boolean(_)) {
              return Err({ kind: Scalar(InvalidOperand), expression: expr, })
            }
            state = Enter(if value is Boolean(true) { yes } else { no })
          }
          Many(expr, op, children, index, previous) => {
            active = expr
            let combined = match op {
              Coalesce => value
              And | Or =>
                match boolean_pair(op, previous, value) {
                  Ok(v) => v
                  Err(e) => return Err({ kind: Scalar(e), expression: expr, })
                }
            }
            if op == @lower.Coalesce && !(combined is Null) {
              state = Return(combined)
            } else if children.get(index + 1) is Some(next) {
              stack.push(Many(expr, op, children, index + 1, combined))
              state = Enter(next)
            } else {
              state = Return(combined)
            }
          }
          Case(expr, clauses, index, otherwise) => {
            if !(value is Null || value is Boolean(_)) {
              return Err({ kind: Scalar(InvalidOperand), expression: expr, })
            }
            if value is Boolean(true) {
              state = Enter(clauses[index].1)
            } else if clauses.get(index + 1) is Some((condition, _)) {
              stack.push(Case(expr, clauses, index + 1, otherwise))
              state = Enter(condition)
            } else {
              state = Enter(otherwise)
            }
          }
        }
      }
    }
  } nobreak {
    Err({ kind: ControlLimit, expression: active, })
  }
}
