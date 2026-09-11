///|
pub(all) enum CapacityIssue {
  InvalidLimits
  MissingCapacity
  InvalidComponent
  BudgetExceeded
  Policy(@policy.Issue)
} derive(Eq, Debug)

///|
struct Capacity {
  environment : WireEnvironment
  policy : @policy.Policy
  bytes : Int
  nodes : Int
}

///|
/// Admit this component only; absence is unresolved, never a default policy.
pub fn read_capacity(
  environment : WireEnvironment,
  limits : @policy.Limits,
) -> Result[Capacity, CapacityIssue] {
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let object = @decode.open_object(environment.policy).unwrap()
  let body = match @decode.lookup(object, "capacity") {
    Some(v) => v
    None => return Err(MissingCapacity)
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
    match @policy.admit(bytes, expected, limits) {
      // Valid capacity bodies contain only scalar fields under one object.
      Ok(policy) =>
        Ok({
          environment,
          policy,
          bytes: bytes.length(),
          nodes: 1 + @decode.object_length(body).unwrap(),
        })
      Err(@policy.BudgetExceeded) => Err(BudgetExceeded)
      Err(e) => Err(Policy(e))
    }
  } catch {
    _ => Err(BudgetExceeded)
  }
}

///|
pub fn capacity_environment(value : Capacity) -> WireEnvironment {
  value.environment
}

///|
pub fn capacity_policy(value : Capacity) -> @policy.Policy {
  value.policy
}

///|
/// Canonical component bytes and nodes, not retained heap size.
pub fn capacity_usage(value : Capacity) -> (Int, Int) {
  (value.bytes, value.nodes)
}
