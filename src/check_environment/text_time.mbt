///|
pub(all) enum TextTimeIssue {
  InvalidLimits
  MissingTextTime
  InvalidComponent
  BudgetExceeded
  Policy(@text_policy.Issue)
} derive(Eq, Debug)

///|
struct TextTime {
  environment : WireEnvironment
  policy : @text_policy.Policy
  bytes : Int
  nodes : Int
}

///|
/// Admit this component only; absence is unresolved, never a default policy.
pub fn read_text_time(
  environment : WireEnvironment,
  limits : @text_policy.Limits,
) -> Result[TextTime, TextTimeIssue] {
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let object = @decode.open_object(environment.policy).unwrap()
  let body = match @decode.lookup(object, "text_time_evaluation") {
    Some(v) => v
    None => return Err(MissingTextTime)
  }
  if @decode.object_length(body) is None {
    return Err(InvalidComponent)
  }
  try {
    // Serialize only the bounded component for the existing canonical reader.
    let writer = @encode.writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_cursor(body, writer, false)
    let bytes = @utf8.encode(@encode.finish(writer))
    let expected = "sha256:" + @sha.hex(bytes)
    match @text_policy.admit(bytes, expected, limits) {
      // Valid text_time bodies contain only scalar fields under one object.
      Ok(policy) =>
        Ok({
          environment,
          policy,
          bytes: bytes.length(),
          nodes: 1 + @decode.object_length(body).unwrap(),
        })
      Err(@text_policy.BudgetExceeded) => Err(BudgetExceeded)
      Err(e) => Err(Policy(e))
    }
  } catch {
    _ => Err(BudgetExceeded)
  }
}

///|
pub fn text_time_environment(value : TextTime) -> WireEnvironment {
  value.environment
}

///|
pub fn text_time_policy(value : TextTime) -> @text_policy.Policy {
  value.policy
}

///|
/// Canonical component bytes and nodes, not retained heap size.
pub fn text_time_usage(value : TextTime) -> (Int, Int) {
  (value.bytes, value.nodes)
}
