///|
// Structural scratch entries only: bounded integer records, parse/power state,
// quotient/remainder, rounded coefficient and formatter result. These entries
// are neither a physical byte reservation nor a cleanup acknowledgement.
const DECIMAL_QUANTIZE_SLOTS : Int = 32

///|
fn quantize_coefficient(
  value : @admitted.DecimalValue,
  precision : Int,
  scale : Int,
  mode : String,
) -> String? {
  let negative = value.coefficient[0] == '-'
  let start = if negative { 1 } else { 0 }
  let digits = value.coefficient.length() - start
  let difference = scale - value.scale
  if difference >= 0 &&
    value.coefficient != "0" &&
    digits + difference > precision {
    return None
  }
  let magnitude = decimal_coefficient_magnitude(value)
  let factor = decimal_scale_power(difference.abs())
  let rounded = if difference >= 0 {
    magnitude * factor
  } else {
    guard exact_decimal_round_ratio(magnitude, factor, negative, mode)
      is Some(value) else {
      return None
    }
    value
  }
  let coefficient = rounded.to_string()
  if coefficient.length() > precision {
    return None
  }
  Some(
    if negative && coefficient != "0" {
      "-" + coefficient
    } else {
      coefficient
    },
  )
}

///|
fn quantize_expression_value(
  expression : @lower.Expression,
  value : Value,
  mode : String,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Value, EvalIssue] {
  guard @lower.expression_contract(expression).shape
    is @contract.Decimal(precision~, scale~) &&
    ["half_even", "half_up", "toward_zero", "floor", "ceiling"].contains(mode) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  if value is Null {
    return Ok(Null)
  }
  guard value is Captured(@admitted.Decimal(decimal)) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  // Parse, power, quotient/remainder, rounding and formatting are bounded by
  // 38 admitted digits/scales. Upscaling overflow is checked before multiplying;
  // every successful intermediate is at most 10^38 (twice remainder <2e38).
  // Preflight the fixed-width integer operations and representation passes.
  if !spend_control(control, 8 * 39 + 64) {
    return Err({ kind: ControlLimit, expression, })
  }
  if !reserve_slots(workspace, DECIMAL_QUANTIZE_SLOTS) {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  let converted = match quantize_coefficient(decimal, precision, scale, mode) {
    Some(coefficient) =>
      @admitted.decimal_from_coefficient(coefficient, precision, scale)
    None => None
  }
  release_slots(workspace, DECIMAL_QUANTIZE_SLOTS)
  match converted {
    Some(value) => Ok(capture(value))
    None => Err({ kind: Scalar(ArithmeticFailure), expression, })
  }
}
