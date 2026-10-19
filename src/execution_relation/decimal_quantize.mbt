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
  let ten = @bigint.BigInt::from_int(10)
  let one = @bigint.BigInt::from_int(1)
  let zero = @bigint.BigInt::from_int(0)
  let mut magnitude = zero
  // Original admitted coefficients have at most 38 digits, not binary64 text.
  for i = start; i < value.coefficient.length(); i = i + 1 {
    magnitude = magnitude * ten +
      @bigint.BigInt::from_int(value.coefficient[i].to_int() - 48)
  }
  let mut factor = one
  for _i = 0; _i < difference.abs(); _i = _i + 1 {
    factor = factor * ten
  }
  let rounded = if difference >= 0 {
    magnitude * factor
  } else {
    let quotient = magnitude / factor
    let remainder = magnitude % factor
    let twice = remainder * @bigint.BigInt::from_int(2)
    let increment = match mode {
      "half_even" =>
        twice > factor ||
        (twice == factor && quotient % @bigint.BigInt::from_int(2) == one)
      "half_up" => twice >= factor
      "toward_zero" => false
      "floor" => negative && remainder != zero
      "ceiling" => !negative && remainder != zero
      _ => return None
    }
    if increment {
      quotient + one
    } else {
      quotient
    }
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
