///|
// This shares the existing decimal coefficient/scale owner and bounded scratch.
// No observed Number is promoted to an exact integer domain.
fn exact_integer_decimal_operand(value : Value) -> @admitted.DecimalValue? {
  match value {
    Captured(@admitted.Decimal(d)) => Some(d)
    Captured(@admitted.Signed64(n)) =>
      match @admitted.decimal_from_coefficient(n.to_string(), 19, 0) {
        Some(@admitted.Decimal(d)) => Some(d)
        _ => None
      }
    _ => None
  }
}

///|
fn exact_decimal_integer_expression_value(
  expression : @lower.Expression,
  operation : @lower.BinaryOperator,
  left : Value,
  right : Value,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Value, EvalIssue] {
  if left is Null || right is Null {
    return Ok(Null)
  }
  // At most two original 38-digit coefficients aligned by at most 38 decimal
  // places: magnitudes below 10^76. Reuse the existing decimal division
  // envelope, which already covers ratios with up to 114-digit numerators.
  if !spend_control(control, 8 * 115 + 128) {
    return Err({ kind: ControlLimit, expression, })
  }
  if !reserve_slots(workspace, DECIMAL_DIVISION_SLOTS) {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  let result = exact_decimal_integer_value(expression, operation, left, right)
  release_slots(workspace, DECIMAL_DIVISION_SLOTS)
  result.map_err(issue => { kind: Scalar(issue), expression, })
}

///|
fn exact_decimal_integer_value(
  expression : @lower.Expression,
  operation : @lower.BinaryOperator,
  left : Value,
  right : Value,
) -> Result[Value, ScalarIssue] {
  guard @lower.expression_contract(expression).shape
    is @contract.Decimal(precision~, scale~) &&
    exact_integer_decimal_operand(left) is Some(a) &&
    exact_integer_decimal_operand(right) is Some(b) else {
    return Err(InvalidOperand)
  }
  let aligned_scale = Int::max(a.scale, b.scale)
  let numerator = decimal_coefficient_magnitude(a) *
    decimal_scale_power(aligned_scale - a.scale)
  let denominator = decimal_coefficient_magnitude(b) *
    decimal_scale_power(aligned_scale - b.scale)
  if denominator.is_zero() {
    return Err(ArithmeticFailure)
  }
  let (magnitude, negative) = match operation {
    IntegerDivide =>
      (
        numerator / denominator,
        (a.coefficient[0] == '-') != (b.coefficient[0] == '-'),
      )
    ExactModulo => (numerator % denominator, a.coefficient[0] == '-')
    _ => return Err(InvalidOperand)
  }
  if scale !=
    (if operation == @lower.IntegerDivide { 0 } else { aligned_scale }) {
    return Err(InvalidOperand)
  }
  if magnitude >= decimal_scale_power(precision) {
    return Err(ArithmeticFailure)
  }
  let digits = magnitude.to_string()
  let coefficient = if negative && !magnitude.is_zero() {
    "-" + digits
  } else {
    digits
  }
  match @admitted.decimal_from_coefficient(coefficient, precision, scale) {
    Some(value) => Ok(capture(value))
    None => Err(ArithmeticFailure)
  }
}
