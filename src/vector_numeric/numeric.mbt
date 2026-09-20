///|
pub(all) enum Issue {
  NonFinite
  ZeroVector
  InvalidMemberCount
  InvalidRankingOperand
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
pub(all) enum PoolMethod {
  Mean
  Sum
  Max
} derive(Eq, Debug)

///|
struct PoolFold {
  reduction : PoolMethod
  mut value : Double
  mut count : Int
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
/// Compute one weighted-ranking contribution with an explicit binary64
/// rounding point. Admission of the score contract remains the caller's
/// responsibility.
pub fn ranking_weighted_contribution(
  score : Double,
  weight : Double,
) -> Result[Double, Issue] {
  if score.is_nan() ||
    score.is_inf() ||
    weight.is_nan() ||
    weight.is_inf() ||
    weight < 0.0 {
    return Err(InvalidRankingOperand)
  }
  rounded(score * weight)
}

///|
/// Compute one reciprocal-rank contribution. Admit both positions as positive
/// safe-integer binary64 values before the rounded addition and division.
pub fn ranking_rrf_contribution(
  weight : Double,
  rank_constant : Double,
  rank : Double,
) -> Result[Double, Issue] {
  if weight.is_nan() ||
    weight.is_inf() ||
    weight < 0.0 ||
    rank_constant.is_nan() ||
    rank_constant.is_inf() ||
    rank_constant < 1.0 ||
    rank_constant > 9007199254740991.0 ||
    rank_constant.trunc() != rank_constant ||
    rank.is_nan() ||
    rank.is_inf() ||
    rank < 1.0 ||
    rank > 9007199254740991.0 ||
    rank.trunc() != rank {
    return Err(InvalidRankingOperand)
  }
  let denominator = match rounded(rank_constant + rank) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  rounded(weight / denominator)
}

///|
/// Add one contribution to the occurrence-ordered binary64 ranking fold.
pub fn ranking_fuse_step(
  sum : Double,
  contribution : Double,
) -> Result[Double, Issue] {
  if sum.is_nan() ||
    sum.is_inf() ||
    contribution.is_nan() ||
    contribution.is_inf() {
    return Err(InvalidRankingOperand)
  }
  add(sum, contribution)
}

///|
/// Start one dimension of a member-identity-ordered pooling fold.
pub fn prepare_pool(reduction : PoolMethod) -> PoolFold {
  { reduction, value: 0.0, count: 0, }
}

///|
/// Consume one component after binary32 input quantization.
pub fn pool_step(fold : PoolFold, component : Double) -> Result[Unit, Issue] {
  let admitted = match quantize(component) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if fold.count == 2147483647 {
    return Err(InvalidMemberCount)
  }
  if fold.count == 0 {
    fold.value = admitted
  } else {
    fold.value = match fold.reduction {
      Mean | Sum =>
        match add(fold.value, admitted) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
      Max => if admitted > fold.value { admitted } else { fold.value }
    }
  }
  fold.count += 1
  Ok(())
}

///|
/// Complete one pooled component and quantize the output to binary32.
pub fn finish_pool(fold : PoolFold) -> Result[Double, Issue] {
  if fold.count <= 0 {
    return Err(InvalidMemberCount)
  }
  let value = match fold.reduction {
    Mean =>
      match rounded(fold.value / fold.count.to_double()) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    Sum | Max => fold.value
  }
  quantize(value)
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
