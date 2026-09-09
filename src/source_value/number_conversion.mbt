///|
/// Convert an already grammar-checked JSON token. Rebase the exact significand
/// to one leading nonzero digit before calling the binary64 converter, so its
/// exponent accumulator cannot lose cancellation with a long fractional part.
/// Interior significant digits are retained, including arbitrarily late digits
/// that distinguish an exact rounding midpoint from a value just above it.
fn Parser::read_binary64(
  self : Parser,
  start : Int,
  path : Array[PathSegment],
) -> Double raise ParseAbort {
  let negative = self.source[start].to_int() == 0x2d
  let mut index = start + (if negative { 1 } else { 0 })
  let mut digits = 0
  let mut decimal_position = -1
  let mut first_nonzero = -1
  let mut first_ordinal = 0
  let mut last_nonzero = -1
  while index < self.offset {
    let unit = self.source[index].to_int()
    if unit == 0x65 || unit == 0x45 {
      break
    }
    if unit == 0x2e {
      decimal_position = digits
    } else {
      if unit != 0x30 {
        if first_nonzero < 0 {
          first_nonzero = index
          first_ordinal = digits
        }
        last_nonzero = index
      }
      digits += 1
    }
    index += 1
  }
  if decimal_position < 0 {
    decimal_position = digits
  }
  // Zero is independent of the exponent, but JSON source still rejects -0.
  if first_nonzero < 0 {
    if negative {
      self.fail(NegativeZero, path)
    }
    return 0.0
  }
  let mut exponent = 0L
  let mut negative_exponent = false
  if index < self.offset {
    index += 1
    let sign = self.source[index].to_int()
    if sign == 0x2d || sign == 0x2b {
      negative_exponent = sign == 0x2d
      index += 1
    }
    // The mantissa's decimal displacement has magnitude below token length.
    // Beyond length + 400, even maximal cancellation remains outside [-324,308].
    // Saturation therefore preserves overflow/underflow classification. Int64
    // keeps multiplication safe even near the maximum admitted input length.
    let cap = (self.offset - start).to_int64() + 400L
    while index < self.offset {
      if exponent < cap {
        exponent = exponent * 10L +
          (self.source[index].to_int() - 0x30).to_int64()
        if exponent > cap {
          exponent = cap
        }
      }
      index += 1
    }
  }
  if negative_exponent {
    exponent = -exponent
  }
  let power = exponent +
    decimal_position.to_int64() -
    first_ordinal.to_int64() -
    1L
  if power > 308L {
    self.fail(NumberOutOfRange, path)
  }
  if power < -324L {
    if negative {
      self.fail(NegativeZero, path)
    }
    return 0.0
  }
  let spelling = StringBuilder()
  if negative {
    spelling.write_char('-')
  }
  spelling.write_char(self.source[first_nonzero].to_int().unsafe_to_char())
  if last_nonzero > first_nonzero {
    spelling.write_char('.')
    for i = first_nonzero + 1; i <= last_nonzero; i = i + 1 {
      let unit = self.source[i].to_int()
      if unit != 0x2e {
        spelling.write_char(unit.unsafe_to_char())
      }
    }
  }
  spelling.write_char('e')
  spelling.write_string(power.to_string())
  let number = @string.parse_double(spelling.to_string()) catch {
    _ => self.fail(NumberOutOfRange, path)
  }
  if number.is_nan() || number.is_inf() {
    self.fail(NumberOutOfRange, path)
  }
  if number.reinterpret_as_uint64() == 0x8000000000000000UL {
    self.fail(NegativeZero, path)
  }
  number
}
