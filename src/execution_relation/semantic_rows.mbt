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
/// Charge one admitted UTF-16 scalar by its exact UTF-8 byte width. A long
/// operand can therefore be charged without hiding its scan in one resume.
fn bounded_text_charge_step(
  control : ControlBudget,
  value : String,
  index : Int,
) -> Result[Int, OrderingIssue] {
  if index >= value.length() {
    return Ok(index)
  }
  let unit = value[index].to_int()
  let (width, next) = if unit < 0x80 {
    (1, index + 1)
  } else if unit < 0x800 {
    (2, index + 1)
  } else if unit >= 0xd800 && unit <= 0xdbff {
    if index + 1 >= value.length() {
      return Err(Limit)
    }
    let trailing = value[index + 1].to_int()
    if trailing < 0xdc00 || trailing > 0xdfff {
      return Err(Limit)
    }
    (4, index + 2)
  } else if unit >= 0xdc00 && unit <= 0xdfff {
    return Err(Limit)
  } else {
    (3, index + 1)
  }
  if !spend_control(control, width) {
    Err(Limit)
  } else {
    Ok(next)
  }
}

///|
/// Keep a multi-byte scalar inside the same logical charge while exposing
/// one charged byte per bounded advance.
priv struct BoundedTextCharge {
  mut offset : Int
  mut next : Int
  mut remaining : Int
}

///|
fn reset_bounded_text_charge(cursor : BoundedTextCharge) -> Unit {
  cursor.offset = 0
  cursor.next = 0
  cursor.remaining = 0
}

///|
fn advance_bounded_text_charge(
  cursor : BoundedTextCharge,
  control : ControlBudget,
  value : String,
) -> Result[Bool, OrderingIssue] {
  if cursor.remaining == 0 {
    if cursor.offset == value.length() {
      return Ok(true)
    }
    if cursor.offset < 0 || cursor.offset > value.length() {
      return Err(InvalidInput)
    }
    let unit = value[cursor.offset].to_int()
    let (width, next) = if unit < 0x80 {
      (1, cursor.offset + 1)
    } else if unit < 0x800 {
      (2, cursor.offset + 1)
    } else if unit >= 0xd800 && unit <= 0xdbff {
      if cursor.offset + 1 >= value.length() {
        return Err(Limit)
      }
      let trailing = value[cursor.offset + 1].to_int()
      if trailing < 0xdc00 || trailing > 0xdfff {
        return Err(Limit)
      }
      (4, cursor.offset + 2)
    } else if unit >= 0xdc00 && unit <= 0xdfff {
      return Err(Limit)
    } else {
      (3, cursor.offset + 1)
    }
    if control.remaining < width {
      return Err(Limit)
    }
    cursor.next = next
    cursor.remaining = width
  }
  if !spend_control(control, 1) {
    return Err(Limit)
  }
  cursor.remaining -= 1
  if cursor.remaining == 0 {
    cursor.offset = cursor.next
  }
  Ok(cursor.offset == value.length() && cursor.remaining == 0)
}

///|
priv struct BoundedCompleteValueComparison {
  mut phase : Int
  mut offset : Int
  charge : BoundedTextCharge
}

///|
fn bounded_complete_value_comparison() -> BoundedCompleteValueComparison {
  { phase: -1, offset: 0, charge: { offset: 0, next: 0, remaining: 0, }, }
}

///|
/// Text uses the same complete-value charges and UTF-16 order as the atomic
/// comparator, paying at most one UTF-8 byte unit per advance. Other admitted
/// kinds retain their existing comparison path.
fn bounded_complete_value_comparison_step(
  cursor : BoundedCompleteValueComparison,
  left : Value,
  right : Value,
  control : ControlBudget,
) -> Result[Int?, OrderingIssue] {
  guard left is Text(a) && right is Text(b) else {
    if cursor.phase != -1 {
      return Err(InvalidInput)
    }
    return compare_complete_value(left, right, control).map(value => Some(value))
  }
  if cursor.phase == -1 {
    cursor.phase = 0
    cursor.offset = 0
  }
  match cursor.phase {
    0 => {
      if !spend_control(control, 1) {
        return Err(Limit)
      }
      cursor.phase = 1
      Ok(None)
    }
    1 => {
      match advance_bounded_text_charge(cursor.charge, control, a) {
        Ok(false) => return Ok(None)
        Ok(true) => ()
        Err(issue) => return Err(issue)
      }
      reset_bounded_text_charge(cursor.charge)
      cursor.phase = 2
      cursor.offset = 0
      Ok(None)
    }
    2 => {
      match advance_bounded_text_charge(cursor.charge, control, b) {
        Ok(false) => return Ok(None)
        Ok(true) => ()
        Err(issue) => return Err(issue)
      }
      reset_bounded_text_charge(cursor.charge)
      cursor.phase = 3
      cursor.offset = 0
      Ok(None)
    }
    3 => {
      let compared = if cursor.offset < a.length() && cursor.offset < b.length() {
        let left_unit = a[cursor.offset]
        let right_unit = b[cursor.offset]
        if left_unit == right_unit {
          cursor.offset += 1
          return Ok(None)
        }
        if left_unit < right_unit {
          -1
        } else {
          1
        }
      } else if a.length() < b.length() {
        -1
      } else if a.length() > b.length() {
        1
      } else {
        0
      }
      cursor.phase = -1
      cursor.offset = 0
      Ok(Some(compared))
    }
    _ => Err(InvalidInput)
  }
}

///|
fn compare_complete_scalar(
  left : Value,
  right : Value,
  control : ControlBudget,
) -> Result[Int, OrderingIssue] {
  match charge_comparison_pair(control, left, right) {
    Ok(_) => ()
    Err(ComparisonChargeLimit) => return Err(Limit)
    Err(ComparisonChargeInvalidOperand) => return Err(Scalar(InvalidOperand))
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
    @admitted.Reference(_) => 10
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
    (@admitted.Reference(a), @admitted.Reference(b)) => {
      if !@admitted.reference_available(a) || !@admitted.reference_available(b) {
        return Err(Scalar(InvalidOperand))
      }
      if !@admitted.reference_same_domain(a, b) {
        return Err(Scalar(ComparisonDomainNotImplemented))
      }
      compare_complete_text(
        @admitted.reference_identity_cid(a),
        @admitted.reference_identity_cid(b),
        control,
      )
    }
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
  let compared = Int::min(left_count, right_count)
  // Numeric scalar comparison has constant operand cost, so the vector
  // primitive owns the dimension-dependent charge before it starts walking
  // either vector.
  if !spend_control(control, compared) {
    return Err(Limit)
  }
  for index in 0..<compared {
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
