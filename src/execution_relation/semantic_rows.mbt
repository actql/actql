///|
/// Internal total order whose equality classes are the normative complete-value
/// equality classes used by row-set operations. Ordering between unlike JSON
/// kinds is private and unobservable; it only groups equal rows efficiently.
fn compare_complete_value(
  left : Value,
  right : Value,
  control : ControlBudget,
) -> Result[Int, OrderingIssue] {
  if !spend_control(control, 1) {
    return Err(Limit)
  }
  match (left, right) {
    (Null, Null) => Ok(0)
    (Number(a), Number(b)) =>
      compare_complete_scalar(Number(a), Number(b), control)
    (Boolean(a), Boolean(b)) =>
      compare_complete_scalar(Boolean(a), Boolean(b), control)
    (Text(a), Text(b)) => compare_complete_scalar(Text(a), Text(b), control)
    (Captured(a), Captured(b)) => compare_admitted_value(a, b, control)
    _ => Ok(Int::compare(value_rank(left), value_rank(right)))
  }
}

///|
fn compare_complete_scalar(
  left : Value,
  right : Value,
  control : ControlBudget,
) -> Result[Int, OrderingIssue] {
  if !charge_comparison_operand(control, left) ||
    !charge_comparison_operand(control, right) {
    return Err(Limit)
  }
  match compare(left, right) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Scalar(issue))
  }
}

///|
fn value_rank(value : Value) -> Int {
  match value {
    Null => 0
    Boolean(_) => 1
    Number(_) => 2
    Text(_) => 3
    Captured(value) => 4 + admitted_rank(value)
  }
}

///|
fn admitted_rank(value : @admitted.Value) -> Int {
  match value {
    @admitted.Null => 0
    @admitted.Boolean(_) => 1
    @admitted.Number(_) => 2
    @admitted.Text(_) => 3
    @admitted.Date(_) => 4
    @admitted.Timestamp(_) => 5
    @admitted.Decimal(_) => 6
    @admitted.Array(_) => 7
    @admitted.Object(_) => 8
    @admitted.Vector(_) => 9
  }
}

///|
fn compare_admitted_value(
  left : @admitted.Value,
  right : @admitted.Value,
  control : ControlBudget,
) -> Result[Int, OrderingIssue] {
  if !spend_control(control, 1) {
    return Err(Limit)
  }
  match (left, right) {
    (@admitted.Null, @admitted.Null) => Ok(0)
    (@admitted.Boolean(a), @admitted.Boolean(b)) =>
      compare_complete_scalar(Boolean(a), Boolean(b), control)
    (@admitted.Number(a), @admitted.Number(b)) =>
      compare_complete_scalar(Number(a), Number(b), control)
    (@admitted.Text(a), @admitted.Text(b)) =>
      compare_complete_scalar(Text(a), Text(b), control)
    (@admitted.Date(a), @admitted.Date(b)) =>
      compare_complete_text(a, b, control)
    (@admitted.Timestamp(a), @admitted.Timestamp(b)) =>
      compare_complete_text(a, b, control)
    (@admitted.Decimal(a), @admitted.Decimal(b)) => {
      if !spend_control_text(control, a.coefficient) ||
        !spend_control_text(control, b.coefficient) {
        return Err(Limit)
      }
      Ok(compare_decimal(a, b))
    }
    (@admitted.Array(a), @admitted.Array(b)) =>
      compare_admitted_arrays(a, b, control)
    (@admitted.Object(a), @admitted.Object(b)) =>
      compare_admitted_objects(a, b, control)
    (@admitted.Vector(a), @admitted.Vector(b)) =>
      compare_admitted_vectors(a, b, control)
    _ => Ok(Int::compare(admitted_rank(left), admitted_rank(right)))
  }
}

///|
fn compare_complete_text(
  left : String,
  right : String,
  control : ControlBudget,
) -> Result[Int, OrderingIssue] {
  if !spend_control_text(control, left) || !spend_control_text(control, right) {
    return Err(Limit)
  }
  Ok(@canonical.compare_utf16(left, right))
}

///|
fn compare_admitted_arrays(
  left : @admitted.FrozenArray[@admitted.Value],
  right : @admitted.FrozenArray[@admitted.Value],
  control : ControlBudget,
) -> Result[Int, OrderingIssue] {
  let left_count = @admitted.element_count(left)
  let right_count = @admitted.element_count(right)
  for index in 0..<Int::min(left_count, right_count) {
    let comparison = match
      compare_admitted_value(
        @admitted.element_at(left, index).unwrap(),
        @admitted.element_at(right, index).unwrap(),
        control,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if comparison != 0 {
      return Ok(comparison)
    }
  }
  Ok(Int::compare(left_count, right_count))
}

///|
fn compare_admitted_objects(
  left : @admitted.FrozenArray[(String, @admitted.Value)],
  right : @admitted.FrozenArray[(String, @admitted.Value)],
  control : ControlBudget,
) -> Result[Int, OrderingIssue] {
  let left_count = @admitted.element_count(left)
  let right_count = @admitted.element_count(right)
  for index in 0..<Int::min(left_count, right_count) {
    let (left_name, left_value) = @admitted.element_at(left, index).unwrap()
    let (right_name, right_value) = @admitted.element_at(right, index).unwrap()
    if !spend_control_text(control, left_name) ||
      !spend_control_text(control, right_name) {
      return Err(Limit)
    }
    let name_order = @canonical.compare_utf16(left_name, right_name)
    if name_order != 0 {
      return Ok(name_order)
    }
    let value_order = match
      compare_admitted_value(left_value, right_value, control) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if value_order != 0 {
      return Ok(value_order)
    }
  }
  Ok(Int::compare(left_count, right_count))
}

///|
fn compare_admitted_vectors(
  left : @admitted.FrozenArray[Double],
  right : @admitted.FrozenArray[Double],
  control : ControlBudget,
) -> Result[Int, OrderingIssue] {
  let left_count = @admitted.element_count(left)
  let right_count = @admitted.element_count(right)
  for index in 0..<Int::min(left_count, right_count) {
    let comparison = match
      compare_complete_scalar(
        Number(@admitted.element_at(left, index).unwrap()),
        Number(@admitted.element_at(right, index).unwrap()),
        control,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if comparison != 0 {
      return Ok(comparison)
    }
  }
  Ok(Int::compare(left_count, right_count))
}

///|
fn[T : IndexedRows] compare_complete_row_indices(
  input : T,
  left : Int,
  right : Int,
  columns : Array[Int],
  control : ControlBudget,
) -> Result[Int, OrderingIssue] {
  for column in columns {
    let comparison = match
      compare_complete_value(
        IndexedRows::read_cell(input, left, column),
        IndexedRows::read_cell(input, right, column),
        control,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if comparison != 0 {
      return Ok(comparison)
    }
  }
  Ok(0)
}

///|
fn[L : IndexedRows, R : IndexedRows] compare_complete_rows(
  left : L,
  left_row : Int,
  left_columns : Array[Int],
  right : R,
  right_row : Int,
  right_columns : Array[Int],
  control : ControlBudget,
) -> Result[Int, OrderingIssue] {
  if left_columns.length() != right_columns.length() {
    return Err(InvalidInput)
  }
  for index in 0..<left_columns.length() {
    let comparison = match
      compare_complete_value(
        IndexedRows::read_cell(left, left_row, left_columns[index]),
        IndexedRows::read_cell(right, right_row, right_columns[index]),
        control,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if comparison != 0 {
      return Ok(comparison)
    }
  }
  Ok(0)
}

///|
fn[T : IndexedRows] stable_complete_order_indices(
  input : T,
  columns : Array[Int],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Array[Int], OrderingIssue] {
  if control.remaining < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit {
    return Err(InvalidInput)
  }
  let count = IndexedRows::row_count(input)
  for column in columns {
    if column < 0 || column >= IndexedRows::column_count(input) {
      return Err(InvalidInput)
    }
  }
  for row in 0..<count {
    if !spend_control(control, 1) {
      return Err(Limit)
    }
    if IndexedRows::row_width(input, row) != IndexedRows::column_count(input) {
      return Err(InvalidInput)
    }
  }
  if !reserve_slots(workspace, count) || !spend_control(control, count) {
    return Err(Limit)
  }
  let mut source = Array::makei(count, index => index)
  if count < 2 || columns.is_empty() {
    return Ok(source)
  }
  if !reserve_slots(workspace, count) || !spend_control(control, count) {
    return Err(Limit)
  }
  let mut target = Array::make(count, 0)
  let mut width = 1
  while width < count {
    let mut start = 0
    while start < count {
      let middle = start + Int::min(width, count - start)
      let end = middle + Int::min(width, count - middle)
      let mut left = start
      let mut right = middle
      for output = start; output < end; output = output + 1 {
        if !spend_control(control, 1) {
          return Err(Limit)
        }
        let choose_left = if left == middle {
          false
        } else if right == end {
          true
        } else {
          match
            compare_complete_row_indices(
              input,
              source[left],
              source[right],
              columns,
              control,
            ) {
            Ok(value) => value <= 0
            Err(issue) => return Err(issue)
          }
        }
        if choose_left {
          target[output] = source[left]
          left += 1
        } else {
          target[output] = source[right]
          right += 1
        }
      }
      start = end
    }
    let prior = source
    source = target
    target = prior
    if width > count / 2 {
      break
    }
    width *= 2
  }
  Ok(source)
}
