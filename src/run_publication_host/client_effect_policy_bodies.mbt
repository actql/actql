///|
/// Exact checked policy closure for the combined Result publication. Body
/// custody does not replace current Source or Effect authorization.
pub fn prepared_client_effect_publication_policy_bodies(
  value : PreparedClientEffectComputation,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[(String, String, String)], @checked.LocalDependencyBodyIssue] {
  guard prepared_client_effect_publication_data_policy_cid(value) is Some(cid) else {
    return Err(MissingDependency)
  }
  let program = @checked.effect_program_static_checked_computation(
    prepared_client_effect_computation_candidate(value),
  )
  let mut remaining = Int::min(max_bytes, 16777216)
  let mut work = Int::min(max_nodes, 4096)
  let count = @checked.unit_count(program)
  if count > work {
    return Err(BudgetExceeded)
  }
  work -= count
  let mut selected : @checked.PublicationSourcePolicy? = None
  for unit in 0..<count {
    let publications = @checked.unit_publication_count(program, unit).unwrap_or(
      0,
    )
    if publications > work {
      return Err(BudgetExceeded)
    }
    work -= publications
    for index in 0..<publications {
      let publication = @checked.unit_publication_at(program, unit, index).unwrap()
      if @checked.publication_source_policy(publication) is Some(policy) &&
        policy.cid == cid {
        selected = Some(policy)
      }
    }
  }
  guard selected is Some(policy) else { return Err(MissingDependency) }
  let bodies : Array[(String, String, String)] = []
  let seen : Map[String, Bool] = Map([])
  fn retain(
    identity : String,
    emit : (@encode.Writer) -> Unit raise @encode.EncodeFailure,
  ) -> Result[Unit, @checked.LocalDependencyBodyIssue] {
    if seen.contains(identity) {
      return Ok(())
    }
    let writer = @encode.writer(remaining, max_nodes, max_depth) catch {
      _ => return Err(BudgetExceeded)
    }
    emit(writer) catch {
      _ => return Err(Encoding)
    }
    let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
    let bytes = @utf8.encode(wire)
    if "sha256:" + @sha.hex(bytes) != identity {
      return Err(ForeignBody)
    }
    remaining -= bytes.length()
    bodies.push(("data_policy", identity, wire))
    seen[identity] = true
    Ok(())
  }
  match
    retain(cid, writer => {
      @checked.emit_publication_source_policy(policy, writer)
    }) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let sources = @checked.publication_policy_source_count(policy)
  if sources > work {
    return Err(BudgetExceeded)
  }
  for index in 0..<sources {
    let source = @checked.source_execution_subject(
      @checked.publication_policy_source_at(policy, index).unwrap(),
    )
    match
      retain(source.response_policy_cid, writer => {
        @checked.emit_source_response_policy(source.response_policy, writer)
      }) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  Ok(bodies)
}
