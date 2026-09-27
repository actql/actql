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
  ChargeText(String, Int)
  CompareText(String, String, Int)
  CompareDecimal(DecimalValue, DecimalValue, Int)
  CompareArray(FrozenArray[Value], FrozenArray[Value], Int, Int)
  CompareObject(
    FrozenArray[(String, Value)],
    FrozenArray[(String, Value)],
    Int,
    Int
  )
  CompareObjectNames(
    FrozenArray[(String, Value)],
    FrozenArray[(String, Value)],
    Int,
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
fn equality_text_scalar(text : String, index : Int) -> (Int, Int)? {
  if index < 0 || index >= text.length() {
    return None
  }
  let unit = text[index].to_int()
  if unit < 0x80 {
    Some((index + 1, 1))
  } else if unit < 0x800 {
    Some((index + 1, 2))
  } else if unit >= 0xd800 && unit <= 0xdbff {
    if index + 1 >= text.length() {
      return None
    }
    let trailing = text[index + 1].to_int()
    if trailing < 0xdc00 || trailing > 0xdfff {
      None
    } else {
      Some((index + 2, 4))
    }
  } else if unit >= 0xdc00 && unit <= 0xdfff {
    None
  } else {
    Some((index + 1, 3))
  }
}

///|
fn equality_queue_text_comparison(
  value : CompleteEquality,
  left : String,
  right : String,
) -> Unit {
  value.frames.push(CompareText(left, right, 0))
  if right.length() > 0 {
    value.frames.push(ChargeText(right, 0))
  }
  if left.length() > 0 {
    value.frames.push(ChargeText(left, 0))
  }
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
  value.frames.clear()
  EqualityComplete(equal~, work~)
}

///|
fn equality_failure(
  value : CompleteEquality,
  issue : CompleteEqualityIssue,
  work : Int,
) -> CompleteEqualityPoll {
  value.terminal = true
  value.frames.clear()
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
          | (Timestamp(a), Timestamp(b)) =>
            equality_queue_text_comparison(value, a, b)
          (Decimal(a), Decimal(b)) => {
            value.frames.push(CompareDecimal(a, b, 0))
            if b.coefficient.length() > 0 {
              value.frames.push(ChargeText(b.coefficient, 0))
            }
            if a.coefficient.length() > 0 {
              value.frames.push(ChargeText(a.coefficient, 0))
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
            equality_queue_text_comparison(value, left_id, right_id)
          }
          _ => return equality_result(value, false, work)
        }
      }
      ChargeText(text, index) => {
        guard equality_text_scalar(text, index) is Some((next, bytes)) &&
          bytes <= value.limits.max_text_bytes - value.text_bytes else {
          return equality_failure(value, CompleteEqualityLimit, work)
        }
        value.text_bytes += bytes
        if next < text.length() {
          value.frames.push(ChargeText(text, next))
        }
      }
      CompareText(left, right, index) =>
        if index >= left.length() || index >= right.length() {
          if left.length() != right.length() {
            return equality_result(value, false, work)
          }
        } else if left[index] != right[index] {
          return equality_result(value, false, work)
        } else if index + 1 < left.length() || index + 1 < right.length() {
          value.frames.push(CompareText(left, right, index + 1))
        }
      CompareDecimal(left, right, index) => {
        let a = left.coefficient
        let b = right.coefficient
        if a == "0" || b == "0" {
          if a != "0" || b != "0" {
            return equality_result(value, false, work)
          }
        } else {
          let negative_a = a[0] == '-'
          let negative_b = b[0] == '-'
          if negative_a != negative_b {
            return equality_result(value, false, work)
          }
          let offset_a = if negative_a { 1 } else { 0 }
          let offset_b = if negative_b { 1 } else { 0 }
          let digits_a = a.length() - offset_a
          let digits_b = b.length() - offset_b
          if digits_a - left.scale != digits_b - right.scale {
            return equality_result(value, false, work)
          }
          let length = Int::max(digits_a, digits_b)
          if index < length {
            let digit_a = if index < digits_a {
              a[offset_a + index]
            } else {
              '0'
            }
            let digit_b = if index < digits_b {
              b[offset_b + index]
            } else {
              '0'
            }
            if digit_a != digit_b {
              return equality_result(value, false, work)
            }
            if index + 1 < length {
              value.frames.push(CompareDecimal(left, right, index + 1))
            }
          }
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
          let (left_name, _) = element_at(left, index).unwrap()
          let (right_name, _) = element_at(right, index).unwrap()
          value.frames.push(CompareObjectNames(left, right, index, depth, 0))
          if right_name.length() > 0 {
            value.frames.push(ChargeText(right_name, 0))
          }
          if left_name.length() > 0 {
            value.frames.push(ChargeText(left_name, 0))
          }
        }
      }
      CompareObjectNames(left, right, index, depth, position) => {
        let (left_name, left_value) = element_at(left, index).unwrap()
        let (right_name, right_value) = element_at(right, index).unwrap()
        if position >= left_name.length() || position >= right_name.length() {
          if left_name.length() != right_name.length() {
            return equality_result(value, false, work)
          }
        } else if left_name[position] != right_name[position] {
          return equality_result(value, false, work)
        } else if position + 1 < left_name.length() ||
          position + 1 < right_name.length() {
          value.frames.push(
            CompareObjectNames(left, right, index, depth, position + 1),
          )
          continue
        }
        value.frames.push(CompareObject(left, right, index + 1, depth))
        value.frames.push(CompareValue(left_value, right_value, depth))
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
