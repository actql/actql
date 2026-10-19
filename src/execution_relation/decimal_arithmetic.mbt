///|
// Structural integer/parser/formatter entries only, not physical byte funding.
const DECIMAL_ARITHMETIC_SLOTS : Int = 64

///|
fn decimal_arithmetic_expression_value(
  expression : @lower.Expression,
  operation : @lower.BinaryOperator,
  left : Value,
  right : Value,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Value, EvalIssue] {
  guard @lower.expression_contract(expression).shape
    is @contract.Decimal(precision~, scale~) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  // Both original children have already been demanded and charged by the frame.
  if left is Null || right is Null {
    return Ok(Null)
  }
  guard left is Captured(@admitted.Decimal(a)) &&
    right is Captured(@admitted.Decimal(b)) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  // Each admitted coefficient has at most 38 digits. Scale alignment is at
  // most 38 places: each aligned magnitude is below 10^76, a sum below
  // 2*10^76, and a product below 10^76. Refuse overflow before formatting.
  if !spend_control(control, 8 * 77 + 128) {
    return Err({ kind: ControlLimit, expression, })
  }
  if !reserve_slots(workspace, DECIMAL_ARITHMETIC_SLOTS) {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  let result = decimal_arithmetic_value(operation, a, b, precision, scale)
  release_slots(workspace, DECIMAL_ARITHMETIC_SLOTS)
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err({ kind: Scalar(issue), expression, })
  }
}

///|
fn decimal_arithmetic_value(
  operation : @lower.BinaryOperator,
  left : @admitted.DecimalValue,
  right : @admitted.DecimalValue,
  precision : Int,
  scale : Int,
) -> Result[Value, ScalarIssue] {
  let zero = @bigint.BigInt::from_int(0)
  let a = decimal_coefficient_magnitude(left)
  let b = decimal_coefficient_magnitude(right)
  let signed_a = if left.coefficient[0] == '-' { zero - a } else { a }
  let signed_b = if right.coefficient[0] == '-' { zero - b } else { b }
  let coefficient = match operation {
    Add | Subtract => {
      if scale != Int::max(left.scale, right.scale) {
        return Err(InvalidOperand)
      }
      let aligned_a = signed_a * decimal_scale_power(scale - left.scale)
      let aligned_b = signed_b * decimal_scale_power(scale - right.scale)
      if operation == @lower.Add {
        aligned_a + aligned_b
      } else {
        aligned_a - aligned_b
      }
    }
    Multiply => {
      if scale != left.scale + right.scale {
        return Err(InvalidOperand)
      }
      signed_a * signed_b
    }
    _ => return Err(InvalidOperand)
  }
  let magnitude = if coefficient < zero {
    zero - coefficient
  } else {
    coefficient
  }
  if magnitude >= decimal_scale_power(precision) {
    return Err(ArithmeticFailure)
  }
  match
    @admitted.decimal_from_coefficient(
      coefficient.to_string(),
      precision,
      scale,
    ) {
    Some(value) => Ok(capture(value))
    None => Err(ArithmeticFailure)
  }
}
