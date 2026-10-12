///|
pub(all) enum ClientSubmittedRunRecordIssue {
  Encoding
  CustodyLost
} derive(Eq, Debug)

///|
fn submitted_run_record_text(
  object : @decode.ObjectView,
  name : String,
) -> String? {
  @decode.required(object, name)
  .to_option()
  .bind(cursor => @decode.text(cursor).to_option())
}

///|
/// The existing journal's exact admission-record codec. Bytes are not proof
/// of a committed transaction, current authority or permission to dispatch.
pub fn client_submitted_run_admission_wire(
  request : ClientRequestIdentity,
  run_definition_cid : String,
  revision : Int64,
) -> Result[String, ClientSubmittedRunRecordIssue] {
  let request = match client_request_identity_record_wire(request) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  try {
    let writer = @encode.writer(8192, 8, 2)
    @encode.begin_object(writer)
    @encode.key(writer, "admitted_revision")
    // The existing exact Int64 decoder accepts decimal text, not a JSON
    // number routed through a floating-point value.
    @encode.string_value(writer, revision.to_string())
    @encode.key(writer, "request")
    @encode.string_value(writer, request)
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(writer, run_definition_cid)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Encoding)
  }
}

///|
pub fn admit_client_submitted_run_admission_wire(
  wire : String,
) -> Result[
  (ClientRequestIdentity, String, Int64),
  ClientSubmittedRunRecordIssue,
] {
  let source = @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 8192,
    max_nodes: 8,
    max_depth: 2,
  }).to_option()
  guard source is Some(source) &&
    @decode.admit(source, {
      max_nodes: 8,
      max_depth: 2,
      max_string_bytes: 8192,
      max_total_string_bytes: 8192,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, [
      "admitted_revision", "request", "run_definition_cid",
    ])
    is Ok(object) &&
    submitted_run_record_text(object, "request") is Some(request_wire) &&
    submitted_run_record_text(object, "run_definition_cid")
    is Some(run_definition_cid) &&
    @decode.lookup(object, "admitted_revision") is Some(revision) &&
    @decode.decimal_int64(revision) is Ok(revision) &&
    revision >= 0L else {
    return Err(CustodyLost)
  }
  let request = match admit_client_request_identity_record_wire(request_wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  match
    client_submitted_run_admission_wire(request, run_definition_cid, revision) {
    Ok(original) if original == wire =>
      Ok((request, run_definition_cid, revision))
    _ => Err(CustodyLost)
  }
}
