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
  Property(@lower.Expression, String, Int)
  Object(ObjectExpressionState)
  Cast(@lower.Expression, @lower.Expression)
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
  Membership(MembershipState)
  Score(VectorScoreState)
  Concat(VectorConcatState)
  FinishObject(ObjectExpressionState)
  MeasureObject(ObjectExpressionState, Value, LogicalMeasureCursor)
  MeasureObjectOperand(Value, LogicalMeasureCursor)
}

///|
priv struct ObjectExpressionState {
  expression : @lower.Expression
  fields : Array[(String, @lower.Expression)]
  builder : @admitted.ObjectBuilder
  roots : Array[ExpressionRootLease?]
  root : ExpressionRootLease?
  mut index : Int
}

///|
priv struct MembershipState {
  expression : @lower.Expression
  operation : @lower.BinaryOperator
  left : Value
  items : @admitted.FrozenArray[@admitted.Value]?
  left_root : ExpressionRootLease?
  right_root : ExpressionRootLease?
  mut index : Int
  mut matched : Bool
  mut unknown : Bool
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
  objects : Array[@admitted.ObjectBuilder]
  mut object_context : Int
  mut membership_context : Int
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
    objects: [],
    object_context: 0,
    membership_context: 0,
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
  for builder in frame.objects {
    @admitted.cancel_object_value(builder) |> ignore
  }
  frame.objects.clear()
  frame.object_context = 0
  frame.membership_context = 0
  frame.stack.clear()
  frame.current_root = None
  match frame.state {
    Concat(state) => @admitted.cancel_vector_value(state.builder) |> ignore
    MeasureObject(_, _, cursor) => clear_logical_measure(cursor)
    MeasureObjectOperand(_, cursor) => clear_logical_measure(cursor)
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
  fn charge_value(
    value : Value,
    root : ExpressionRootLease?,
  ) -> LogicalBudgetIssue? {
    match logical_work {
      None => None
      Some(logical) =>
        match consume_expression_value(logical, value, root) {
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
          | Object(_)
          | Property(_, _, _)
          | Cast(_)
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
          Property(child, name, index) => {
            frame.object_context += 1
            frame.stack.push(Property(expr, name, index))
            frame.state = Enter(child)
          }
          Object(fields) => {
            let root = if scope is Some(scope) {
              let budget = scope.budget
              if budget.host_nodes < 1 ||
                budget.host_depth < 1 ||
                budget.host_bytes < 2 ||
                budget.limits.max_value_bytes < 2L {
                return Err({
                  kind: LogicalValue(ValueMeasure(HostMeasureLimit)),
                  expression: expr,
                })
              }
              let root = match reserve_logical_bytes(budget, 2L) {
                Ok(root) => root
                Err(issue) =>
                  return Err({ kind: LogicalValue(issue), expression: expr, })
              }
              match register_scope_root(scope, root) {
                Ok(root) => Some(root)
                Err(issue) =>
                  return Err({ kind: LogicalValue(issue), expression: expr, })
              }
            } else {
              None
            }
            guard fields.get(0) is Some((_, child)) &&
              reserve_slots(workspace, 1) &&
              @admitted.prepare_object_value(fields.length()) is Some(builder) else {
              return Err({ kind: WorkspaceLimit, expression: expr, })
            }
            frame.objects.push(builder)
            frame.object_context += 1
            frame.stack.push(
              Object({
                expression: expr,
                fields,
                builder,
                roots: [],
                root,
                index: 0,
              }),
            )
            frame.state = Enter(child)
          }
          Cast(child) => {
            frame.stack.push(Cast(expr, child))
            frame.state = Enter(child)
          }
          Unary(op, child) => {
            frame.stack.push(Unary(expr, op))
            frame.state = Enter(child)
          }
          Binary(op, left, right) => {
            if op == @lower.In || op == @lower.NotIn {
              frame.membership_context += 1
            }
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
        // A borrowed aggregate still needs an exact measurement before its
        // first semantic consumption. Object/property must not drain a large
        // model output in a single Return transition. Other operation paths
        // retain their existing measurement/charge schedule.
        let object_operand = frame.object_context > 0 ||
          frame.membership_context > 0 ||
          @lower.expression_body(frame.active) is @lower.Property(_, _, _)
        if object_operand &&
          frame.current_root is None &&
          scope is Some(scope) &&
          value is Captured(@admitted.Object(_) | @admitted.Array(_)) {
          let logical = scope.budget
          let cursor = match
            start_logical_measure(
              value,
              logical.limits.max_work - logical.work,
              Int64::min(
                logical.limits.max_value_bytes,
                logical.host_bytes.to_int64(),
              ).to_int(),
              logical.host_nodes,
              logical.host_depth,
            ) {
            Ok(cursor) => cursor
            Err(issue) =>
              return Err({
                kind: LogicalValue(ValueMeasure(issue)),
                expression: frame.active,
              })
          }
          frame.state = MeasureObjectOperand(value, cursor)
          if !drain {
            return Ok(None)
          }
          continue
        }
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
          Property(expr, name, index) => {
            frame.object_context -= 1
            frame.active = expr
            if charge_value(value, frame.current_root) is Some(issue) {
              return Err({ kind: LogicalValue(issue), expression: expr, })
            }
            if !spend_control_text(budget, name) {
              return Err({ kind: ControlLimit, expression: expr, })
            }
            let selected = match value {
              Null => Null
              Captured(@admitted.Object(fields)) => {
                guard @admitted.element_at(fields, index)
                  is Some((actual, selected_value)) &&
                  actual == name else {
                  return Err({ kind: MissingValue, expression: expr, })
                }
                capture(selected_value)
              }
              _ =>
                return Err({ kind: Scalar(InvalidOperand), expression: expr, })
            }
            if release(frame.current_root) is Some(issue) {
              return Err({ kind: LogicalValue(issue), expression: expr, })
            }
            frame.current_root = None
            release_slots(workspace, 1)
            frame.state = Return(selected)
          }
          Object(state) => {
            let expr = state.expression
            frame.active = expr
            if state.root is Some(root) {
              let budget = root.scope.budget
              let measured = match
                consume_expression_value(budget, value, frame.current_root) {
                Ok(measured) => measured
                Err(issue) =>
                  return Err({ kind: LogicalValue(issue), expression: expr, })
              }
              let name_bytes = try {
                let writer = @encode.measuring_writer(budget.host_bytes, 1, 1)
                @encode.string_value(writer, state.fields[state.index].0)
                @encode.finish_measurement(writer)
              } catch {
                _ =>
                  return Err({
                    kind: LogicalValue(ValueMeasure(WireMeasureFailure)),
                    expression: expr,
                  })
              }
              let delta = name_bytes.to_int64() +
                1L +
                measured.wire_bytes.to_int64() +
                (if state.index == 0 { 0L } else { 1L })
              match grow_object_root(root, delta) {
                Ok(_) => ()
                Err(issue) =>
                  return Err({ kind: LogicalValue(issue), expression: expr, })
              }
            }
            // Reserve the field tuple and its retained child before append.
            if !reserve_slots(workspace, 3) {
              return Err({ kind: WorkspaceLimit, expression: expr, })
            }
            if !spend_control_text(budget, state.fields[state.index].0) {
              return Err({ kind: ControlLimit, expression: expr, })
            }
            let admitted = match admitted_aggregate_item(value, budget) {
              Ok(Some(value)) => value
              Ok(None) => @admitted.null_value()
              Err(_) => return Err({ kind: ControlLimit, expression: expr, })
            }
            if !@admitted.append_object_field(
                state.builder,
                state.fields[state.index].0,
                admitted,
              ) {
              return Err({ kind: Scalar(InvalidOperand), expression: expr, })
            }
            state.roots.push(frame.current_root)
            frame.current_root = None
            state.index += 1
            if state.fields.get(state.index) is Some((_, child)) {
              frame.stack.push(Object(state))
              frame.state = Enter(child)
            } else {
              state.index = 0
              frame.state = FinishObject(state)
            }
          }
          Forward(expr) => {
            release_slots(workspace, 1)
            frame.active = expr
            if charge_value(value, frame.current_root) is Some(issue) {
              return Err({ kind: LogicalValue(issue), expression: expr, })
            }
            frame.state = Return(value)
          }
          Unary(expr, op) => {
            release_slots(workspace, 1)
            frame.active = expr
            if charge_value(value, frame.current_root) is Some(issue) {
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
          Cast(expr, child) => {
            release_slots(workspace, 1)
            frame.active = expr
            if charge_value(value, frame.current_root) is Some(issue) {
              return Err({ kind: LogicalValue(issue), expression: expr, })
            }
            let converted = match
              cast_expression_value(expr, child, value, budget) {
              Ok(value) => value
              Err(issue) => return Err(issue)
            }
            if release(frame.current_root) is Some(issue) {
              return Err({ kind: LogicalValue(issue), expression: expr, })
            }
            frame.current_root = None
            frame.state = Return(converted)
          }
          Left(expr, op, right) => {
            frame.stack.push(Right(expr, op, value, frame.current_root))
            frame.current_root = None
            frame.state = Enter(right)
          }
          Right(expr, op, left, left_root) => {
            frame.active = expr
            if op == @lower.In || op == @lower.NotIn {
              let state = match
                start_membership(
                  logical_work,
                  expr,
                  op,
                  left,
                  left_root,
                  value,
                  frame.current_root,
                ) {
                Ok(state) => state
                Err(issue) => return Err(issue)
              }
              frame.current_root = None
              frame.state = Membership(state)
              if !drain {
                return Ok(None)
              }
              continue
            }
            release_slots(workspace, 1)
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
            if charge_value(left, left_root) is Some(issue) {
              release_slots(workspace, 1)
              return Err({ kind: LogicalValue(issue), expression: expr, })
            }
            if charge_value(value, frame.current_root) is Some(issue) {
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
            if charge_value(value, frame.current_root) is Some(issue) {
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
            if charge_value(value, frame.current_root) is Some(issue) {
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
            if charge_value(value, frame.current_root) is Some(issue) {
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
      Membership(state) => {
        frame.active = state.expression
        let item = match state.items {
          Some(items) => @admitted.element_at(items, state.index)
          None => None
        }
        if item is Some(item) {
          // Scan all admitted elements, including duplicates after a match.
          // Comparisons are control work, not synthetic semantic expressions.
          match
            membership_compare(
              budget,
              state.expression,
              state.left,
              capture(item),
            ) {
            Ok(Boolean(true)) => state.matched = true
            Ok(Boolean(false)) => ()
            Ok(Null) => state.unknown = true
            Ok(_) =>
              return Err({
                kind: Scalar(InvalidOperand),
                expression: state.expression,
              })
            Err(issue) => return Err(issue)
          }
          state.index += 1
        } else {
          match expression_event_release(state.left_root, state.expression) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
          }
          match expression_event_release(state.right_root, state.expression) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
          }
          release_slots(workspace, 1)
          frame.membership_context -= 1
          frame.state = Return(
            membership_result(state.operation, state.matched, state.unknown),
          )
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
      FinishObject(state) => {
        frame.active = state.expression
        if state.roots.get(state.index) is Some(root) {
          if release(root) is Some(issue) {
            return Err({
              kind: LogicalValue(issue),
              expression: state.expression,
            })
          }
          state.index += 1
          release_slots(workspace, 1)
        } else {
          guard @admitted.finish_object_value(state.builder) is Some(object) else {
            return Err({
              kind: Scalar(InvalidOperand),
              expression: state.expression,
            })
          }
          frame.objects.pop() |> ignore
          frame.object_context -= 1
          release_slots(workspace, state.fields.length() * 3 + 2)
          let value = Captured(object)
          if state.root is Some(root) {
            let budget = root.scope.budget
            let cursor = match
              start_logical_measure(
                value,
                budget.limits.max_work - budget.work,
                Int64::min(
                  budget.limits.max_value_bytes,
                  budget.host_bytes.to_int64(),
                ).to_int(),
                budget.host_nodes,
                budget.host_depth,
              ) {
              Ok(cursor) => cursor
              Err(issue) =>
                return Err({
                  kind: LogicalValue(ValueMeasure(issue)),
                  expression: state.expression,
                })
            }
            frame.state = MeasureObject(state, value, cursor)
          } else {
            frame.state = Return(value)
          }
        }
      }
      MeasureObject(state, value, cursor) => {
        frame.active = state.expression
        match advance_logical_measure(cursor) {
          Err(issue) =>
            return Err({
              kind: LogicalValue(ValueMeasure(issue)),
              expression: state.expression,
            })
          Ok(None) => ()
          Ok(Some(measured)) => {
            guard state.root is Some(root) &&
              root.root.bytes == measured.wire_bytes.to_int64() else {
              return Err({
                kind: LogicalValue(InvalidRootLifetime),
                expression: state.expression,
              })
            }
            root.root.measurement = Some(measured)
            frame.current_root = Some(root)
            frame.state = Return(value)
          }
        }
      }
      MeasureObjectOperand(value, cursor) =>
        match advance_logical_measure(cursor) {
          Err(issue) =>
            return Err({
              kind: LogicalValue(ValueMeasure(issue)),
              expression: frame.active,
            })
          Ok(None) => ()
          Ok(Some(measured)) => {
            guard scope is Some(scope) else {
              return Err({
                kind: LogicalValue(InvalidRootLifetime),
                expression: frame.active,
              })
            }
            let root = match
              reserve_logical_bytes(
                scope.budget,
                measured.wire_bytes.to_int64(),
              ) {
              Ok(root) => root
              Err(issue) =>
                return Err({
                  kind: LogicalValue(issue),
                  expression: frame.active,
                })
            }
            root.measurement = Some(measured)
            frame.current_root = match register_scope_root(scope, root) {
              Ok(root) => Some(root)
              Err(issue) =>
                return Err({
                  kind: LogicalValue(issue),
                  expression: frame.active,
                })
            }
            // Return pays the same full value weight as synchronous evaluation.
            frame.state = Return(value)
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
