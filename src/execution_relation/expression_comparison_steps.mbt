///|
/// Resume the existing scalar comparison. Its caller owns operand roots and
/// cursor reservations; suspending neither consumes operands again nor adds
/// semantic work. Operand byte charges cover the subsequent UTF-16 scan.
fn advance_binary_comparison(
  state : BinaryComparisonState,
  budget : ControlBudget,
) -> Result[Value?, EvalIssue] {
  if state.phase < 2 {
    let operand = if state.phase == 0 { state.left } else { state.right }
    match bounded_comparison_charge_text(operand) {
      Err(Scalar(issue)) =>
        return Err({ kind: Scalar(issue), expression: state.expression, })
      Err(_) =>
        return Err({ kind: ControlLimit, expression: state.expression, })
      Ok(Some(text)) =>
        match advance_bounded_text_charge(state.charge, budget, text) {
          Err(_) =>
            return Err({ kind: ControlLimit, expression: state.expression, })
          Ok(false) => return Ok(None)
          Ok(true) => ()
        }
      Ok(None) =>
        match charge_comparison_operand(budget, operand) {
          Err(ComparisonChargeLimit) =>
            return Err({ kind: ControlLimit, expression: state.expression, })
          Err(ComparisonChargeInvalidOperand) =>
            return Err({
              kind: Scalar(InvalidOperand),
              expression: state.expression,
            })
          Ok(_) => ()
        }
    }
    state.phase += 1
    reset_bounded_text_charge(state.charge)
    return Ok(None)
  }
  let comparison_operator = match state.op {
    Add | Subtract | Multiply | Divide | Modulo | In | NotIn => false
    _ => true
  }
  let result = if comparison_operator &&
    state.left is Text(left) &&
    state.right is Text(right) {
    let (compared, offset) = bounded_utf16_comparison_step(
      left,
      right,
      state.offset,
    )
    state.offset = offset
    guard compared is Some(compared) else { return Ok(None) }
    binary_comparison_result(state.op, state.left, compared)
  } else {
    binary(state.op, state.left, state.right)
  }
  match result {
    Ok(value) => Ok(Some(value))
    Err(issue) => Err({ kind: Scalar(issue), expression: state.expression, })
  }
}
