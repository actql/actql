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
  checked_client_publication_policy_bodies(
    program,
    cid,
    max_bytes,
    max_nodes,
    max_depth,
    retain_catalog=true,
  )
}

///|
/// Original checked Effect-free Result policy bodies, including their exact
/// Catalog references. This does not acquire data, reprepare a restored Run,
/// authorize read/egress or replace unknown provenance with public.
pub fn prepared_client_publication_policy_bodies(
  value : PreparedClientProgram,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[(String, String, String)], @checked.LocalDependencyBodyIssue] {
  guard prepared_client_publication_data_policy_cid(value) is Some(cid) else {
    return Err(MissingDependency)
  }
  checked_client_publication_policy_bodies(
    @strategy.graph_program(value.graph),
    cid,
    max_bytes,
    max_nodes,
    max_depth,
    retain_catalog=true,
  )
}

///|
fn checked_client_publication_policy_bodies(
  program : @checked.CheckedProgram,
  cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  retain_catalog? : Bool = false,
) -> Result[Array[(String, String, String)], @checked.LocalDependencyBodyIssue] {
  let remaining = Int::min(max_bytes, 16777216)
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
  checked_client_source_policy_bodies(
    program,
    policy,
    remaining,
    max_nodes,
    max_depth,
    work,
    retain_catalog~,
  )
}

///|
/// Preserve the exact selected policy and its response-policy originals for
/// both Result publication and an intermediate Content barrier. This neither
/// selects the final Result's policy for bytes nor grants external I/O.
fn checked_client_source_policy_bodies(
  program : @checked.CheckedProgram,
  policy : @checked.PublicationSourcePolicy,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  work : Int,
  retain_catalog? : Bool = false,
) -> Result[Array[(String, String, String)], @checked.LocalDependencyBodyIssue] {
  let mut remaining_work = work
  let cid = policy.cid
  let mut remaining = Int::min(max_bytes, 16777216)
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
  if sources > remaining_work {
    return Err(BudgetExceeded)
  }
  if retain_catalog {
    remaining_work -= sources
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
    if retain_catalog {
      // The existing policy codec distinguishes whole-body checked identities
      // from self-excluding Catalog identities. Never rehash a Catalog body as
      // a checked policy or resolve these references from current Host input.
      let source_policy = @environment.source_view_data_policy(
        source.response_policy.authoritative,
      )
      let references = [
        (
          "data_policy",
          @environment.contract_identity(
            @environment.data_policy_envelope(source_policy),
          ).2,
        ),
        (
          "source_view_contract",
          @acquisition.selected_cid(source.response_policy.source),
        ),
      ]
      if references.length() > remaining_work {
        return Err(BudgetExceeded)
      }
      remaining_work -= references.length()
      for (kind, identity) in references {
        if seen.contains(identity) {
          guard bodies.iter().find_first(body => body.1 == identity)
            is Some(body) &&
            body.0 == kind else {
            return Err(ForeignBody)
          }
          continue
        }
        let original = match
          @checked.checked_local_catalog_dependency_body(
            program,
            source.stage,
            kind,
            identity,
            remaining,
            max_nodes,
            max_depth,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        let body = @checked.checked_local_dependency_body_json(original)
        match
          @publication.admit_captured_effect_dependency_body(
            kind,
            Some(identity),
            body,
            remaining,
            max_nodes,
            max_depth,
          ) {
          Ok(_) => ()
          Err(_) => return Err(ForeignBody)
        }
        remaining -= @utf8.encode(body).length()
        bodies.push((kind, identity, body))
        seen[identity] = true
      }
    }
  }
  if retain_catalog {
    let admitted : Array[@publication.CapturedEffectDependencyBody] = []
    for (kind, identity, wire) in bodies {
      match
        @publication.admit_captured_effect_dependency_body(
          kind,
          Some(identity),
          wire,
          max_bytes,
          max_nodes,
          max_depth,
        ) {
        Ok(body) => admitted.push(body)
        Err(_) => return Err(ForeignBody)
      }
    }
    match
      @publication.validate_captured_effect_dependency_bodies(
        admitted,
        [admitted[0]],
        0,
        {
          max_entries: Int::min(max_nodes, 4096),
          max_total_bytes: Int::min(max_bytes, 16777216),
          // The dependency graph keeps its own existing depth ceiling.
          max_depth: Int::min(max_depth, 64),
          max_references: Int::min(max_nodes, 4096),
        },
      ) {
      Ok(_) => ()
      Err(@publication.MissingDependency) => return Err(MissingDependency)
      Err(
        @publication.InvalidLimits
        | @publication.EntryLimit
        | @publication.ByteLimit
        | @publication.ReferenceLimit
        | @publication.DepthLimit
      ) => return Err(BudgetExceeded)
      Err(_) => return Err(ForeignBody)
    }
  }
  Ok(bodies)
}

///|
/// Source-free outputs require the installed Host's admitted original. Source
/// outputs keep their exact checked closure. Missing originals are refused,
/// never synthesized from a CID or copied from unrelated installations.
pub fn client_compiled_run_publication_policy_bodies(
  value : ClientCompiledRun,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[(String, String, String)], @checked.LocalDependencyBodyIssue] {
  if value.compilation is Effects(_) {
    return Err(ForeignBody)
  }
  if prepared_client_acquisition_count(value.owner) != 0 {
    return prepared_client_publication_policy_bodies(
      value.owner,
      max_bytes,
      max_nodes,
      max_depth,
    )
  }
  guard value.source_free_result_policy is Some(body) else {
    return Err(MissingDependency)
  }
  let cid = @publication.captured_effect_dependency_body_cid(body)
  let wire = @publication.captured_effect_dependency_body_json(body)
  match
    admit_source_free_result_policy_body(
      cid, wire, max_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => Ok([("data_policy", cid, wire)])
    Err(_) => Err(BudgetExceeded)
  }
}
