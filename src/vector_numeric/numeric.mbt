///|
pub(all) enum Issue {
  NonFinite
  ZeroVector
} derive(Eq, Debug)

///|
pub(all) enum Metric {
  Cosine
  Dot
  L2
} derive(Eq, Debug)

///|
struct ScoreFold {
  metric : Metric
  mut dot : Double
  mut left_squared : Double
  mut right_squared : Double
  mut distance_squared : Double
}

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

///|
pub fn prepare_score(metric : Metric) -> ScoreFold {
  {
    metric,
    dot: 0.0,
    left_squared: 0.0,
    right_squared: 0.0,
    distance_squared: 0.0,
  }
}

///|
fn product(left : Double, right : Double) -> Result[Double, Issue] {
  rounded(left * right)
}

///|
fn add(sum : Double, value : Double) -> Result[Double, Issue] {
  rounded(sum + value)
}

///|
/// Consume one dimension in increasing index order.
pub fn score_step(
  fold : ScoreFold,
  left : Double,
  right : Double,
) -> Result[Unit, Issue] {
  let a = match quantize(left) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let b = match quantize(right) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match fold.metric {
    Dot => {
      let pair = match product(a, b) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      fold.dot = match add(fold.dot, pair) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    }
    Cosine => {
      let pair = match product(a, b) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      fold.dot = match add(fold.dot, pair) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let left = match product(a, a) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      fold.left_squared = match add(fold.left_squared, left) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let right = match product(b, b) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      fold.right_squared = match add(fold.right_squared, right) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    }
    L2 => {
      let difference = match rounded(a - b) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let square = match product(difference, difference) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      fold.distance_squared = match add(fold.distance_squared, square) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    }
  }
  Ok(())
}

///|
fn canonical_zero(value : Double) -> Double {
  if value == 0.0 {
    0.0
  } else {
    value
  }
}

///|
/// Finish a score without approximation, clamping, or score quantization.
pub fn finish_score(fold : ScoreFold) -> Result[Double, Issue] {
  match fold.metric {
    Dot => Ok(canonical_zero(fold.dot))
    Cosine => {
      if fold.left_squared == 0.0 || fold.right_squared == 0.0 {
        return Ok(0.0)
      }
      let left = match rounded(fold.left_squared.sqrt()) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let right = match rounded(fold.right_squared.sqrt()) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let denominator = match product(left, right) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      rounded(fold.dot / denominator).map(canonical_zero)
    }
    L2 =>
      rounded(fold.distance_squared.sqrt()).map(value => canonical_zero(-value))
  }
}
