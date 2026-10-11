///|
// Finite originals remain inside the existing Run row and its unchanged
// physical record budget. This is custody, never read or egress authority.
fn run_policy_originals_wire(
  prepared : @host.PreparedClientProgram,
) -> Result[String, NativeClientRunJournalIssue] {
  let bodies = match
    @host.prepared_client_publication_policy_bodies(prepared, 65536, 8192, 64) {
    Ok(value) => value
    Err(issue) => return Err(PublicationPolicy(issue))
  }
  guard bodies.length() > 0 && bodies.length() <= 64 else {
    return Err(CapacityExceeded)
  }
  try {
    let writer = @encode.writer(65536, 512, 8)
    @encode.begin_object(writer)
    @encode.key(writer, "bodies")
    @encode.begin_array(writer)
    for (kind, cid, body) in bodies {
      @encode.begin_object(writer)
      @encode.key(writer, "body")
      @encode.string_value(writer, body)
      @encode.key(writer, "cid")
      @encode.string_value(writer, cid)
      @encode.key(writer, "kind")
      @encode.string_value(writer, kind)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "root_policy_cid")
    @encode.string_value(writer, bodies[0].1)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
fn read_run_policy_originals(
  wire : String,
) -> Result[
  Array[@publication.CapturedEffectDependencyBody],
  NativeClientRunJournalIssue,
] {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 65536,
      max_nodes: 512,
      max_depth: 8,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 512,
      max_depth: 8,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  guard @decode.closed_object(cursor, ["bodies", "root_policy_cid"]) is Ok(root) &&
    epoch_text(root, "root_policy_cid") is Some(root_cid) &&
    @decode.lookup(root, "bodies") is Some(list) &&
    @decode.elements(list) is Ok(elements) &&
    elements.length() > 0 &&
    elements.length() <= 64 else {
    return Err(CustodyLost)
  }
  let bodies : Array[@publication.CapturedEffectDependencyBody] = []
  for element in elements {
    guard @decode.closed_object(element, ["body", "cid", "kind"]) is Ok(fields) &&
      epoch_text(fields, "body") is Some(body) &&
      epoch_text(fields, "cid") is Some(cid) &&
      epoch_text(fields, "kind") is Some(kind) &&
      (kind == "data_policy" || kind == "source_view_contract") else {
      return Err(CustodyLost)
    }
    match
      @publication.admit_captured_effect_dependency_body(
        kind,
        Some(cid),
        body,
        65536,
        8192,
        64,
      ) {
      Ok(value) => bodies.push(value)
      Err(_) => return Err(CustodyLost)
    }
  }
  if @publication.captured_effect_dependency_body_kind(bodies[0]) !=
    "data_policy" ||
    @publication.captured_effect_dependency_body_cid(bodies[0]) != root_cid {
    return Err(CustodyLost)
  }
  match
    @publication.validate_captured_effect_dependency_bodies(
      bodies,
      [bodies[0]],
      0,
      {
        max_entries: 64,
        max_total_bytes: 65536,
        max_depth: 64,
        max_references: 512,
      },
    ) {
    Ok(_) => Ok(bodies)
    Err(_) => Err(CustodyLost)
  }
}

///|
/// Keep exact checked originals only before dispatch/start. The existing Run
/// transaction, current authority and checked binding decide the mutation.
/// A restored Run with missing originals is never re-prepared to repair them.
fn NativeClientRunJournal::retain_publication_policy_originals(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  authority : NativeLocalPolicyAuthority,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  if !authority.current_for(self, request) {
    return Err(AuthorizationDenied)
  }
  match
    validate_native_client_run_binding(request, prepared, compiled, definition) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let wire = match run_policy_originals_wire(prepared) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.transaction(() => {
    if !authority.current_for(self, request) {
      return Err(AuthorizationDenied)
    }
    let record = match self.retained(request) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    if @publication.publication_contract_identity(record.definition) !=
      @publication.publication_contract_identity(definition) {
      return Err(ForeignRun)
    }
    if record.publication_policy_originals is Some(original) {
      if original != wire {
        return Err(CustodyLost)
      }
      if !authority.current_for(self, request) {
        return Err(AuthorizationDenied)
      }
      return Ok(record)
    }
    if record.dispatch_reserved ||
      record.physical_start_claimed ||
      record.cancellation_requested {
      return Err(Fenced)
    }
    // Recheck after preparation/transaction reads, immediately before CAS.
    if !authority.current_for(self, request) {
      return Err(AuthorizationDenied)
    }
    self.save({ ..record, publication_policy_originals: Some(wire), })
  })
}

///|
/// Resolve only a retained original under current read authority. The caller
/// obtains actual_policy_cid from the committed Result Artifact, not from
/// current Source configuration. This method never creates a grant or payload.
fn NativeClientRunJournal::lookup_publication_policy_original(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  actual_policy_cid : String,
  authority : NativeLocalPolicyAuthority,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  NativeClientRunJournalIssue,
] {
  if !authority.current_for(self, request) {
    return Err(AuthorizationDenied)
  }
  self.transaction(() => {
    if !authority.current_for(self, request) {
      return Err(AuthorizationDenied)
    }
    let record = match self.retained(request) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    guard record.publication_policy_originals is Some(wire) else {
      return Err(PublicationPolicy(@checked.MissingDependency))
    }
    let bodies = match read_run_policy_originals(wire) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard bodies
      .iter()
      .find_first(body => {
        @publication.captured_effect_dependency_body_kind(body) == "data_policy" &&
        @publication.captured_effect_dependency_body_cid(body) ==
        actual_policy_cid
      })
      is Some(body) else {
      return Err(PublicationPolicy(@checked.MissingDependency))
    }
    if !authority.current_for(self, request) {
      return Err(AuthorizationDenied)
    }
    Ok(body)
  })
}
