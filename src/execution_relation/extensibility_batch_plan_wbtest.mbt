///|
// Non-wire specialization of already checked AoA expressions, not a parser or
// replacement type checker. The bounded shape is deliberately non-recursive.
priv enum ExtBatchAddress {
  Input(Int)
  Slot(Int)
  Constant(Value)
}

///|
priv struct ExtBatchLeaf {
  expr : @lower.Expression
  address : ExtBatchAddress
}

///|
priv enum ExtBatchSimple {
  Leaf(ExtBatchLeaf)
  Pair(@lower.Expression, @lower.BinaryOperator, ExtBatchLeaf, ExtBatchLeaf)
}

///|
priv enum ExtBatchExpr {
  Simple(ExtBatchSimple)
  Choose(@lower.Expression, ExtBatchSimple, ExtBatchSimple, ExtBatchSimple)
}

///|
priv struct ExtBatchPlan {
  kernel : @lower.PreparedKernel
  bindings : Array[(String, @lower.Expression)]
  programs : Array[ExtBatchExpr]
  names : Array[String]
  input_names : Array[String]
  output_addresses : Array[ExtBatchAddress]
}

///|
priv enum ExtBatchChoice {
  Typed(ExtBatchPlan)
  Row(@lower.PreparedKernel)
}

///|
fn ext_choose_batch(
  kernel : @lower.PreparedKernel,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[ExtBatchChoice, RowIssue] {
  match ext_prepare_batch(kernel, control, workspace) {
    Ok(Some(plan)) => Ok(Typed(plan))
    Ok(None) => Ok(Row(kernel))
    Err(e) => Err(e)
  }
}

///|
fn ext_batch_leaf(
  expr : @lower.Expression,
  names : Array[String],
  slot : Int,
) -> ExtBatchLeaf? {
  // Reject array-bearing views before the accessor can copy their children.
  if @lower.expression_view_entries(expr) != 0 {
    return None
  }
  match @lower.expression_contract(expr).shape {
    @contract.Number | @contract.Boolean => ()
    _ => return None
  }
  let address = match @lower.expression_body(expr) {
    @lower.Field(name, @relation.InputField(_)) => {
      let mut found = -1
      for i in 0..<names.length() {
        if names[i] == name {
          found = i
        }
      }
      if found < 0 {
        return None
      }
      Input(found)
    }
    @lower.Field(_, @relation.PriorSlot(i)) => {
      if i < 0 || i >= slot {
        return None
      }
      Slot(i)
    }
    @lower.TypedNull => Constant(Null)
    @lower.Literal(value) => {
      let captured = capture(value.value)
      if !(captured is Null || captured is Number(_) || captured is Boolean(_)) {
        return None
      }
      Constant(captured)
    }
    _ => return None
  }
  Some({ expr, address, })
}

///|
fn ext_batch_simple(
  expr : @lower.Expression,
  names : Array[String],
  slot : Int,
) -> ExtBatchSimple? {
  if @lower.expression_view_entries(expr) != 0 {
    return None
  }
  if ext_batch_leaf(expr, names, slot) is Some(leaf) {
    return Some(Leaf(leaf))
  }
  guard @lower.expression_body(expr) is @lower.Binary(op, left, right) else {
    return None
  }
  if op == @lower.NullIf || op == @lower.In || op == @lower.NotIn {
    return None
  }
  guard ext_batch_leaf(left, names, slot) is Some(l) else { return None }
  guard ext_batch_leaf(right, names, slot) is Some(r) else { return None }
  Some(Pair(expr, op, l, r))
}

///|
fn ext_batch_expr(
  expr : @lower.Expression,
  names : Array[String],
  slot : Int,
) -> ExtBatchExpr? {
  if @lower.expression_view_entries(expr) != 0 {
    return None
  }
  if @lower.expression_body(expr) is @lower.Conditional(condition, yes, no) {
    guard ext_batch_simple(condition, names, slot) is Some(c) else {
      return None
    }
    guard ext_batch_simple(yes, names, slot) is Some(y) else { return None }
    guard ext_batch_simple(no, names, slot) is Some(n) else { return None }
    return Some(Choose(expr, c, y, n))
  }
  ext_batch_simple(expr, names, slot).map(simple => Simple(simple))
}

///|
// None means choose the ordinary row kernel for the WHOLE operation, before
// input evaluation. Budget failure is an error, never a fallback request.
fn ext_prepare_batch(
  kernel : @lower.PreparedKernel,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[ExtBatchPlan?, RowIssue] {
  let count = @lower.kernel_view_entries(kernel)
  let schema = @relation.input_schema(@lower.kernel_checked(kernel))
  let width = @schema.field_count(schema)
  if !spend_control(control, width) || !reserve_slots(workspace, width) {
    return Err(RowLimit)
  }
  let names : Array[String] = []
  for i in 0..<width {
    let field = @schema.field_at(schema, i).unwrap()
    if !(field.contract.shape is @contract.Number ||
      field.contract.shape is @contract.Boolean) {
      return Ok(None)
    }
    let name = @schema.reference_name(field.name)
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    names.push(name)
  }
  if count > 1000 ||
    !spend_control(control, count) ||
    !reserve_slots(workspace, count) {
    return Err(RowLimit)
  }
  let (bindings, ordered) = match @lower.kernel_body(kernel) {
    @lower.OrderedBindings(b) => (b, true)
    @lower.SnapshotMap(b) => (b, false)
    _ => return Ok(None)
  }
  let programs : Array[ExtBatchExpr] = []
  if !spend_control(control, width) ||
    !reserve_slots(workspace, width) ||
    !reserve_slots(workspace, width) {
    return Err(RowLimit)
  }
  let output_names = names.copy()
  let addresses : Array[ExtBatchAddress] = Array::makei(width, i => Input(i))
  for i in 0..<bindings.length() {
    // At most ten nodes per supported root; name-to-ordinal physical binding
    // scans at most width fields per leaf. Precharge that bounded scan/copy.
    if width > 195225600 ||
      !spend_control(control, 11 * (width + 1) + i) ||
      !reserve_slots(workspace, 14) {
      return Err(RowLimit)
    }
    let (name, expr) = bindings[i]
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    if !(@lower.expression_contract(expr).shape is @contract.Number ||
      @lower.expression_contract(expr).shape is @contract.Boolean) {
      return Ok(None)
    }
    guard ext_batch_expr(expr, names, if ordered { i } else { 0 })
      is Some(program) else {
      return Ok(None)
    }
    programs.push(program)
    let mut target = -1
    for j in 0..<output_names.length() {
      if output_names[j] == name {
        target = j
      }
    }
    if target >= 0 {
      if !ordered {
        return Err(InvalidRows)
      }
      addresses[target] = Slot(i)
    } else {
      output_names.push(name)
      addresses.push(Slot(i))
    }
  }
  Ok(
    Some({
      kernel,
      bindings,
      programs,
      names: output_names,
      input_names: names,
      output_addresses: addresses,
    }),
  )
}

///|
priv struct ExtBatchScalar {
  value : Value
  root : ExpressionRootLease?
}

///|
priv struct ExtBatchRead {
  input : LayoutRelation
  row : Int
  slots : Array[LayoutColumn]
  lane : Int
}

///|
fn ext_batch_read(read : ExtBatchRead, address : ExtBatchAddress) -> Value {
  match address {
    Input(column) => IndexedRows::read_cell(read.input, read.row, column)
    Slot(slot) => layout_column_cell(read.slots[slot], read.lane)
    Constant(value) => value
  }
}

///|
fn ext_batch_enter(
  expr : @lower.Expression,
  scope : ExpressionRoots,
  control : ControlBudget,
) -> Result[Unit, EvalIssue] {
  if !spend_control(control, 1) {
    return Err({ kind: ControlLimit, expression: expr, })
  }
  expression_event_entry(Some(scope.budget), expr)
}

///|
fn ext_batch_eval_leaf(
  leaf : ExtBatchLeaf,
  read : ExtBatchRead,
  scope : ExpressionRoots,
  control : ControlBudget,
) -> Result[ExtBatchScalar, EvalIssue] {
  match ext_batch_enter(leaf.expr, scope, control) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let value = ext_batch_read(read, leaf.address)
  match expression_event_result(Some(scope), value, None, leaf.expr) {
    Err(e) => Err(e)
    Ok(root) => Ok({ value, root, })
  }
}

///|
fn ext_batch_eval_simple(
  program : ExtBatchSimple,
  read : ExtBatchRead,
  scope : ExpressionRoots,
  control : ControlBudget,
) -> Result[ExtBatchScalar, EvalIssue] {
  match program {
    Leaf(leaf) => ext_batch_eval_leaf(leaf, read, scope, control)
    Pair(expr, op, left, right) => {
      match ext_batch_enter(expr, scope, control) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      let l = match ext_batch_eval_leaf(left, read, scope, control) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      let r = match ext_batch_eval_leaf(right, read, scope, control) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      let value = match
        expression_event_binary(
          Some(scope.budget),
          control,
          expr,
          op,
          l.value,
          l.root,
          r.value,
          r.root,
        ) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      match expression_event_result(Some(scope), value, None, expr) {
        Err(e) => Err(e)
        Ok(root) => Ok({ value, root, })
      }
    }
  }
}

///|
fn ext_batch_eval(
  program : ExtBatchExpr,
  read : ExtBatchRead,
  scope : ExpressionRoots,
  control : ControlBudget,
  mask : FixedArray[Byte],
) -> Result[ExtBatchScalar, EvalIssue] {
  match program {
    Simple(simple) => ext_batch_eval_simple(simple, read, scope, control)
    Choose(expr, condition, yes, no) => {
      match ext_batch_enter(expr, scope, control) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      let c = match ext_batch_eval_simple(condition, read, scope, control) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      let selected = match
        expression_event_choice(Some(scope.budget), expr, c.value, c.root) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      mask[read.lane] = if selected { 1 } else { 0 }
      let branch = if mask[read.lane] == 1 { yes } else { no }
      let result = match ext_batch_eval_simple(branch, read, scope, control) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      match expression_event_consume(Some(scope.budget), result.value, expr) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      match
        expression_event_result(Some(scope), result.value, result.root, expr) {
        Err(e) => Err(e)
        Ok(root) => Ok({ value: result.value, root, })
      }
    }
  }
}
