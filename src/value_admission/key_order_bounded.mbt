///|
priv enum BoundedKeyKind {
  FixedOrder(Int)
  TextOrder(String, String)
  DecimalOrder(DecimalValue, DecimalValue)
}

///|
struct BoundedKeyComparison {
  kind : BoundedKeyKind
  mut index : Int
  mut terminal : Bool
}

///|
pub enum BoundedKeyComparisonPoll {
  KeyComparisonContinue(work~ : Int)
  KeyComparisonComplete(order~ : Int, work~ : Int)
}

///|
pub fn start_bounded_key_comparison(
  left : CheckedValue,
  right : CheckedValue,
) -> Result[BoundedKeyComparison, KeyOrderIssue] {
  if left.contract.nullable || right.contract.nullable {
    return Err(InvalidKey)
  }
  start_bounded_nonnull_comparison(left, right)
}

///|
/// Start comparing two components of a declared-nullable domain, such as
/// Graph edge labels, in canonical typed order with nulls first.
pub fn start_bounded_present_key_comparison(
  left : CheckedValue,
  right : CheckedValue,
) -> Result[BoundedKeyComparison, KeyOrderIssue] {
  match (left.value, right.value) {
    (Null, Null) => Ok({ kind: FixedOrder(0), index: 0, terminal: false, })
    (Null, _) => Ok({ kind: FixedOrder(-1), index: 0, terminal: false, })
    (_, Null) => Ok({ kind: FixedOrder(1), index: 0, terminal: false, })
    _ => start_bounded_nonnull_comparison(left, right)
  }
}

///|
fn start_bounded_nonnull_comparison(
  left : CheckedValue,
  right : CheckedValue,
) -> Result[BoundedKeyComparison, KeyOrderIssue] {
  let kind = match
    (left.value, right.value, left.contract.shape, right.contract.shape) {
    (Text(a), Text(b), @contract.Text(_), @contract.Text(_))
    | (Date(a), Date(b), @contract.Date, @contract.Date)
    | (Timestamp(a), Timestamp(b), @contract.Timestamp, @contract.Timestamp) =>
      TextOrder(a, b)
    (Decimal(a), Decimal(b), @contract.Decimal(..), @contract.Decimal(..)) =>
      DecimalOrder(a, b)
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
      TextOrder(reference_identity_cid(a), reference_identity_cid(b))
    }
    _ =>
      match compare_nonnull_order_values(left, right) {
        Ok(order) => FixedOrder(order)
        Err(issue) => return Err(issue)
      }
  }
  Ok({ kind, index: 0, terminal: false, })
}

///|
fn bounded_key_result(
  value : BoundedKeyComparison,
  order : Int,
  work : Int,
) -> BoundedKeyComparisonPoll {
  value.terminal = true
  KeyComparisonComplete(order~, work~)
}

///|
pub fn advance_bounded_key_comparison(
  value : BoundedKeyComparison,
  quantum : Int,
) -> Result[BoundedKeyComparisonPoll, KeyOrderIssue] {
  if value.terminal || quantum <= 0 {
    return Err(InvalidKey)
  }
  let mut work = 0
  while work < quantum {
    work += 1
    match value.kind {
      FixedOrder(order) => return Ok(bounded_key_result(value, order, work))
      TextOrder(left, right) => {
        let index = value.index
        if index < left.length() && index < right.length() {
          if left[index] != right[index] {
            return Ok(
              bounded_key_result(
                value,
                if left[index] < right[index] {
                  -1
                } else {
                  1
                },
                work,
              ),
            )
          }
          value.index += 1
        }
        if value.index >= left.length() || value.index >= right.length() {
          return Ok(
            bounded_key_result(
              value,
              if left.length() < right.length() {
                -1
              } else if left.length() > right.length() {
                1
              } else {
                0
              },
              work,
            ),
          )
        }
      }
      DecimalOrder(left, right) => {
        let a = left.coefficient
        let b = right.coefficient
        if a == "0" || b == "0" {
          return Ok(
            bounded_key_result(
              value,
              if a == b {
                0
              } else if a == "0" {
                if b[0] == '-' {
                  1
                } else {
                  -1
                }
              } else if a[0] == '-' {
                -1
              } else {
                1
              },
              work,
            ),
          )
        }
        let negative_a = a[0] == '-'
        let negative_b = b[0] == '-'
        if negative_a != negative_b {
          return Ok(
            bounded_key_result(value, if negative_a { -1 } else { 1 }, work),
          )
        }
        let offset_a = if negative_a { 1 } else { 0 }
        let offset_b = if negative_b { 1 } else { 0 }
        let digits_a = a.length() - offset_a
        let digits_b = b.length() - offset_b
        let exponent_a = digits_a - left.scale
        let exponent_b = digits_b - right.scale
        let direction = if negative_a { -1 } else { 1 }
        if exponent_a != exponent_b {
          return Ok(
            bounded_key_result(
              value,
              (if exponent_a < exponent_b { -1 } else { 1 }) * direction,
              work,
            ),
          )
        }
        let index = value.index
        let length = Int::max(digits_a, digits_b)
        if index < length {
          let digit_a = if index < digits_a { a[offset_a + index] } else { '0' }
          let digit_b = if index < digits_b { b[offset_b + index] } else { '0' }
          if digit_a != digit_b {
            return Ok(
              bounded_key_result(
                value,
                (if digit_a < digit_b { -1 } else { 1 }) * direction,
                work,
              ),
            )
          }
          value.index += 1
        }
        if value.index >= length {
          return Ok(bounded_key_result(value, 0, work))
        }
      }
    }
  }
  Ok(KeyComparisonContinue(work~))
}
