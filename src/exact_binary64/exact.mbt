///|
pub(all) enum Issue {
  NonFinite
  NegativeWeight
  ZeroDenominator
  BitLimit
  Overflow
  Closed
} derive(Eq, Debug)

///|
/// One exact integer multiplied by a power of two. The coefficient is kept
/// odd, except for zero, so equivalent binary64 inputs have one form.
priv struct Dyadic {
  coefficient : @bigint.BigInt
  exponent : Int
}

///|
struct WeightSum {
  max_bits : Int
  mut value : Dyadic
  mut open : Bool
}

///|
struct Mean {
  max_bits : Int
  mut numerator : Dyadic
  mut denominator : Dyadic
  mut open : Bool
}

///|
fn zero() -> Dyadic {
  { coefficient: @bigint.BigInt::from_int(0), exponent: 0, }
}

///|
fn magnitude(value : @bigint.BigInt) -> @bigint.BigInt {
  if value.compare_int(0) < 0 {
    -value
  } else {
    value
  }
}

///|
fn normalized(coefficient : @bigint.BigInt, exponent : Int) -> Dyadic {
  if coefficient.is_zero() {
    return zero()
  }
  let shift = magnitude(coefficient).ctz()
  { coefficient: coefficient >> shift, exponent: exponent + shift, }
}

///|
fn admitted_bits(value : @bigint.BigInt, max_bits : Int) -> Bool {
  max_bits >= 1 &&
  (value.is_zero() || magnitude(value).bit_length() <= max_bits)
}

///|
fn from_finite(value : Double) -> Result[Dyadic, Issue] {
  if value.is_nan() || value.is_inf() {
    return Err(NonFinite)
  }
  let bits = value.reinterpret_as_uint64()
  let magnitude_bits = bits & 0x7fffffffffffffffUL
  if magnitude_bits == 0UL {
    return Ok(zero())
  }
  let encoded_exponent = ((bits >> 52) & 0x7ffUL).to_int()
  let fraction = bits & 0x000fffffffffffffUL
  let (significand, exponent) = if encoded_exponent == 0 {
    (@bigint.BigInt::from_uint64(fraction), -1074)
  } else {
    (
      @bigint.BigInt::from_uint64(fraction | 0x0010000000000000UL),
      encoded_exponent - 1023 - 52,
    )
  }
  let signed = if (bits & 0x8000000000000000UL) == 0UL {
    significand
  } else {
    -significand
  }
  Ok(normalized(signed, exponent))
}

///|
fn shifted_bits(value : Dyadic, exponent : Int) -> Int {
  if value.coefficient.is_zero() {
    0
  } else {
    magnitude(value.coefficient).bit_length() + value.exponent - exponent
  }
}

///|
fn add(left : Dyadic, right : Dyadic, max_bits : Int) -> Result[Dyadic, Issue] {
  if left.coefficient.is_zero() {
    return if admitted_bits(right.coefficient, max_bits) {
      Ok(right)
    } else {
      Err(BitLimit)
    }
  }
  if right.coefficient.is_zero() {
    return if admitted_bits(left.coefficient, max_bits) {
      Ok(left)
    } else {
      Err(BitLimit)
    }
  }
  let exponent = Int::min(left.exponent, right.exponent)
  if shifted_bits(left, exponent) > max_bits ||
    shifted_bits(right, exponent) > max_bits {
    return Err(BitLimit)
  }
  let coefficient = (left.coefficient << (left.exponent - exponent)) +
    (right.coefficient << (right.exponent - exponent))
  if !admitted_bits(coefficient, max_bits) {
    Err(BitLimit)
  } else {
    Ok(normalized(coefficient, exponent))
  }
}

///|
fn multiply(
  left : Dyadic,
  right : Dyadic,
  max_bits : Int,
) -> Result[Dyadic, Issue] {
  if left.coefficient.is_zero() || right.coefficient.is_zero() {
    return Ok(zero())
  }
  let left_bits = magnitude(left.coefficient).bit_length()
  let right_bits = magnitude(right.coefficient).bit_length()
  if left_bits > max_bits || right_bits > max_bits - left_bits + 1 {
    return Err(BitLimit)
  }
  let coefficient = left.coefficient * right.coefficient
  if !admitted_bits(coefficient, max_bits) {
    Err(BitLimit)
  } else {
    Ok(normalized(coefficient, left.exponent + right.exponent))
  }
}

///|
fn compare(left : Dyadic, right : Dyadic, max_bits : Int) -> Result[Int, Issue] {
  if left.coefficient.compare_int(0) < 0 &&
    right.coefficient.compare_int(0) >= 0 {
    return Ok(-1)
  }
  if left.coefficient.compare_int(0) >= 0 &&
    right.coefficient.compare_int(0) < 0 {
    return Ok(1)
  }
  let exponent = Int::min(left.exponent, right.exponent)
  if shifted_bits(left, exponent) > max_bits ||
    shifted_bits(right, exponent) > max_bits {
    return Err(BitLimit)
  }
  Ok(
    (left.coefficient << (left.exponent - exponent)).compare(
      right.coefficient << (right.exponent - exponent),
    ),
  )
}

///|
fn rounded_quotient(
  numerator : @bigint.BigInt,
  denominator : @bigint.BigInt,
) -> @bigint.BigInt {
  let quotient = numerator / denominator
  let remainder = numerator % denominator
  let doubled = remainder << 1
  let order = doubled.compare(denominator)
  if order > 0 ||
    (order == 0 && (quotient & @bigint.BigInt::from_int(1)).compare_int(0) != 0) {
    quotient + @bigint.BigInt::from_int(1)
  } else {
    quotient
  }
}

///|
fn scaled_quotient(
  numerator : @bigint.BigInt,
  denominator : @bigint.BigInt,
  shift : Int,
  max_bits : Int,
) -> Result[@bigint.BigInt, Issue] {
  if shift >= 0 {
    if numerator.bit_length() + shift > max_bits {
      return Err(BitLimit)
    }
    Ok(rounded_quotient(numerator << shift, denominator))
  } else {
    if denominator.bit_length() - shift > max_bits {
      return Err(BitLimit)
    }
    Ok(rounded_quotient(numerator, denominator << -shift))
  }
}

///|
fn ratio_exponent(
  numerator : @bigint.BigInt,
  denominator : @bigint.BigInt,
  binary_shift : Int,
  max_bits : Int,
) -> Result[Int, Issue] {
  let mut exponent = numerator.bit_length() -
    denominator.bit_length() +
    binary_shift
  let comparison = if exponent >= binary_shift {
    let shift = exponent - binary_shift
    if denominator.bit_length() + shift > max_bits {
      return Err(BitLimit)
    }
    numerator.compare(denominator << shift)
  } else {
    let shift = binary_shift - exponent
    if numerator.bit_length() + shift > max_bits {
      return Err(BitLimit)
    }
    (numerator << shift).compare(denominator)
  }
  if comparison < 0 {
    exponent -= 1
  }
  Ok(exponent)
}

///|
fn divide_to_binary64(
  numerator : Dyadic,
  denominator : Dyadic,
  max_bits : Int,
) -> Result[Double, Issue] {
  if denominator.coefficient.compare_int(0) <= 0 {
    return Err(ZeroDenominator)
  }
  if numerator.coefficient.is_zero() {
    return Ok(0.0)
  }
  let negative = numerator.coefficient.compare_int(0) < 0
  let absolute = magnitude(numerator.coefficient)
  let shift = numerator.exponent - denominator.exponent
  let mut exponent = match
    ratio_exponent(absolute, denominator.coefficient, shift, max_bits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if exponent > 1023 {
    return Err(Overflow)
  }
  let mut significand = if exponent >= -1022 {
    match
      scaled_quotient(
        absolute,
        denominator.coefficient,
        shift + 52 - exponent,
        max_bits,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  } else {
    exponent = -1023
    match
      scaled_quotient(absolute, denominator.coefficient, shift + 1074, max_bits) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  }
  let hidden = @bigint.BigInt::from_uint64(0x0010000000000000UL)
  let carry = hidden << 1
  if exponent >= -1022 && significand == carry {
    exponent += 1
    significand = hidden
    if exponent > 1023 {
      return Err(Overflow)
    }
  }
  if significand.is_zero() {
    return Ok(0.0)
  }
  let magnitude_bits = if exponent == -1023 {
    if significand >= hidden {
      0x0010000000000000UL
    } else {
      significand.to_uint64()
    }
  } else {
    ((exponent + 1023).to_uint64() << 52) | (significand - hidden).to_uint64()
  }
  let bits = if negative {
    magnitude_bits | 0x8000000000000000UL
  } else {
    magnitude_bits
  }
  Ok(bits.reinterpret_as_double())
}

///|
/// Start a bounded exact sum of nonnegative binary64 weights.
pub fn prepare_weight_sum(max_bits : Int) -> Result[WeightSum, Issue] {
  if max_bits < 1 {
    Err(BitLimit)
  } else {
    Ok({ max_bits, value: zero(), open: true, })
  }
}

///|
/// Add one semantic weight occurrence. Repeated occurrences are not folded
/// away and a failed addition does not change the prior exact sum.
pub fn add_weight(sum : WeightSum, weight : Double) -> Result[Unit, Issue] {
  if !sum.open {
    return Err(Closed)
  }
  if weight < 0.0 {
    return Err(NegativeWeight)
  }
  let exact = match from_finite(weight) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match add(sum.value, exact, sum.max_bits) {
    Ok(value) => {
      sum.value = value
      Ok(())
    }
    Err(issue) => Err(issue)
  }
}

///|
/// Compare two accumulated weight sums to one binary64 support threshold.
/// Neither sum is consumed or rounded.
pub fn accumulated_support_at_least(
  present : WeightSum,
  total : WeightSum,
  threshold : Double,
) -> Result[Bool, Issue] {
  if !present.open || !total.open {
    return Err(Closed)
  }
  if total.value.coefficient.compare_int(0) <= 0 {
    return Err(ZeroDenominator)
  }
  let max_bits = Int::min(present.max_bits, total.max_bits)
  let exact_threshold = match from_finite(threshold) {
    Ok(value) if value.coefficient.compare_int(0) >= 0 => value
    Ok(_) => return Err(NegativeWeight)
    Err(issue) => return Err(issue)
  }
  let required = match multiply(total.value, exact_threshold, max_bits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  compare(present.value, required, max_bits).map(order => order >= 0)
}

///|
pub fn cancel_weight_sum(sum : WeightSum) -> Bool {
  if !sum.open {
    false
  } else {
    sum.open = false
    sum.value = zero()
    true
  }
}

///|
/// Start an exact weighted-mean fold. One call to `add_weighted_value`
/// corresponds to one included semantic sample occurrence.
pub fn prepare_weighted_mean(max_bits : Int) -> Result[Mean, Issue] {
  if max_bits < 1 {
    Err(BitLimit)
  } else {
    Ok({ max_bits, numerator: zero(), denominator: zero(), open: true, })
  }
}

///|
pub fn add_weighted_value(
  mean : Mean,
  value : Double,
  weight : Double,
) -> Result[Unit, Issue] {
  if !mean.open {
    return Err(Closed)
  }
  if weight < 0.0 {
    return Err(NegativeWeight)
  }
  let exact_value = match from_finite(value) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let exact_weight = match from_finite(weight) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let product = match multiply(exact_value, exact_weight, mean.max_bits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let numerator = match add(mean.numerator, product, mean.max_bits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let denominator = match add(mean.denominator, exact_weight, mean.max_bits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  mean.numerator = numerator
  mean.denominator = denominator
  Ok(())
}

///|
pub fn finish_weighted_mean(mean : Mean) -> Result[Double, Issue] {
  if !mean.open {
    return Err(Closed)
  }
  mean.open = false
  let result = divide_to_binary64(
    mean.numerator,
    mean.denominator,
    mean.max_bits,
  )
  mean.numerator = zero()
  mean.denominator = zero()
  result
}

///|
pub fn cancel_weighted_mean(mean : Mean) -> Bool {
  if !mean.open {
    false
  } else {
    mean.open = false
    mean.numerator = zero()
    mean.denominator = zero()
    true
  }
}

///|
/// Compare `present / total` with an exact binary64 threshold. All inputs are
/// nonnegative and the comparison performs no floating-point division.
pub fn support_at_least(
  present : Array[Double],
  total : Array[Double],
  threshold : Double,
  max_bits : Int,
) -> Result[Bool, Issue] {
  let present_sum = match prepare_weight_sum(max_bits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let total_sum = match prepare_weight_sum(max_bits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for weight in present {
    match add_weight(present_sum, weight) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  for weight in total {
    match add_weight(total_sum, weight) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  accumulated_support_at_least(present_sum, total_sum, threshold)
}

///|
/// Compute a weighted mean using exact products and one final
/// nearest-ties-to-even binary64 rounding.
pub fn weighted_mean(
  values : Array[(Double, Double)],
  max_bits : Int,
) -> Result[Double, Issue] {
  let mean = match prepare_weighted_mean(max_bits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for (value, weight) in values {
    match add_weighted_value(mean, value, weight) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  finish_weighted_mean(mean)
}
