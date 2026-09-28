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
  VectorLeft(@lower.Expression, @lower.VectorMetric, @lower.Expression)
  VectorRight(
    @lower.Expression,
    @lower.VectorMetric,
    Value,
    ExpressionRootLease?
  )
  VectorConcat(
    @lower.Expression,
    Array[@lower.Expression],
    Int,
    Array[@admitted.FrozenArray[Double]?],
    Array[ExpressionRootLease?],
    Bool,
    Int
  )
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
  Score(VectorScoreState)
  Concat(VectorConcatState)
}

///|
priv struct VectorScoreState {
  expression : @lower.Expression
  fold : @vector.ScoreFold
  left : @admitted.FrozenArray[Double]
  right : @admitted.FrozenArray[Double]
  left_root : ExpressionRootLease?
  right_root : ExpressionRootLease?
  mut index : Int
}

///|
priv struct VectorConcatState {
  expression : @lower.Expression
  builder : @admitted.VectorBuilder
  vectors : Array[@admitted.FrozenArray[Double]?]
  roots : Array[ExpressionRootLease?]
  expected_dimension : Int
  mut child : Int
  mut component : Int
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
  release_expression_result(
    root,
    evaluate_expression_retained(
      root,
      input,
      slots,
      budget,
      workspace,
      logical_work~,
    ),
  )
}

///|
fn release_expression_result(
  root : @lower.Expression,
  result : Result[EvaluatedValue, EvalIssue],
) -> Result[Value, EvalIssue] {
  match result {
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
  check_expression_result(root, result, logical_work)
}

///|
/// Apply the same detached-root limit to draining and resumable callers.
fn check_expression_result(
  root : @lower.Expression,
  result : Result[EvaluatedValue, EvalIssue],
  logical_work : LogicalBudget?,
) -> Result[EvaluatedValue, EvalIssue] {
  // The final-root ceiling is separate from retained-row limits. Acquisition
  // mode also checks intermediate roots in the shared result event. Reuse the
  // already measured successful root;
  // never reevaluate it, double-charge it, or inspect an undemanded branch.
  if result is Ok(value) &&
    value.root is Some(retained) &&
    logical_work is Some(logical) &&
    logical.root_result_bytes is Some(ceiling) &&
    retained.bytes > ceiling {
    release_logical_root(logical, retained) |> ignore
    logical.failed = true
    return Err({
      kind: LogicalValue(ValueMeasure(WireMeasureFailure)),
      expression: root,
    })
  }
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
  workspace_baseline : Int
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
    workspace_baseline: workspace.live,
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
  match frame.state {
    Concat(state) => @admitted.cancel_vector_value(state.builder) |> ignore
    _ => ()
  }
  if frame.workspace.live > frame.workspace_baseline {
    release_slots(
      frame.workspace,
      frame.workspace.live - frame.workspace_baseline,
    )
  }
  frame.state = Return(Null)
  frame.closed = true
}

///|
fn advance_expression_frame(
  frame : ExpressionFrame,
  drain? : Bool = false,
) -> Result[EvaluatedValue?, EvalIssue] {
  if frame.closed {
    return Err({ kind: InvalidControlLimits, expression: frame.root, })
  }
  let result = advance_expression_frame_impl(frame, drain)
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
    match advance_expression_frame(frame, drain=true) {
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
  drain : Bool,
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
  while true {
    if budget.remaining == 0 {
      return Err({ kind: ControlLimit, expression: frame.active, })
    }
    budget.remaining = budget.remaining - 1
    match frame.state {
      Enter(expr) => {
        frame.active = expr
        // Input/slot/output row lifetimes belong to the enclosing row kernel.
        match expression_event_entry(logical_work, expr) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
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
          | VectorScore(_, _, _)
          | VectorConcat(_)
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
          VectorScore(metric, left, right) => {
            frame.stack.push(VectorLeft(expr, metric, right))
            frame.state = Enter(left)
          }
          VectorConcat(children) => {
            guard children.length() >= 2 &&
              @lower.expression_contract(expr).shape
              is @contract.Vector(dimensions~) &&
              dimensions >= 1.0 &&
              dimensions <= 2147483647.0 else {
              return Err({ kind: Scalar(InvalidOperand), expression: expr, })
            }
            let expected_dimension = dimensions.to_int()
            guard expected_dimension.to_double() == dimensions &&
              children.length() <= (workspace.limit - workspace.live) / 2 &&
              reserve_slots(workspace, children.length() * 2) else {
              return Err({ kind: WorkspaceLimit, expression: expr, })
            }
            frame.stack.push(
              VectorConcat(
                expr,
                children,
                0,
                Array::make(children.length(), None),
                Array::make(children.length(), None),
                false,
                expected_dimension,
              ),
            )
            frame.state = Enter(children[0])
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
              Concat | ConcatStrict => Text("")
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
        frame.current_root = match
          expression_event_result(
            scope,
            value,
            frame.current_root,
            frame.active,
          ) {
          Ok(root) => root
          Err(issue) => return Err(issue)
        }
        guard frame.stack.pop() is Some(continuation) else {
          let retained = match frame.current_root {
            None => None
            Some(r) =>
              match detach_expression_root(r) {
                Ok(root) => Some(root)
                Err(e) =>
                  return Err({
                    kind: LogicalValue(e),
                    expression: frame.active,
                  })
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
            let result = match
              expression_event_binary(
                logical_work,
                budget,
                expr,
                op,
                left,
                left_root,
                value,
                frame.current_root,
              ) {
              Ok(result) => result
              Err(issue) => return Err(issue)
            }
            frame.current_root = None
            frame.state = Return(result)
          }
          VectorLeft(expr, metric, right) => {
            frame.stack.push(
              VectorRight(expr, metric, value, frame.current_root),
            )
            frame.current_root = None
            frame.state = Enter(right)
          }
          VectorRight(expr, metric, left, left_root) => {
            frame.active = expr
            if charge_value(left) is Some(issue) {
              release_slots(workspace, 1)
              return Err({ kind: LogicalValue(issue), expression: expr, })
            }
            if charge_value(value) is Some(issue) {
              release_slots(workspace, 1)
              return Err({ kind: LogicalValue(issue), expression: expr, })
            }
            let right_root = frame.current_root
            if left is Null || value is Null {
              if release(left_root) is Some(issue) {
                return Err({ kind: LogicalValue(issue), expression: expr, })
              }
              if release(right_root) is Some(issue) {
                return Err({ kind: LogicalValue(issue), expression: expr, })
              }
              frame.current_root = None
              release_slots(workspace, 1)
              frame.state = Return(Null)
            } else {
              guard left is Captured(@admitted.Vector(left_values)) &&
                value is Captured(@admitted.Vector(right_values)) &&
                @admitted.element_count(left_values) ==
                @admitted.element_count(right_values) &&
                @admitted.element_count(left_values) > 0 else {
                release_slots(workspace, 1)
                return Err({ kind: Scalar(InvalidOperand), expression: expr, })
              }
              frame.current_root = None
              frame.state = Score({
                expression: expr,
                fold: @vector.prepare_score(
                  match metric {
                    @lower.Cosine => @vector.Cosine
                    @lower.Dot => @vector.Dot
                    @lower.L2 => @vector.L2
                  },
                ),
                left: left_values,
                right: right_values,
                left_root,
                right_root,
                index: 0,
              })
            }
          }
          VectorConcat(
            expr,
            children,
            index,
            vectors,
            roots,
            null_seen,
            expected_dimension
          ) => {
            frame.active = expr
            if charge_value(value) is Some(issue) {
              return Err({ kind: LogicalValue(issue), expression: expr, })
            }
            let mut next_null = null_seen
            match value {
              Null => {
                next_null = true
                if release(frame.current_root) is Some(issue) {
                  return Err({ kind: LogicalValue(issue), expression: expr, })
                }
              }
              Captured(@admitted.Vector(vector)) => {
                vectors[index] = Some(vector)
                roots[index] = frame.current_root
              }
              _ =>
                return Err({ kind: Scalar(InvalidOperand), expression: expr, })
            }
            frame.current_root = None
            if children.get(index + 1) is Some(next) {
              frame.stack.push(
                VectorConcat(
                  expr,
                  children,
                  index + 1,
                  vectors,
                  roots,
                  next_null,
                  expected_dimension,
                ),
              )
              frame.state = Enter(next)
            } else if next_null {
              for root in roots {
                if release(root) is Some(issue) {
                  return Err({ kind: LogicalValue(issue), expression: expr, })
                }
              }
              release_slots(workspace, children.length() * 3 + 1)
              frame.state = Return(Null)
            } else {
              let tail_overhead = children.length() + 2
              if tail_overhead > budget.remaining ||
                expected_dimension > budget.remaining - tail_overhead {
                return Err({ kind: ControlLimit, expression: expr, })
              }
              guard reserve_slots(workspace, expected_dimension) &&
                @admitted.prepare_vector_value(expected_dimension)
                is Some(builder) else {
                return Err({ kind: WorkspaceLimit, expression: expr, })
              }
              frame.state = Concat({
                expression: expr,
                builder,
                vectors,
                roots,
                expected_dimension,
                child: 0,
                component: 0,
              })
            }
          }
          Choose(expr, yes, no) => {
            let selected = match
              expression_event_choice(
                logical_work,
                expr,
                value,
                frame.current_root,
              ) {
              Ok(selected) => selected
              Err(issue) => return Err(issue)
            }
            frame.current_root = None
            frame.stack.push(Forward(expr))
            frame.state = Enter(if selected { yes } else { no })
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
              Concat | ConcatStrict =>
                match (previous, value) {
                  (Text(prefix), Text(part)) => {
                    let cap = match logical_work {
                      Some(b) =>
                        Int64::min(
                          b.limits.max_value_bytes,
                          b.host_bytes.to_int64(),
                        ).to_int()
                      None => 2147483647
                    }
                    let prefix_bytes = match
                      @scalar.admit_utf8_length(prefix, cap) {
                      Ok(n) => n
                      Err(_) =>
                        return Err({ kind: ControlLimit, expression: expr, })
                    }
                    let part_bytes = match
                      @scalar.admit_utf8_length(part, cap - prefix_bytes) {
                      Ok(n) => n
                      Err(_) =>
                        return Err({ kind: ControlLimit, expression: expr, })
                    }
                    if !spend_control(budget, prefix_bytes + part_bytes) {
                      return Err({ kind: ControlLimit, expression: expr, })
                    }
                    Text(prefix + part)
                  }
                  (Text(prefix), Null) =>
                    if op == @lower.Concat {
                      Text(prefix)
                    } else {
                      Null
                    }
                  (Null, Text(_) | Null) if op == @lower.ConcatStrict => Null
                  _ =>
                    return Err({
                      kind: Scalar(InvalidOperand),
                      expression: expr,
                    })
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
      Score(score) => {
        frame.active = score.expression
        if score.index < @admitted.element_count(score.left) {
          guard @admitted.element_at(score.left, score.index) is Some(left) &&
            @admitted.element_at(score.right, score.index) is Some(right) else {
            release_slots(workspace, 1)
            return Err({
              kind: Scalar(InvalidOperand),
              expression: score.expression,
            })
          }
          match @vector.score_step(score.fold, left, right) {
            Ok(_) => score.index += 1
            Err(_) => {
              release_slots(workspace, 1)
              return Err({
                kind: Scalar(ArithmeticFailure),
                expression: score.expression,
              })
            }
          }
        } else {
          let result = match @vector.finish_score(score.fold) {
            Ok(value) => value
            Err(_) => {
              release_slots(workspace, 1)
              return Err({
                kind: Scalar(ArithmeticFailure),
                expression: score.expression,
              })
            }
          }
          if release(score.left_root) is Some(issue) {
            release_slots(workspace, 1)
            return Err({
              kind: LogicalValue(issue),
              expression: score.expression,
            })
          }
          if release(score.right_root) is Some(issue) {
            release_slots(workspace, 1)
            return Err({
              kind: LogicalValue(issue),
              expression: score.expression,
            })
          }
          release_slots(workspace, 1)
          frame.state = Return(Number(result))
        }
      }
      Concat(concat) => {
        frame.active = concat.expression
        if concat.vectors.get(concat.child) is Some(Some(vector)) {
          if @admitted.element_at(vector, concat.component) is Some(component) {
            if !@admitted.append_vector_component(concat.builder, component) {
              return Err({
                kind: Scalar(InvalidOperand),
                expression: concat.expression,
              })
            }
            concat.component += 1
          } else {
            concat.child += 1
            concat.component = 0
          }
        } else if concat.child < concat.vectors.length() {
          return Err({
            kind: Scalar(InvalidOperand),
            expression: concat.expression,
          })
        } else {
          guard @contract.vector_contract(
              concat.expected_dimension.to_double(),
              nullable=false,
            )
            is Some(contract) &&
            @admitted.finish_checked_vector_value(concat.builder, contract)
            is Some(checked) else {
            return Err({
              kind: Scalar(InvalidOperand),
              expression: concat.expression,
            })
          }
          for root in concat.roots {
            if release(root) is Some(issue) {
              return Err({
                kind: LogicalValue(issue),
                expression: concat.expression,
              })
            }
          }
          release_slots(
            workspace,
            concat.vectors.length() * 3 + 1 + concat.expected_dimension,
          )
          frame.state = Return(Captured(checked.value))
        }
      }
    }
    if !drain {
      return Ok(None)
    }
  } nobreak {
    Err({ kind: ControlLimit, expression: frame.active, })
  }
}
