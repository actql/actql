///|
// Private bounded arithmetic shared by the existing exact Decimal operations.
// Callers retain the admitted coefficient/scale bounds and preflight scratch.
fn decimal_coefficient_magnitude(
  value : @admitted.DecimalValue,
) -> @bigint.BigInt {
  let start = if value.coefficient[0] == '-' { 1 } else { 0 }
  let ten = @bigint.BigInt::from_int(10)
  let mut magnitude = @bigint.BigInt::from_int(0)
  for i = start; i < value.coefficient.length(); i = i + 1 {
    magnitude = magnitude * ten +
      @bigint.BigInt::from_int(value.coefficient[i].to_int() - 48)
  }
  magnitude
}

///|
// Quantization requests at most 38 powers, explicit division at most 76.
fn decimal_scale_power(exponent : Int) -> @bigint.BigInt {
  let ten = @bigint.BigInt::from_int(10)
  let mut factor = @bigint.BigInt::from_int(1)
  for _i = 0; _i < exponent; _i = _i + 1 {
    factor = factor * ten
  }
  factor
}

///|
fn exact_decimal_round_ratio(
  numerator : @bigint.BigInt,
  denominator : @bigint.BigInt,
  negative : Bool,
  mode : String,
) -> @bigint.BigInt? {
  let zero = @bigint.BigInt::from_int(0)
  let one = @bigint.BigInt::from_int(1)
  if numerator < zero || denominator <= zero {
    return None
  }
  let quotient = numerator / denominator
  let remainder = numerator % denominator
  let twice = remainder * @bigint.BigInt::from_int(2)
  let increment = match mode {
    "half_even" =>
      twice > denominator ||
      (twice == denominator && quotient % @bigint.BigInt::from_int(2) == one)
    "half_up" => twice >= denominator
    "toward_zero" => false
    "floor" => negative && remainder != zero
    "ceiling" => !negative && remainder != zero
    _ => return None
  }
  Some(if increment { quotient + one } else { quotient })
}
