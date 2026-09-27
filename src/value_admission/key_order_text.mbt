///|
/// Hexadecimal digits in ascending UTF-16 order.
let key_hex_digits : String = "0123456789abcdef"

///|
/// Exponents of admitted decimals stay far inside this bias; a value outside
/// it has no order-preserving text key.
const DECIMAL_EXPONENT_BIAS : Int = 500000

///|
fn binary64_order_text(value : Double) -> String {
  let bits = value.reinterpret_as_uint64()
  let ordered = if bits >> 63 == 1UL {
    bits.lnot()
  } else {
    bits | 0x8000000000000000UL
  }
  let out = StringBuilder()
  for shift = 60; shift >= 0; shift = shift - 4 {
    let digit = ((ordered >> shift) & 15UL).to_int()
    out.write_char(key_hex_digits[digit].to_int().unsafe_to_char())
  }
  out.to_string()
}

///|
fn fixed_digits(value : Int, width : Int) -> String {
  let text = value.to_string()
  "0".repeat(width - text.length()) + text
}

///|
/// Sign, exponent and significant digits, so that UTF-16 order equals exact
/// numeric order across precision and scale. Negative magnitudes invert the
/// exponent and digits and end with a terminator above every digit.
fn decimal_order_text(value : DecimalValue) -> String? {
  let coefficient = value.coefficient
  if coefficient == "0" {
    return Some("1")
  }
  let negative = coefficient[0] == '-'
  let offset = if negative { 1 } else { 0 }
  let mut end = coefficient.length()
  while end > offset + 1 && coefficient[end - 1] == '0' {
    end = end - 1
  }
  let exponent = coefficient.length() - offset - value.scale
  let biased = exponent + DECIMAL_EXPONENT_BIAS
  if biased < 0 || biased >= 2 * DECIMAL_EXPONENT_BIAS {
    return None
  }
  let out = StringBuilder()
  if negative {
    out.write_string("0")
    out.write_string(fixed_digits(2 * DECIMAL_EXPONENT_BIAS - 1 - biased, 7))
    for index in offset..<end {
      let digit = coefficient[index].to_int() - '0'.to_int()
      out.write_char(('9'.to_int() - digit).unsafe_to_char())
    }
    out.write_char('~')
  } else {
    out.write_string("2")
    out.write_string(fixed_digits(biased, 7))
    for index in offset..<end {
      out.write_char(coefficient[index].to_int().unsafe_to_char())
    }
  }
  Some(out.to_string())
}

///|
/// Text whose UTF-16 order equals the canonical typed key order of non-null
/// KeyComparable values of one comparable domain: numeric order for numbers
/// and decimals, false before true, and UTF-16 order for text, dates,
/// timestamps and live reference identities. Specifications that require
/// canonical typed ID order, such as Graph snapshot identity, sort by it;
/// the canonical key encoding is a different order.
pub fn typed_key_order_text(
  checked : CheckedValue,
) -> Result[String, KeyOrderIssue] {
  match (checked.value, checked.contract.shape) {
    (Number(value), @contract.Number) => Ok(binary64_order_text(value))
    (Boolean(value), @contract.Boolean) => Ok(if value { "1" } else { "0" })
    (Text(value), @contract.Text(_))
    | (Date(value), @contract.Date)
    | (Timestamp(value), @contract.Timestamp) => Ok(value)
    (Decimal(value), @contract.Decimal(..)) =>
      match decimal_order_text(value) {
        Some(text) => Ok(text)
        None => Err(InvalidKey)
      }
    (Reference(value), @contract.ResourceRef(..))
    | (Reference(value), @contract.ArtifactRef(..)) =>
      if reference_available(value) {
        Ok(reference_identity_cid(value))
      } else {
        Err(UnavailableReference)
      }
    _ => Err(InvalidKey)
  }
}
