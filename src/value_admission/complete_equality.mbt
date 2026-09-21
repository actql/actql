///|
pub(all) enum CompleteEqualityIssue {
  InvalidCompleteEqualityLimits
  CompleteEqualityLimit
  CompleteEqualityReferenceUnavailable
  CompleteEqualityReferenceDomain
  CompleteEqualityTerminal
} derive(Eq, Debug)

///|
priv enum EqualityFrame {
  CompareValue(Value, Value, Int)
  CompareArray(FrozenArray[Value], FrozenArray[Value], Int, Int)
  CompareObject(
    FrozenArray[(String, Value)],
    FrozenArray[(String, Value)],
    Int,
    Int
  )
  CompareVector(FrozenArray[Double], FrozenArray[Double], Int)
}

///|
struct CompleteEquality {
  limits : Limits
  frames : Array[EqualityFrame]
  mut nodes : Int
  mut text_bytes : Int
  mut terminal : Bool
}

///|
pub enum CompleteEqualityPoll {
  EqualityContinue(work~ : Int)
  EqualityComplete(equal~ : Bool, work~ : Int)
  EqualityFailed(CompleteEqualityIssue, work~ : Int)
}

///|
fn equality_text_charge(value : CompleteEquality, text : String) -> Bool {
  guard value.text_bytes <= value.limits.max_text_bytes &&
    @scalar.admit_utf8_length(
      text,
      value.limits.max_text_bytes - value.text_bytes,
    )
    is Ok(bytes) else {
    return false
  }
  value.text_bytes += bytes
  true
}

///|
fn decimal_values_equal(left : DecimalValue, right : DecimalValue) -> Bool {
  let a = left.coefficient
  let b = right.coefficient
  let negative_a = a[0] == '-'
  let negative_b = b[0] == '-'
  if a == "0" || b == "0" {
    return a == "0" && b == "0"
  }
  if negative_a != negative_b {
    return false
  }
  let offset_a = if negative_a { 1 } else { 0 }
  let offset_b = if negative_b { 1 } else { 0 }
  let digits_a = a.length() - offset_a
  let digits_b = b.length() - offset_b
  if digits_a - left.scale != digits_b - right.scale {
    return false
  }
  for index in 0..<Int::max(digits_a, digits_b) {
    let digit_a = if index < digits_a { a[offset_a + index] } else { '0' }
    let digit_b = if index < digits_b { b[offset_b + index] } else { '0' }
    if digit_a != digit_b {
      return false
    }
  }
  true
}

///|
pub fn start_complete_equality(
  left : CheckedValue,
  right : CheckedValue,
  limits : Limits,
) -> Result[CompleteEquality, CompleteEqualityIssue] {
  if limits.max_nodes < 0 || limits.max_depth < 0 || limits.max_text_bytes < 0 {
    return Err(InvalidCompleteEqualityLimits)
  }
  Ok({
    limits,
    frames: [CompareValue(left.value, right.value, 0)],
    nodes: 0,
    text_bytes: 0,
    terminal: false,
  })
}

///|
fn equality_result(
  value : CompleteEquality,
  equal : Bool,
  work : Int,
) -> CompleteEqualityPoll {
  value.terminal = true
  EqualityComplete(equal~, work~)
}

///|
fn equality_failure(
  value : CompleteEquality,
  issue : CompleteEqualityIssue,
  work : Int,
) -> CompleteEqualityPoll {
  value.terminal = true
  EqualityFailed(issue, work~)
}

///|
pub fn advance_complete_equality(
  value : CompleteEquality,
  quantum : Int,
) -> CompleteEqualityPoll {
  if value.terminal {
    return EqualityFailed(CompleteEqualityTerminal, work=0)
  }
  if quantum <= 0 {
    return EqualityFailed(InvalidCompleteEqualityLimits, work=0)
  }
  let mut work = 0
  while work < quantum {
    guard value.frames.pop() is Some(frame) else {
      return equality_result(value, true, work)
    }
    work += 1
    match frame {
      CompareValue(left, right, depth) => {
        if value.nodes >= value.limits.max_nodes {
          return equality_failure(value, CompleteEqualityLimit, work)
        }
        value.nodes += 1
        let container = left is (Array(_) | Object(_) | Vector(_))
        if container && depth >= value.limits.max_depth {
          return equality_failure(value, CompleteEqualityLimit, work)
        }
        let child_depth = depth + (if container { 1 } else { 0 })
        match (left, right) {
          (Null, Null) => ()
          (Boolean(a), Boolean(b)) =>
            if a != b {
              return equality_result(value, false, work)
            }
          (Number(a), Number(b)) =>
            if a != b {
              return equality_result(value, false, work)
            }
          (Text(a), Text(b))
          | (Date(a), Date(b))
          | (Timestamp(a), Timestamp(b)) => {
            if !equality_text_charge(value, a) ||
              !equality_text_charge(value, b) {
              return equality_failure(value, CompleteEqualityLimit, work)
            }
            if a != b {
              return equality_result(value, false, work)
            }
          }
          (Decimal(a), Decimal(b)) => {
            if !equality_text_charge(value, a.coefficient) ||
              !equality_text_charge(value, b.coefficient) {
              return equality_failure(value, CompleteEqualityLimit, work)
            }
            if !decimal_values_equal(a, b) {
              return equality_result(value, false, work)
            }
          }
          (Array(a), Array(b)) =>
            value.frames.push(CompareArray(a, b, 0, child_depth))
          (Object(a), Object(b)) =>
            value.frames.push(CompareObject(a, b, 0, child_depth))
          (Vector(a), Vector(b)) => value.frames.push(CompareVector(a, b, 0))
          (Reference(a), Reference(b)) => {
            if !reference_available(a) || !reference_available(b) {
              return equality_failure(
                value,
                CompleteEqualityReferenceUnavailable,
                work,
              )
            }
            if !reference_same_domain(a, b) {
              return equality_failure(
                value,
                CompleteEqualityReferenceDomain,
                work,
              )
            }
            let left_id = reference_identity_cid(a)
            let right_id = reference_identity_cid(b)
            if !equality_text_charge(value, left_id) ||
              !equality_text_charge(value, right_id) {
              return equality_failure(value, CompleteEqualityLimit, work)
            }
            if left_id != right_id {
              return equality_result(value, false, work)
            }
          }
          _ => return equality_result(value, false, work)
        }
      }
      CompareArray(left, right, index, depth) => {
        let left_count = element_count(left)
        let right_count = element_count(right)
        if left_count != right_count {
          return equality_result(value, false, work)
        }
        if index < left_count {
          value.frames.push(CompareArray(left, right, index + 1, depth))
          value.frames.push(
            CompareValue(
              element_at(left, index).unwrap(),
              element_at(right, index).unwrap(),
              depth,
            ),
          )
        }
      }
      CompareObject(left, right, index, depth) => {
        let left_count = element_count(left)
        let right_count = element_count(right)
        if left_count != right_count {
          return equality_result(value, false, work)
        }
        if index < left_count {
          let (left_name, left_value) = element_at(left, index).unwrap()
          let (right_name, right_value) = element_at(right, index).unwrap()
          if !equality_text_charge(value, left_name) ||
            !equality_text_charge(value, right_name) {
            return equality_failure(value, CompleteEqualityLimit, work)
          }
          if left_name != right_name {
            return equality_result(value, false, work)
          }
          value.frames.push(CompareObject(left, right, index + 1, depth))
          value.frames.push(CompareValue(left_value, right_value, depth))
        }
      }
      CompareVector(left, right, index) => {
        let left_count = element_count(left)
        let right_count = element_count(right)
        if left_count != right_count {
          return equality_result(value, false, work)
        }
        if index < left_count {
          if value.nodes >= value.limits.max_nodes {
            return equality_failure(value, CompleteEqualityLimit, work)
          }
          value.nodes += 1
          if element_at(left, index) != element_at(right, index) {
            return equality_result(value, false, work)
          }
          value.frames.push(CompareVector(left, right, index + 1))
        }
      }
    }
  }
  EqualityContinue(work~)
}
