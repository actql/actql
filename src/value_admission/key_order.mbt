///|
pub(all) enum KeyOrderIssue {
  InvalidKey
  UnavailableReference
  DifferentReferenceDomain
} derive(Eq, Debug)

///|
/// Bind a finite execution result to an exact non-null number contract.
pub fn checked_number_value(
  value : Double,
  contract : @contract.Contract,
) -> CheckedValue? {
  guard !contract.nullable &&
    contract.shape is @contract.Number &&
    number_value(value) is Some(number) else {
    return None
  }
  Some({ contract, value: number, })
}

///|
/// Exact decimal order without conversion to binary64.
fn compare_key_decimal(left : DecimalValue, right : DecimalValue) -> Int {
  let a = left.coefficient
  let b = right.coefficient
  let negative_a = a[0] == '-'
  let negative_b = b[0] == '-'
  if a == "0" {
    return if b == "0" { 0 } else if negative_b { 1 } else { -1 }
  }
  if b == "0" {
    return if negative_a { -1 } else { 1 }
  }
  if negative_a != negative_b {
    return if negative_a { -1 } else { 1 }
  }
  let offset_a = if negative_a { 1 } else { 0 }
  let offset_b = if negative_b { 1 } else { 0 }
  let digits_a = a.length() - offset_a
  let digits_b = b.length() - offset_b
  let exponent_a = digits_a - left.scale
  let exponent_b = digits_b - right.scale
  let direction = if negative_a { -1 } else { 1 }
  if exponent_a != exponent_b {
    return (if exponent_a < exponent_b { -1 } else { 1 }) * direction
  }
  for index in 0..<Int::max(digits_a, digits_b) {
    let digit_a = if index < digits_a { a[offset_a + index] } else { '0' }
    let digit_b = if index < digits_b { b[offset_b + index] } else { '0' }
    if digit_a != digit_b {
      return (if digit_a < digit_b { -1 } else { 1 }) * direction
    }
  }
  0
}

///|
/// Compare non-null KeyComparable values using their semantic type order.
pub fn compare_key_values(
  left : CheckedValue,
  right : CheckedValue,
) -> Result[Int, KeyOrderIssue] {
  if left.contract.nullable || right.contract.nullable {
    return Err(InvalidKey)
  }
  match (left.value, right.value, left.contract.shape, right.contract.shape) {
    (Number(a), Number(b), @contract.Number, @contract.Number) =>
      Ok(if a < b { -1 } else if a > b { 1 } else { 0 })
    (Boolean(a), Boolean(b), @contract.Boolean, @contract.Boolean) =>
      Ok(if a == b { 0 } else if a { 1 } else { -1 })
    (Text(a), Text(b), @contract.Text(_), @contract.Text(_))
    | (Date(a), Date(b), @contract.Date, @contract.Date)
    | (Timestamp(a), Timestamp(b), @contract.Timestamp, @contract.Timestamp) =>
      Ok(@canonical.compare_utf16(a, b))
    (Decimal(a), Decimal(b), @contract.Decimal(..), @contract.Decimal(..)) =>
      Ok(compare_key_decimal(a, b))
    (
      Reference(a),
      Reference(b),
      @contract.ResourceRef(..),
      @contract.ResourceRef(..),
    )
    | (
      Reference(a),
      Reference(b),
      @contract.ArtifactRef(..),
      @contract.ArtifactRef(..),
    ) => {
      if !reference_available(a) || !reference_available(b) {
        return Err(UnavailableReference)
      }
      if !reference_same_domain(a, b) {
        return Err(DifferentReferenceDomain)
      }
      Ok(
        @canonical.compare_utf16(
          reference_identity_cid(a),
          reference_identity_cid(b),
        ),
      )
    }
    _ => Err(InvalidKey)
  }
}
