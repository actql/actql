///|
pub(all) enum Issue {
  NonFinite
  ZeroVector
} derive(Eq, Debug)

///|
/// Materialize one binary64 operation result before the next operation.
fn rounded(value : Double) -> Result[Double, Issue] {
  let result = value.reinterpret_as_uint64().reinterpret_as_double()
  if result.is_nan() || result.is_inf() {
    Err(NonFinite)
  } else {
    Ok(result)
  }
}

///|
/// Round a finite component to binary32 nearest-ties-even and widen exactly.
pub fn quantize(value : Double) -> Result[Double, Issue] {
  if value.is_nan() || value.is_inf() {
    return Err(NonFinite)
  }
  let result = Float::from_double(value).to_double()
  if result.is_nan() || result.is_inf() {
    Err(NonFinite)
  } else if result == 0.0 {
    Ok(0.0)
  } else {
    Ok(result)
  }
}

///|
/// Add one admitted component square to a dimension-ordered norm fold.
pub fn squared_norm_step(
  sum : Double,
  component : Double,
) -> Result[Double, Issue] {
  let admitted = match quantize(component) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let product = match rounded(admitted * admitted) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  rounded(sum + product)
}

///|
/// Complete the prescribed binary64 square root and reject a zero norm.
pub fn normalization_divisor(sum : Double) -> Result[Double, Issue] {
  let result = match rounded(sum.sqrt()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if result == 0.0 {
    Err(ZeroVector)
  } else {
    Ok(result)
  }
}

///|
/// Normalize one source component using the already completed divisor.
pub fn normalize_component(
  component : Double,
  divisor : Double,
) -> Result[Double, Issue] {
  let admitted = match quantize(component) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let divided = match rounded(admitted / divisor) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  quantize(divided)
}
