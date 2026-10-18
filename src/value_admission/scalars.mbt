///|
// Validate canonical spelling and magnitude before exact negative accumulation.
// The negative accumulator includes Int64::min_value without positive overflow.
fn signed64(text : String) -> Int64? {
  let size = text.length()
  let negative = size > 0 && text[0] == '-'
  let start = if negative { 1 } else { 0 }
  let digits = size - start
  if digits < 1 || digits > 19 {
    return None
  }
  if text[start] == '0' && (negative || digits != 1) {
    return None
  }
  let limit = if negative {
    "9223372036854775808"
  } else {
    "9223372036854775807"
  }
  let mut order = 0
  for index in start..<size {
    let unit = text[index]
    if unit < '0' || unit > '9' {
      return None
    }
    if digits == 19 && order == 0 && unit != limit[index - start] {
      order = if unit < limit[index - start] { -1 } else { 1 }
    }
  }
  if order > 0 {
    return None
  }
  let mut value = 0L
  for index in start..<size {
    value = value * 10L - (text[index].to_int() - '0'.to_int()).to_int64()
  }
  Some(if negative { value } else { -value })
}

///|
// Parse only canonical fixed-scale wire text. No binary64 or bounded integer
// accumulator is involved, including at precision 38.
fn decimal(text : String, precision : Int, scale : Int) -> DecimalValue? {
  let size = text.length()
  let negative = size > 0 && text[0] == '-'
  let start = if negative { 1 } else { 0 }
  let integer_end = size - (if scale == 0 { 0 } else { scale + 1 })
  if integer_end <= start || size - start > precision + scale + 2 {
    return None
  }
  if scale > 0 && text[integer_end] != '.' {
    return None
  }
  if integer_end - start > 1 && text[start] == '0' {
    return None
  }
  let digits = StringBuilder()
  let mut significant = 0
  for index = start; index < size; index = index + 1 {
    if scale > 0 && index == integer_end {
      continue
    }
    let unit = text[index]
    if unit < '0' || unit > '9' {
      return None
    }
    if significant != 0 || unit != '0' {
      significant += 1
      if significant > precision {
        return None
      }
      digits.write_char(unit.to_int().unsafe_to_char())
    }
  }
  if significant == 0 {
    if negative {
      return None
    }
    Some({ coefficient: "0", precision, scale, })
  } else {
    let coefficient = (if negative { "-" } else { "" }) + digits.to_string()
    Some({ coefficient, precision, scale, })
  }
}

///|
/// Construct an admitted exact Decimal leaf from its canonical signed
/// coefficient. This is for checked arithmetic that already operates in the
/// Decimal domain; it does not parse wire text, round, or coerce binary64.
///
/// The coefficient has no leading zeroes, `-0` is rejected, and the declared
/// precision/scale must itself be a valid ActQL Decimal contract. Callers still
/// own the arithmetic law and the result contract that select these values.
pub fn decimal_from_coefficient(
  coefficient : String,
  precision : Int,
  scale : Int,
) -> Value? {
  if precision < 1 || precision > 38 || scale < 0 || scale > precision {
    return None
  }
  let size = coefficient.length()
  let negative = size > 0 && coefficient[0] == '-'
  let start = if negative { 1 } else { 0 }
  let count = size - start
  if count < 1 || count > precision {
    return None
  }
  if coefficient[start] == '0' {
    if count != 1 || negative {
      return None
    }
  }
  for index = start; index < size; index = index + 1 {
    let unit = coefficient[index]
    if unit < '0' || unit > '9' {
      return None
    }
  }
  Some(Decimal({ coefficient, precision, scale, }))
}

///|
fn digits(text : String, start : Int, end : Int) -> Int? {
  let mut result = 0
  for index = start; index < end; index = index + 1 {
    let unit = text[index].to_int()
    if unit < 48 || unit > 57 {
      return None
    }
    result = result * 10 + unit - 48
  }
  Some(result)
}

///|
fn valid_date(text : String) -> Bool {
  if text.length() < 10 || text[4] != '-' || text[7] != '-' {
    return false
  }
  match (digits(text, 0, 4), digits(text, 5, 7), digits(text, 8, 10)) {
    (Some(year), Some(month), Some(day)) => {
      if month < 1 || month > 12 {
        return false
      }
      let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
      let days = if month == 2 {
        if leap {
          29
        } else {
          28
        }
      } else if [4, 6, 9, 11].contains(month) {
        30
      } else {
        31
      }
      day >= 1 && day <= days
    }
    _ => false
  }
}

///|
fn valid_timestamp(text : String) -> Bool {
  timestamp_instant(text) is Some(_)
}

///|
/// Comparison-context DATA only. The original typed int64 peer and immediate
/// Number-literal occurrence are checked by expression typing, not this helper.
/// Bounds precede conversion: binary64 +2^63 must never saturate to int64 max.
pub fn signed64_comparison_literal_value(number : Double) -> Value? {
  if @scalar.read_integer_number(number) is None ||
    number < -9223372036854775808.0 ||
    number >= 9223372036854775808.0 {
    return None
  }
  let integer = number.to_int64()
  if integer.to_double() != number {
    return None
  }
  Some(signed64_value(integer))
}
