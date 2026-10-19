///|
// Structural integer/formatter scratch only; not bytes, authority or funding.
const DECIMAL_DIVISION_SLOTS : Int = 64

///|
fn decimal_division_expression_value(
  expression : @lower.Expression,
  left : Value,
  right : Value,
  mode : String,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Value, EvalIssue] {
  guard @lower.expression_contract(expression).shape
    is @contract.Decimal(precision~, scale~) &&
    ["half_even", "half_up", "toward_zero", "floor", "ceiling", "exact"].contains(
      mode,
    ) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  // The original binary evaluator has already demanded and charged both children.
  if left is Null || right is Null {
    return Ok(Null)
  }
  guard left is Captured(@admitted.Decimal(dividend)) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  // Two admitted 38-digit coefficients and scale exponent [-38,76] bound the
  // ratio numerator below 10^114 (at most 379 bits), denominator below 10^76.
  // Preflight parse/power, bounded integer arithmetic and result formatting.
  if !spend_control(control, 8 * 115 + 128) {
    return Err({ kind: ControlLimit, expression, })
  }
  if !reserve_slots(workspace, DECIMAL_DIVISION_SLOTS) {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  let result = decimal_division_value(dividend, right, precision, scale, mode)
  release_slots(workspace, DECIMAL_DIVISION_SLOTS)
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err({ kind: Scalar(issue), expression, })
  }
}

///|
fn decimal_division_value(
  left : @admitted.DecimalValue,
  right : Value,
  precision : Int,
  scale : Int,
  mode : String,
) -> Result[Value, ScalarIssue] {
  let (divisor, divisor_scale, divisor_negative) = match right {
    Captured(@admitted.Decimal(value)) =>
      (
        decimal_coefficient_magnitude(value),
        value.scale,
        value.coefficient[0] == '-',
      )
    Number(value) => {
      guard @scalar.read_safe_integer(value) is Some(integer) else {
        return Err(InvalidOperand)
      }
      (
        @bigint.BigInt::from_int64(
          if integer < 0L {
            -integer
          } else {
            integer
          },
        ),
        0,
        integer < 0L,
      )
    }
    _ => return Err(InvalidOperand)
  }
  if divisor.is_zero() {
    return Err(ArithmeticFailure)
  }
  let negative = (left.coefficient[0] == '-') != divisor_negative
  let magnitude = decimal_coefficient_magnitude(left)
  let exponent = scale + divisor_scale - left.scale
  let factor = decimal_scale_power(exponent.abs())
  let numerator = if exponent >= 0 { magnitude * factor } else { magnitude }
  let denominator = if exponent < 0 { divisor * factor } else { divisor }
  guard exact_decimal_round_ratio(numerator, denominator, negative, mode)
    is Some(rounded) else {
    return Err(ArithmeticFailure)
  }
  // Refuse overflow before formatting a potentially 114-digit quotient.
  if rounded >= decimal_scale_power(precision) {
    return Err(ArithmeticFailure)
  }
  let digits = rounded.to_string()
  let coefficient = if negative && digits != "0" {
    "-" + digits
  } else {
    digits
  }
  match @admitted.decimal_from_coefficient(coefficient, precision, scale) {
    Some(value) => Ok(capture(value))
    None => Err(ArithmeticFailure)
  }
}
