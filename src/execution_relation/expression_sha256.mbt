///|
// Borrow one input root. The fixed Hasher state/schedule/block, final digest,
// Base64 encoding and transient allocation controls all fit in this original
// RowWorkspace allowance. No input-sized copy or hash expansion is built.
const SHA256_WORKSPACE_SLOTS : Int = 272

///|
priv struct Sha256Expression {
  expression : @lower.Expression
  input : Value
  hasher : @sha.Hasher
  mut position : Int
}

///|
fn start_sha256_expression(
  expression : @lower.Expression,
  input : Value,
  workspace : RowWorkspace,
) -> Result[Sha256Expression, EvalIssue] {
  guard input is Text(_) || input is Captured(@admitted.Binary(_)) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  if !reserve_slots(workspace, SHA256_WORKSPACE_SLOTS) {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  Ok({ expression, input, hasher: @sha.hasher(), position: 0, })
}

///|
// The expression driver checks current work before every advance. Each
// advance reads one original octet or a single admitted UTF-8 scalar.
fn advance_sha256_expression(
  state : Sha256Expression,
) -> Result[Value?, EvalIssue] {
  let invalid = { kind: Scalar(InvalidOperand), expression: state.expression, }
  try {
    match state.input {
      Text(text) if state.position < text.length() => {
        guard text_function_scalar(text, state.position)
          is Some((scalar, next, _, _)) else {
          return Err(invalid)
        }
        @sha.update_utf8_scalar(state.hasher, scalar)
        state.position = next
        return Ok(None)
      }
      Captured(@admitted.Binary(bytes)) if @admitted.bytes_at(
          bytes,
          state.position,
        )
        is Some(byte) => {
        @sha.update_byte(state.hasher, byte)
        state.position += 1
        return Ok(None)
      }
      _ => ()
    }
    let digest = @sha.finish_digest(state.hasher)
    guard @admitted.bytes_value(digest, 44) is Some(value) else {
      return Err(invalid)
    }
    Ok(Some(capture(value)))
  } catch {
    _ => Err(invalid)
  }
}
