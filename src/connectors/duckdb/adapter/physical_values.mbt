///|
// Parsing is bounded before invoking BigInt's parser. Reject syntax that its
// general parser might otherwise accept; this is an exact transport coefficient.
fn integer_text(text : String) -> @bigint.BigInt? {
  if text.length() == 0 || text.length() > 40 {
    return None
  }
  let start = if text[0] == '-' { 1 } else { 0 }
  if text.length() == start ||
    (text[start] == '0' && (text.length() - start != 1 || start != 0)) {
    return None
  }
  for i in start..<text.length() {
    if text[i] < '0' || text[i] > '9' {
      return None
    }
  }
  Some(@bigint.BigInt::from_string(text))
}

///|
fn in_integer_range(value : @bigint.BigInt, bits : Int, signed : Bool) -> Bool {
  let one = @bigint.BigInt::from_int(1)
  let top = one << (if signed { bits - 1 } else { bits })
  value < top &&
  value >= (if signed { -top } else { @bigint.BigInt::from_int(0) })
}

///|
fn exact_number(value : @bigint.BigInt) -> Double? {
  if value.is_zero() {
    return Some(0.0)
  }
  let negative = value.compare_int(0) < 0
  let magnitude = if negative { -value } else { value }
  let shift = magnitude.ctz()
  if magnitude.bit_length() - shift > 53 {
    return None
  }
  let mut number = (magnitude >> shift).to_uint64().to_double()
  for _ in 0..<shift {
    number *= 2.0
  }
  Some(if negative { -number } else { number })
}

///|
fn hex_bits(text : String, width : Int) -> UInt64? {
  if text.length() != width {
    return None
  }
  let mut value = 0UL
  // Accumulate eight nibbles in a machine word before widening. In the JS
  // target UInt64 uses BigInt: widening every nibble allocates for every digit
  // of every floating-point cell. This preserves the exact bits and syntax.
  let mut word = 0U
  let mut digits = 0
  for i in 0..<width {
    let c = text[i].to_int()
    let digit = if c >= 48 && c <= 57 {
      c - 48
    } else if c >= 97 && c <= 102 {
      c - 97 + 10
    } else {
      return None
    }
    word = (word << 4) | digit.reinterpret_as_uint()
    digits += 1
    if digits == 8 {
      value = (value << 32) | word.to_uint64()
      word = 0U
      digits = 0
    }
  }
  if digits > 0 {
    value = (value << (digits * 4)) | word.to_uint64()
  }
  Some(value)
}

///|
fn pad(value : Int, size : Int) -> String {
  let text = value.to_string()
  let builder = StringBuilder()
  for _ in text.length()..<size {
    builder.write_string("0")
  }
  builder.write_string(text)
  builder.to_string()
}

///|
fn year_start(year : Int) -> Int {
  365 * year + (year + 3) / 4 - (year + 99) / 100 + (year + 399) / 400 - 719528
}

///|
// At most fourteen year comparisons and twelve month steps. This is physical
// epoch conversion, not a replacement for shared Gregorian value admission.
fn date_text(days : Int) -> String? {
  if days < year_start(0) || days >= year_start(10000) {
    return None
  }
  let mut low = 0
  let mut high = 10000
  while high - low > 1 {
    let middle = (low + high) / 2
    if year_start(middle) <= days {
      low = middle
    } else {
      high = middle
    }
  }
  let year = low
  let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
  let mut day = days - year_start(year)
  let mut month = 1
  for
    length in [
      31,
      if leap {
        29
      } else {
        28
      },
      31,
      30,
      31,
      30,
      31,
      31,
      30,
      31,
      30,
      31,
    ] {
    if day < length {
      break
    }
    day -= length
    month += 1
  }
  Some(pad(year, 4) + "-" + pad(month, 2) + "-" + pad(day + 1, 2))
}

///|
fn timestamp_text(micros : Int64) -> Result[String, ValueIssue] {
  if micros % 1000L != 0L {
    return Err(LossyTimestamp)
  }
  let millis = micros / 1000L
  if millis < -62167219200000L || millis > 253402300799999L {
    return Err(OutOfRange)
  }
  let mut days = millis / 86400000L
  let mut within = millis % 86400000L
  if within < 0L {
    days -= 1L
    within += 86400000L
  }
  guard date_text(days.to_int()) is Some(date) else { return Err(OutOfRange) }
  let time = within.to_int()
  Ok(
    date +
    "T" +
    pad(time / 3600000, 2) +
    ":" +
    pad(time / 60000 % 60, 2) +
    ":" +
    pad(time / 1000 % 60, 2) +
    "." +
    pad(time % 1000, 3) +
    "Z",
  )
}

///|
fn decimal_text(coefficient : String, scale : Int) -> String {
  let negative = coefficient[0] == '-'
  let digits = if negative { coefficient[1:].to_owned() } else { coefficient }
  let builder = StringBuilder()
  if negative {
    builder.write_string("-")
  }
  if digits.length() <= scale {
    builder.write_string("0.")
    for _ in digits.length()..<scale {
      builder.write_string("0")
    }
    builder.write_string(digits)
  } else {
    for i in 0..<digits.length() {
      if scale > 0 && i == digits.length() - scale {
        builder.write_string(".")
      }
      builder.write_char(digits[i].to_int().unsafe_to_char())
    }
  }
  builder.to_string()
}

///|
/// Decode a physical scalar and delegate all ActQL value rules to the shared
/// admission. The payload is the primitive emitted by the private Node codec.
/// Returned errors retain the original transport cursor's source span.
pub fn admit_physical_value(
  mapping : ValueMapping,
  payload : @decode.Cursor,
  limits : @admitted.Limits,
) -> Result[@admitted.CheckedValue, ValueIssue] {
  admit_physical_usage(mapping, payload, limits).map(result => result.0)
}

///|
fn admit_physical_usage(
  mapping : ValueMapping,
  payload : @decode.Cursor,
  limits : @admitted.Limits,
) -> Result[(@admitted.CheckedValue, Int, Int), ValueIssue] {
  if limits.max_nodes < 0 || limits.max_depth < 0 || limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  if limits.max_nodes == 0 ||
    @decode.is_null(payload) ||
    mapping.physical == Boolean ||
    mapping.physical == Varchar {
    return @admitted.admit_usage(mapping.contract, payload, limits).map_err(issue => {
      Admission(issue)
    })
  }
  if mapping.physical is DoubleArray(length~) {
    if limits.max_nodes <= length || limits.max_depth < 1 {
      return Err(
        Admission(
          @admitted.ValueIssue(
            @admitted.IssueKind::BudgetExceeded,
            path=[],
            span=@decode.cursor_span(payload),
          ),
        ),
      )
    }
    let text = match @decode.text(payload) {
      Ok(value) => value
      Err(issue) => return Err(Decode(issue))
    }
    let parts = text.split(",").to_array()
    if parts.length() != length {
      return Err(InvalidPhysicalValue)
    }
    let span = @decode.cursor_span(payload)
    let items : Array[@source.Node] = []
    for part in parts {
      let value = if part == "null" {
        @source.Null
      } else {
        guard hex_bits(part.to_owned(), 16) is Some(bits) else {
          return Err(InvalidPhysicalValue)
        }
        @source.Number(bits.reinterpret_as_double())
      }
      items.push({ value, span, })
    }
    let converted = match
      @decode.admit({ value: @source.Array(items), span, }, {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_string_bytes: limits.max_text_bytes,
        max_total_string_bytes: limits.max_text_bytes,
      }) {
      Ok(value) => value
      Err(issue) => return Err(Decode(issue))
    }
    return @admitted.admit_usage(mapping.contract, converted, limits).map_err(issue => {
      Admission(issue)
    })
  }
  let text = match @decode.text(payload) {
    Ok(value) => value
    Err(issue) => return Err(Decode(issue))
  }
  let value : @source.Value = match mapping.physical {
    Float32 => {
      guard hex_bits(text, 8) is Some(bits) else {
        return Err(InvalidPhysicalValue)
      }
      Number(Float::reinterpret_from_uint(bits.to_uint()).to_double())
    }
    Float64 => {
      guard hex_bits(text, 16) is Some(bits) else {
        return Err(InvalidPhysicalValue)
      }
      Number(bits.reinterpret_as_double())
    }
    Integer(bits~, signed~) => {
      guard integer_text(text) is Some(integer) else {
        return Err(InvalidPhysicalValue)
      }
      if !in_integer_range(integer, bits, signed) {
        return Err(OutOfRange)
      }
      guard exact_number(integer) is Some(number) else {
        return Err(LossyInteger)
      }
      Number(number)
    }
    Decimal(precision~, scale~) => {
      guard integer_text(text) is Some(integer) else {
        return Err(InvalidPhysicalValue)
      }
      let digits = text.length() -
        (if integer.compare_int(0) < 0 { 1 } else { 0 })
      if digits > precision {
        return Err(OutOfRange)
      }
      String(decimal_text(text, scale))
    }
    Date => {
      guard integer_text(text) is Some(integer) else {
        return Err(InvalidPhysicalValue)
      }
      if !in_integer_range(integer, 32, true) {
        return Err(OutOfRange)
      }
      guard date_text(integer.to_int()) is Some(date) else {
        return Err(OutOfRange)
      }
      String(date)
    }
    TimestampTZ => {
      guard integer_text(text) is Some(integer) else {
        return Err(InvalidPhysicalValue)
      }
      if !in_integer_range(integer, 64, true) {
        return Err(OutOfRange)
      }
      let timestamp = match timestamp_text(integer.to_int64()) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      String(timestamp)
    }
    NaiveTimestamp => return Err(ImplicitTimezone)
    Boolean | Varchar | DoubleArray(_) => return Err(TypeMismatch)
  }
  let converted = match
    @decode.admit({ value, span: @decode.cursor_span(payload), }, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_text_bytes,
      max_total_string_bytes: limits.max_text_bytes,
    }) {
    Ok(value) => value
    Err(issue) => return Err(Decode(issue))
  }
  let admitted = if mapping.contract.shape is @contract.Number {
    @admitted.admit_number_usage(mapping.contract, converted, limits)
  } else {
    @admitted.admit_usage(mapping.contract, converted, limits)
  }
  admitted.map_err(issue => Admission(issue))
}
