///|
/// A nonnegative safe integer. This is numerical validation, not bound evidence.
struct Value(Int64) derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidValue
  Overflow
} derive(Eq, Debug)

///|
pub fn read(value : Int64) -> Result[Value, Issue] {
  if value < 0L || value > 9007199254740991L {
    Err(InvalidValue)
  } else {
    Ok(Value(value))
  }
}

///|
pub fn value(bound : Value) -> Int64 {
  bound.0
}

///|
/// Reject overflow before addition; never round or saturate.
pub fn add(left : Value, right : Value) -> Result[Value, Issue] {
  if left.0 > 9007199254740991L - right.0 {
    Err(Overflow)
  } else {
    Ok(Value(left.0 + right.0))
  }
}

///|
/// Integer division makes the boundary independent of floating-point rounding.
pub fn multiply(left : Value, right : Value) -> Result[Value, Issue] {
  if right.0 != 0L && left.0 > 9007199254740991L / right.0 {
    Err(Overflow)
  } else {
    Ok(Value(left.0 * right.0))
  }
}

///|
/// Numeric minimum only: callers must retain both witnesses, even on equality.
pub fn minimum(left : Value, right : Value) -> Value {
  if left.0 < right.0 {
    left
  } else {
    right
  }
}

///|
/// An absent input bound can still be clamped by a validated maximum.
/// The returned number does not establish that the clamp was enforced.
pub fn clamp(input : Value?, maximum : Value) -> Value {
  match input {
    Some(input) => minimum(input, maximum)
    None => maximum
  }
}
