///|
pub struct Coordinate {
  coefficient : @bigint.BigInt
  exponent : Int
}

///|
pub fn from_timestamp_milliseconds(value : Int64) -> Coordinate {
  { coefficient: @bigint.BigInt::from_int64(value), exponent: 0, }
}

///|
pub fn from_finite_number(number : Double) -> Coordinate? {
  if number.is_nan() || number.is_inf() {
    return None
  }
  let bits = number.reinterpret_as_uint64()
  let absolute = bits & 0x7fffffffffffffffUL
  if absolute == 0UL {
    return Some({ coefficient: @bigint.BigInt::from_int(0), exponent: 0, })
  }
  let encoded = ((bits >> 52) & 0x7ffUL).to_int()
  let fraction = bits & 0x000fffffffffffffUL
  let coefficient = if encoded == 0 {
    @bigint.BigInt::from_uint64(fraction)
  } else {
    @bigint.BigInt::from_uint64(fraction | 0x0010000000000000UL)
  }
  Some({
    coefficient: if (bits & 0x8000000000000000UL) == 0UL {
      coefficient
    } else {
      -coefficient
    },
    exponent: if encoded == 0 {
      -1074
    } else {
      encoded - 1023 - 52
    },
  })
}

///|
fn floor_div(
  dividend : @bigint.BigInt,
  divisor : @bigint.BigInt,
) -> @bigint.BigInt {
  let quotient = dividend / divisor
  if (dividend % divisor).compare_int(0) < 0 {
    quotient - @bigint.BigInt::from_int(1)
  } else {
    quotient
  }
}

///|
pub fn latest_start(
  time : Coordinate,
  step : Int64,
  offset : Int64,
) -> @bigint.BigInt {
  let denominator = if time.exponent < 0 {
    @bigint.BigInt::from_int(1) << -time.exponent
  } else {
    @bigint.BigInt::from_int(1)
  }
  let numerator = if time.exponent > 0 {
    time.coefficient << time.exponent
  } else {
    time.coefficient
  }
  let origin = @bigint.BigInt::from_int64(offset)
  let interval = @bigint.BigInt::from_int64(step)
  let index = floor_div(
    numerator - origin * denominator,
    interval * denominator,
  )
  origin + index * interval
}

///|
pub fn compare(time : Coordinate, boundary : @bigint.BigInt) -> Int {
  if time.exponent >= 0 {
    (time.coefficient << time.exponent).compare(boundary)
  } else {
    time.coefficient.compare(boundary << -time.exponent)
  }
}

///|
pub fn exact_binary64_boundary(value : @bigint.BigInt) -> Double? {
  if value.is_zero() {
    return Some(0.0)
  }
  let negative = value.compare_int(0) < 0
  let magnitude = if negative { -value } else { value }
  let width = magnitude.bit_length()
  if width > 1024 || width - magnitude.ctz() > 53 {
    return None
  }
  let significand = if width <= 53 {
    magnitude.to_uint64() << (53 - width)
  } else {
    (magnitude >> (width - 53)).to_uint64()
  }
  let sign = if negative { 0x8000000000000000UL } else { 0UL }
  let bits = sign |
    ((width - 1 + 1023).to_uint64() << 52) |
    (significand & 0x000fffffffffffffUL)
  Some(bits.reinterpret_as_double())
}
