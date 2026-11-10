///|
/// Pure custody codec shared by Local Hosts. A valid packet grants neither
/// publication nor read authority; the original Run journal and current
/// publisher still fence its adoption. Bounds and wire match Native originals.
pub(all) enum ClientRunPolicyOriginalsIssue {
  ForeignRun
  PublicationPolicy(@checked.LocalDependencyBodyIssue)
  CapacityExceeded
  Encoding
  CustodyLost
}

///|
fn client_policy_original_text(
  object : @decode.ObjectView,
  key : String,
) -> String? {
  @decode.lookup(object, key).bind(fn(value) { @decode.text(value).to_option() })
}

///|
// Finite originals remain inside the existing Run row and its unchanged
// physical record budget. This is custody, never read or egress authority.
pub fn issue_client_run_policy_originals(
  prepared : PreparedClientProgram,
  compiled? : ClientCompiledRun,
) -> Result[String, ClientRunPolicyOriginalsIssue] {
  let selected = match compiled {
    Some(value) => {
      if !client_compiled_run_matches(value, prepared) {
        return Err(ForeignRun)
      }
      client_compiled_run_publication_policy_bodies(value, 65536, 8192, 64)
    }
    None => prepared_client_publication_policy_bodies(prepared, 65536, 8192, 64)
  }
  let bodies = match selected {
    Ok(value) => value
    Err(issue) => return Err(PublicationPolicy(issue))
  }
  encode_client_run_policy_originals(bodies)
}

///|
/// Borrow the original checked Effect's Result policy closure for the existing
/// packet. This issues no compilation, policy, current permission or read grant.
pub fn issue_client_effect_run_policy_originals(
  prepared : PreparedClientEffectComputation,
) -> Result[String, ClientRunPolicyOriginalsIssue] {
  let bodies = match
    prepared_client_effect_publication_policy_bodies(prepared, 65536, 8192, 64) {
    Ok(value) => value
    Err(issue) => return Err(PublicationPolicy(issue))
  }
  encode_client_run_policy_originals(bodies)
}

///|
// All callers use the same existing packet and bounds. Policy selection and
// original Host/journal authenticity are separate from this pure encoding.
fn encode_client_run_policy_originals(
  bodies : Array[(String, String, String)],
) -> Result[String, ClientRunPolicyOriginalsIssue] {
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
pub fn read_client_run_policy_originals(
  wire : String,
) -> Result[
  Array[@publication.CapturedEffectDependencyBody],
  ClientRunPolicyOriginalsIssue,
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
    client_policy_original_text(root, "root_policy_cid") is Some(root_cid) &&
    @decode.lookup(root, "bodies") is Some(list) &&
    @decode.elements(list) is Ok(elements) &&
    elements.length() > 0 &&
    elements.length() <= 64 else {
    return Err(CustodyLost)
  }
  let bodies : Array[@publication.CapturedEffectDependencyBody] = []
  for element in elements {
    guard @decode.closed_object(element, ["body", "cid", "kind"]) is Ok(fields) &&
      client_policy_original_text(fields, "body") is Some(body) &&
      client_policy_original_text(fields, "cid") is Some(cid) &&
      client_policy_original_text(fields, "kind") is Some(kind) &&
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
