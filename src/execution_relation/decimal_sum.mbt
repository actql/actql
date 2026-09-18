///|
/// Compare unsigned canonical coefficient slices without machine-integer or
/// binary64 conversion.
fn coefficient_magnitude_compare(
  left : String,
  left_start : Int,
  right : String,
  right_start : Int,
) -> Int {
  let left_count = left.length() - left_start
  let right_count = right.length() - right_start
  if left_count != right_count {
    return if left_count < right_count { -1 } else { 1 }
  }
  for i = 0; i < left_count; i = i + 1 {
    let a = left[left_start + i]
    let b = right[right_start + i]
    if a != b {
      return if a < b { -1 } else { 1 }
    }
  }
  0
}

///|
/// Exact signed coefficient addition for Decimal aggregates. Intermediate
/// coefficients intentionally may exceed precision 38: the aggregate law
/// checks the final public-domain result after all contributors, so later
/// cancellation remains exact.
fn add_decimal_coefficients(
  left : String,
  right : String,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[String, RowIssue] {
  if !spend_control_text(control, left) || !spend_control_text(control, right) {
    return Err(RowLimit)
  }
  let left_negative = left[0] == '-'
  let right_negative = right[0] == '-'
  let left_start = if left_negative { 1 } else { 0 }
  let right_start = if right_negative { 1 } else { 0 }
  let left_count = left.length() - left_start
  let right_count = right.length() - right_start
  let capacity = Int::max(left_count, right_count) + 1
  if !spend_control(control, capacity) || !reserve_slots(workspace, capacity) {
    return Err(RowLimit)
  }
  let reverse : Array[Int] = []
  let mut negative = false
  if left_negative == right_negative {
    negative = left_negative
    let mut carry = 0
    for offset = 0; offset < capacity - 1; offset = offset + 1 {
      let li = left.length() - 1 - offset
      let ri = right.length() - 1 - offset
      let a = if li >= left_start { left[li].to_int() - 48 } else { 0 }
      let b = if ri >= right_start { right[ri].to_int() - 48 } else { 0 }
      let value = a + b + carry
      reverse.push(value % 10)
      carry = value / 10
    }
    if carry != 0 {
      reverse.push(carry)
    }
  } else {
    let order = coefficient_magnitude_compare(
      left, left_start, right, right_start,
    )
    if order == 0 {
      release_slots(workspace, capacity)
      return Ok("0")
    }
    let larger = if order > 0 { left } else { right }
    let smaller = if order > 0 { right } else { left }
    let larger_start = if larger[0] == '-' { 1 } else { 0 }
    let smaller_start = if smaller[0] == '-' { 1 } else { 0 }
    negative = if order > 0 { left_negative } else { right_negative }
    let mut borrow = 0
    for offset = 0; offset < larger.length() - larger_start; offset = offset + 1 {
      let li = larger.length() - 1 - offset
      let ri = smaller.length() - 1 - offset
      let a = larger[li].to_int() - 48 - borrow
      let b = if ri >= smaller_start { smaller[ri].to_int() - 48 } else { 0 }
      if a < b {
        reverse.push(a + 10 - b)
        borrow = 1
      } else {
        reverse.push(a - b)
        borrow = 0
      }
    }
    while reverse.length() > 1 && reverse.last() == Some(0) {
      ignore(reverse.pop())
    }
  }
  let out = StringBuilder()
  if negative {
    out.write_char('-')
  }
  for i = reverse.length() - 1; i >= 0; i = i - 1 {
    out.write_char((reverse[i] + 48).unsafe_to_char())
  }
  let result = out.to_string()
  release_slots(workspace, capacity)
  Ok(result)
}
