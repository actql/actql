///|
/// Original compiler metadata retained with first admission. This projection is
/// not a permission, execution observation or a restored physical compilation.
struct ClientRunObservationOriginals {
  prepared : @publication.RunEvidenceValue
  authorization : @publication.RunEvidenceValue
}

///|
pub(all) enum ClientRunObservationOriginalsIssue {
  Compilation(ClientCompiledRunIssue)
  Evidence(@publication.RunEvidenceValueIssue)
  Binding(@publication.RunControlReadIssue)
  Encoding
}

///|
/// Capture exactly the existing compiled Owner's originals, without compiling
/// again. The Native Host saves these with its original acceptance transaction.
pub fn capture_client_run_observation_originals(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[ClientRunObservationOriginals, ClientRunObservationOriginalsIssue] {
  match check_client_compiled_run_definition(compiled, definition) {
    Ok(_) => ()
    Err(issue) => return Err(Compilation(issue))
  }
  checked_client_run_observation_originals(
    definition,
    compiled.prepared,
    compiled.authorization,
  )
}

///|
/// Retain the SAME Effect compiler evidence at first admission. This projection
/// neither creates an Effect-free compilation nor reissues authorization.
pub fn capture_client_effect_run_observation_originals(
  owner : PreparedClientEffectComputation,
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
) -> Result[ClientRunObservationOriginals, ClientRunObservationOriginalsIssue] {
  match bind_client_effect_compiled_run(owner, allowed, definition) {
    Ok(_) => ()
    Err(issue) => return Err(Compilation(EffectBinding(issue)))
  }
  checked_client_run_observation_originals(
    definition,
    allowed.prepared,
    allowed.authorization,
  )
}

///|
fn checked_client_run_observation_originals(
  definition : @publication.PublicationContract,
  prepared : @publication.RunEvidenceValue,
  authorization : @publication.RunEvidenceValue,
) -> Result[ClientRunObservationOriginals, ClientRunObservationOriginalsIssue] {
  match
    @publication.validate_original_interactive_run_evidence(
      definition, prepared, authorization,
    ) {
    Ok(_) => Ok({ prepared, authorization, })
    Err(issue) => Err(Binding(issue))
  }
}

///|
/// Read the exact saved metadata after the Host authenticates its same original
/// request/Run row. A copied Allow remains metadata, never current authority.
/// Missing originals must remain unavailable; callers cannot recapture them.
pub fn restore_client_run_observation_originals(
  definition : @publication.PublicationContract,
  prepared_wire : String,
  authorization_wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientRunObservationOriginals, ClientRunObservationOriginalsIssue] {
  let prepared = match
    @publication.admit_run_evidence_value(
      "prepared_invocation", prepared_wire, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let authorization = match
    @publication.admit_run_evidence_value(
      "run_authorization", authorization_wire, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  checked_client_run_observation_originals(definition, prepared, authorization)
}

///|
/// Borrow exact original values for the existing read-only Run projection.
pub fn ClientRunObservationOriginals::prepared(
  self : ClientRunObservationOriginals,
) -> @publication.RunEvidenceValue {
  self.prepared
}

///|
pub fn ClientRunObservationOriginals::authorization(
  self : ClientRunObservationOriginals,
) -> @publication.RunEvidenceValue {
  self.authorization
}

///|
/// Retain the exact first-admission evidence in the existing Run row. This
/// bounded envelope is metadata, never current permission or physical state.
pub fn ClientRunObservationOriginals::wire(
  self : ClientRunObservationOriginals,
) -> Result[String, ClientRunObservationOriginalsIssue] {
  try {
    let writer = @encode.writer(131072, 8, 1)
    @encode.begin_object(writer)
    @encode.key(writer, "authorization")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_json(self.authorization),
    )
    @encode.key(writer, "prepared")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_json(self.prepared),
    )
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// Read the selected SDK's saved envelope, validating the original evidence
/// against its retained definition. This does not compile or authorize work.
pub fn restore_client_run_observation_originals_wire(
  definition : @publication.PublicationContract,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientRunObservationOriginals, ClientRunObservationOriginalsIssue] {
  if max_bytes < 1 ||
    max_bytes > 131072 ||
    wire.length() > max_bytes ||
    max_nodes < 1 ||
    max_depth < 1 {
    return Err(Encoding)
  }
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: max_bytes,
      max_nodes: 8,
      max_depth: 2,
    }) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  guard @decode.admit(source, {
      max_nodes: 8,
      max_depth: 2,
      max_string_bytes: max_bytes,
      max_total_string_bytes: max_bytes,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, ["authorization", "prepared"]) is Ok(object) &&
    @decode.lookup(object, "prepared").bind(value => {
      @decode.text(value).to_option()
    })
    is Some(prepared) &&
    @decode.lookup(object, "authorization").bind(value => {
      @decode.text(value).to_option()
    })
    is Some(authorization) else {
    return Err(Encoding)
  }
  let original = match
    restore_client_run_observation_originals(
      definition, prepared, authorization, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match original.wire() {
    Ok(canonical) if canonical == wire => Ok(original)
    _ => Err(Encoding)
  }
}
