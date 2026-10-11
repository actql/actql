// Copyright 2019 Google LLC
// Licensed under the Apache License, Version 2.0. See
// https://www.apache.org/licenses/LICENSE-2.0
// Adapted from google/googlesql at 81c15b796138185c046aefe852321011fdf96615:
// googlesql/common/round_decimal.cc and googlesql/common/double_double.h.
// This bounded MoonBit adaptation uses the existing expression continuation,
// canonical positive zero, and exact integer-derived power pairs. It preserves
// the portable Dekker binary64 operation sequence; no fused operations or
// reassociation are permitted. See docs/design/frontend-standard-profiles.md.

///|
// Fixed structural scratch entries, not a heap-byte measurement. Only the
// bounded exponentiation/power-pair conversion uses BigInt; no input can grow
// it beyond 2200 bits. The remaining phases have fixed binary64 scalar work.
const DECIMAL_ROUNDING_SLOTS : Int = 32

///|
priv struct DecimalPair {
  hi : Double
  lo : Double
}

///|
priv struct DecimalRounding {
  round : Bool
  negative : Bool
  digits : Int
  magnitude : Double
  mut remaining : Int
  mut phase : Int
  mut power : @bigint.BigInt
  mut factor : @bigint.BigInt
  mut forward : DecimalPair
  mut reverse : DecimalPair
  mut first : DecimalPair
  mut second : DecimalPair
  mut rounded : DecimalPair
  mut intermediate : Double
  mut result : Value?
}

///|
fn start_decimal_rounding(
  op : @lower.BinaryOperator,
  left : Value,
  right : Value,
) -> Result[DecimalRounding, ScalarIssue] {
  let mut result : Value? = None
  let mut digits = 0
  let mut magnitude = 0.0
  let mut negative = false
  if left is Null || right is Null {
    result = Some(Null)
  } else {
    guard left is Number(value) && right is Number(position) else {
      return Err(InvalidOperand)
    }
    if value.is_nan() ||
      value.is_inf() ||
      position.is_nan() ||
      position.is_inf() {
      return Err(InvalidOperand)
    }
    if position.trunc() != position {
      return Err(ArithmeticFailure)
    }
    negative = value < 0.0
    magnitude = if negative { -value } else { value }
    if position == 0.0 {
      result = Some(
        unary(
          if op == @lower.RoundAt {
            @lower.Round
          } else {
            @lower.Trunc
          },
          left,
        ).unwrap(),
      )
    } else if value == 0.0 || position > 323.0 {
      result = Some(Number(if value == 0.0 { 0.0 } else { value }))
    } else if position < -308.0 {
      result = Some(Number(0.0))
    } else {
      digits = position.to_int()
      let bits = value.reinterpret_as_uint64() & 0x7fffffffffffffffUL
      let encoded = (bits >> 52).to_int()
      let fraction = bits & 0x000fffffffffffffUL
      let significand = if encoded == 0 {
        fraction
      } else {
        fraction | 0x0010000000000000UL
      }
      let binary_extent = if encoded == 0 {
        @bigint.BigInt::from_uint64(significand).bit_length() - 1074
      } else {
        encoded - 1022
      }
      // Preserve the selected GoogleSQL range reductions, including its
      // finite-FLOAT64 extreme-position behavior, before growing integers.
      let lower_scale = if digits < 0 { 3 } else { 4 }
      let upper_scale = if digits < 0 { 4 } else { 3 }
      if -digits * lower_scale > binary_extent + 1 {
        result = Some(Number(0.0))
      } else if -digits * upper_scale < binary_extent - 55 {
        result = Some(Number(value))
      }
    }
  }
  Ok({
    round: op == @lower.RoundAt,
    negative,
    digits,
    magnitude,
    remaining: if digits < 0 {
      -digits
    } else {
      digits
    },
    phase: 0,
    power: @bigint.BigInt::from_int(1),
    factor: @bigint.BigInt::from_int(5),
    forward: { hi: 0.0, lo: 0.0, },
    reverse: { hi: 0.0, lo: 0.0, },
    first: { hi: 0.0, lo: 0.0, },
    second: { hi: 0.0, lo: 0.0, },
    rounded: { hi: 0.0, lo: 0.0, },
    intermediate: 0.0,
    result,
  })
}

///|
// Round a nonnegative, bounded rational exactly to nearest-even binary64.
// Decimal integer selection is separate: halfway ROUND ties are away from
// zero, whereas this representation conversion uses IEEE nearest-even.
fn decimal_round_ratio(
  numerator : @bigint.BigInt,
  denominator : @bigint.BigInt,
) -> Result[Double, ScalarIssue] {
  if numerator.is_zero() {
    return Ok(0.0)
  }
  let mut exponent = numerator.bit_length() - denominator.bit_length()
  if (if exponent >= 0 {
      numerator < denominator << exponent
    } else {
      numerator << -exponent < denominator
    }) {
    exponent -= 1
  }
  if exponent > 1023 {
    return Err(ArithmeticFailure)
  }
  let shift = if exponent < -1022 { 1074 } else { 52 - exponent }
  let scaled_numerator = if shift >= 0 { numerator << shift } else { numerator }
  let scaled_denominator = if shift < 0 {
    denominator << -shift
  } else {
    denominator
  }
  let mut significand = scaled_numerator / scaled_denominator
  let residual = (scaled_numerator % scaled_denominator) << 1
  if residual > scaled_denominator ||
    (residual == scaled_denominator && (significand.to_uint64() & 1UL) == 1UL) {
    significand += @bigint.BigInt::from_int(1)
  }
  let mut bits = significand.to_uint64()
  if exponent < -1022 {
    return Ok(bits.reinterpret_as_double())
  }
  if bits == 0x0020000000000000UL {
    bits = bits >> 1
    exponent += 1
    if exponent > 1023 {
      return Err(ArithmeticFailure)
    }
  }
  Ok(
    (((exponent + 1023).to_uint64() << 52) | (bits & 0x000fffffffffffffUL)).reinterpret_as_double(),
  )
}

///|
// GoogleSQL rounds the extended product's high part to binary64 before the
// final ldexp. Preserve that second rounding for subnormal outputs; directly
// rounding the exact final decimal rational differs by one ULP there.
fn decimal_round_binary_scale(
  value : Double,
  shift : Int,
) -> Result[Double, ScalarIssue] {
  if value == 0.0 {
    return Ok(0.0)
  }
  let bits = value.reinterpret_as_uint64()
  let mut encoded = (bits >> 52).to_int()
  let mut fraction = bits & 0x000fffffffffffffUL
  if encoded == 2047 {
    return Err(ArithmeticFailure)
  }
  if encoded == 0 {
    let width = @bigint.BigInt::from_uint64(fraction).bit_length()
    let normalize = 53 - width
    fraction = (fraction << normalize) & 0x000fffffffffffffUL
    encoded = 1 - normalize
  }
  let adjusted = encoded + shift
  if adjusted >= 2047 {
    return Err(ArithmeticFailure)
  }
  if adjusted > 0 {
    return Ok(((adjusted.to_uint64() << 52) | fraction).reinterpret_as_double())
  }
  let drop = 1 - adjusted
  if drop > 53 {
    return Ok(0.0)
  }
  let significand = fraction | 0x0010000000000000UL
  let mut rounded = significand >> drop
  let remainder = significand & ((1UL << drop) - 1UL)
  let halfway = 1UL << (drop - 1)
  if remainder > halfway || (remainder == halfway && (rounded & 1UL) == 1UL) {
    rounded += 1UL
  }
  Ok(rounded.reinterpret_as_double())
}

///|
fn decimal_abs(value : Double) -> Double {
  if value < 0.0 {
    -value
  } else {
    value
  }
}

///|
fn decimal_half_away(value : Double) -> Double {
  let magnitude = decimal_abs(value)
  let integral = magnitude.floor()
  let rounded = if magnitude - integral >= 0.5 {
    integral + 1.0
  } else {
    integral
  }
  if value < 0.0 {
    -rounded
  } else {
    rounded
  }
}

///|
fn decimal_fast_sum(a : Double, b : Double) -> DecimalPair {
  let hi = a + b
  { hi, lo: b - (hi - a), }
}

///|
fn decimal_pair_sum(a : Double, b : Double) -> DecimalPair {
  let hi = a + b
  let a1 = hi - b
  let b1 = hi - a1
  { hi, lo: a - a1 + (b - b1), }
}

///|
fn decimal_split(value : Double) -> DecimalPair {
  // The guarded decimal domain never reaches Split's generic overflow case.
  let multiplied = 134217729.0 * value
  let hi = multiplied + (value - multiplied)
  { hi, lo: value - hi, }
}

///|
fn decimal_pair_product(a : Double, b : Double) -> DecimalPair {
  // All nonzero intermediate products are normal in this guarded domain.
  // Keep every operation separate and in the reference's original order.
  let hi = a * b
  let first = decimal_split(a)
  let second = decimal_split(b)
  let high_product = first.hi * second.hi
  let residual = -hi + high_product
  let residual = residual + first.hi * second.lo
  let residual = residual + first.lo * second.hi
  let residual = residual + first.lo * second.lo
  decimal_fast_sum(hi, residual)
}

///|
fn decimal_pair_multiply(a : DecimalPair, b : DecimalPair) -> DecimalPair {
  let product = decimal_pair_product(a.hi, b.hi)
  let residual = a.hi * b.lo + product.lo
  let residual = residual + a.lo * b.hi
  decimal_fast_sum(product.hi, residual)
}

///|
// Regenerate the selected reference table entry exactly: high=RN(5^n),
// low=RN(5^n-high). The complete 647-entry source table was independently
// compared bit-for-bit; no host decimal parse or platform pow is used here.
fn decimal_power_pair(
  power : @bigint.BigInt,
  inverse : Bool,
) -> Result[DecimalPair, ScalarIssue] {
  let one = @bigint.BigInt::from_int(1)
  let numerator = if inverse { one } else { power }
  let denominator = if inverse { power } else { one }
  let hi = match decimal_round_ratio(numerator, denominator) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let bits = hi.reinterpret_as_uint64()
  let significand = @bigint.BigInt::from_uint64(
    (bits & 0x000fffffffffffffUL) | 0x0010000000000000UL,
  )
  let exponent = (bits >> 52).to_int() - 1075
  let residual = if exponent >= 0 {
    numerator - (significand << exponent) * denominator
  } else {
    (numerator << -exponent) - significand * denominator
  }
  let divisor = if exponent < 0 {
    denominator << -exponent
  } else {
    denominator
  }
  let negative = residual.compare_int(0) < 0
  let lo = match
    decimal_round_ratio(if negative { -residual } else { residual }, divisor) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ hi, lo: if negative { -lo } else { lo }, })
}

///|
fn decimal_select_integer(state : DecimalRounding) -> DecimalPair {
  let r1 = if state.round {
    decimal_half_away(state.first.hi)
  } else {
    state.first.hi.trunc()
  }
  let error = state.first.hi - r1
  let mid = decimal_pair_sum(state.first.lo, state.second.hi)
  let correction = decimal_fast_sum(error, mid.hi)
  let error_bound = r1 * 0x3960000000000000UL.reinterpret_as_double()
  let mut high = correction.hi
  if decimal_abs(high) <= error_bound {
    return { hi: r1, lo: 0.0, }
  }
  if (high.reinterpret_as_uint64() & 0x00003fffffffffffUL) == 0UL {
    let low = state.second.lo + mid.lo + correction.lo
    let sign_product = correction.hi * low
    if decimal_abs(low) > error_bound {
      if sign_product < 0.0 {
        high = (high.reinterpret_as_uint64() - 1UL).reinterpret_as_double()
      } else if state.round && sign_product > 0.0 {
        high = (high.reinterpret_as_uint64() + 1UL).reinterpret_as_double()
      }
    }
  }
  let r2 = if high < 0.0 {
    if state.round {
      let rounded = decimal_half_away(high)
      if high - rounded == 0.5 {
        rounded + 1.0
      } else {
        rounded
      }
    } else {
      high.floor()
    }
  } else if state.round {
    decimal_half_away(high)
  } else {
    high.trunc()
  }
  decimal_fast_sum(r1, r2)
}

///|
fn advance_decimal_rounding(
  state : DecimalRounding,
) -> Result[Value?, ScalarIssue] {
  if state.result is Some(value) {
    return Ok(Some(value))
  }
  match state.phase {
    0 => {
      if state.remaining > 0 {
        if state.remaining % 2 == 1 {
          state.power *= state.factor
        }
        state.remaining /= 2
        if state.remaining > 0 {
          state.factor *= state.factor
        }
      }
      if state.remaining == 0 {
        state.phase = 1
      }
      Ok(None)
    }
    1 => {
      state.forward = match decimal_power_pair(state.power, state.digits < 0) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      state.phase = 2
      Ok(None)
    }
    2 => {
      state.reverse = match decimal_power_pair(state.power, state.digits > 0) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      state.phase = 3
      Ok(None)
    }
    3 => {
      let scaled = match
        decimal_round_binary_scale(state.magnitude, state.digits) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      state.first = decimal_pair_product(scaled, state.forward.hi)
      state.second = decimal_pair_product(scaled, state.forward.lo)
      state.phase = 4
      Ok(None)
    }
    4 => {
      state.rounded = decimal_select_integer(state)
      state.phase = 5
      Ok(None)
    }
    5 => {
      state.intermediate = decimal_pair_multiply(state.rounded, state.reverse).hi
      state.phase = 6
      Ok(None)
    }
    _ => {
      let scaled = match
        decimal_round_binary_scale(state.intermediate, -state.digits) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let value = Number(
        if scaled == 0.0 {
          0.0
        } else if state.negative {
          -scaled
        } else {
          scaled
        },
      )
      state.result = Some(value)
      Ok(Some(value))
    }
  }
}

///|
fn decimal_round_binary(
  op : @lower.BinaryOperator,
  left : Value,
  right : Value,
) -> Result[Value, ScalarIssue] {
  let state = match start_decimal_rounding(op, left, right) {
    Ok(state) => state
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_decimal_rounding(state) {
      Ok(Some(value)) => return Ok(value)
      Ok(None) => ()
      Err(issue) => return Err(issue)
    }
  }
  Err(InvalidOperand)
}
