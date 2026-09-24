///|
pub(all) enum ClientPublicationLimitSetIssue {
  InvalidLimit
  BudgetExceeded
  CheckedLimit(ClientPublicationLimitIssue)
  DuplicateCheckedLimit
  UnexpectedLimit
  DuplicateLimit
  MissingLimit
} derive(Eq, Debug)

///|
/// Check every Result publication limit against its canonical checked body.
/// A saved Plan limit is an identity artifact, so reserialized or altered
/// bytes do not replace the body's canonical encoding and self CID.
pub fn admit_prepared_client_publication_limit_set(
  value : PreparedClientProgram,
  bodies : Array[String],
  max_limits : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientPublicationLimitSetIssue] {
  if max_limits <= 0 || max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimit)
  }
  if bodies.length() > max_limits {
    return Err(BudgetExceeded)
  }
  let program = @strategy.graph_program(value.graph)
  let expected : Array[String] = []
  for unit in 0..<@checked.unit_count(program) {
    guard @checked.unit_publication_count(program, unit) is Some(count) else {
      return Err(CheckedLimit(MissingPublication))
    }
    for index in 0..<count {
      for scope in [Rows, Bytes] {
        if expected.length() >= max_limits {
          return Err(BudgetExceeded)
        }
        let body = match
          emit_prepared_client_publication_limit(
            value, unit, index, scope, max_wire_bytes, max_nodes, max_depth,
          ) {
          Ok(body) => body
          Err(issue) => return Err(CheckedLimit(issue))
        }
        if expected.contains(body) {
          return Err(DuplicateCheckedLimit)
        }
        expected.push(body)
      }
    }
  }
  let seen : Array[String] = []
  for body in bodies {
    if !expected.contains(body) {
      return Err(UnexpectedLimit)
    }
    if seen.contains(body) {
      return Err(DuplicateLimit)
    }
    seen.push(body)
  }
  if seen.length() != expected.length() {
    return Err(MissingLimit)
  }
  Ok(())
}

///|
pub(all) enum ClientPublicationPlanFactIssue {
  Limits(ClientPublicationLimitSetIssue)
  Bindings(ClientPublicationBindingSetIssue)
} derive(Eq, Debug)

///|
/// Admit the complete checked Result-publication portion of private Plan
/// facts. This does not admit unrelated executable limits or the Plan itself.
pub fn admit_prepared_client_publication_plan_facts(
  value : PreparedClientProgram,
  limits : Array[String],
  bindings : Array[String],
  max_facts : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientPublicationPlanFactIssue] {
  match
    admit_prepared_client_publication_limit_set(
      value, limits, max_facts, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Limits(issue))
  }
  admit_prepared_client_publication_binding_set(
    value, bindings, max_facts, max_wire_bytes, max_nodes, max_depth,
  ).map_err(issue => Bindings(issue))
}
