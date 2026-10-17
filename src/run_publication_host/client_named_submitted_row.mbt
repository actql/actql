///|
/// Closed physical row DATA. Its authenticator is not verified here: only the
/// original Journal with the original epoch key can establish that custody.
pub(all) struct ClientSubmittedNameRow {
  binding : ClientSubmittedNameBinding
  authenticator : Bytes
}

///|
pub fn client_submitted_name_binding_fields(
  binding : ClientSubmittedNameBinding,
) -> (ClientSubmittedNameKey, String, String, String) {
  (
    binding.key,
    binding.authority_scope_cid,
    binding.submission_id,
    binding.intent_cid,
  )
}

///|
/// Private physical index input, not a public identity, permission, or epoch.
/// Scope/intent are deliberately absent: changing either must find the same
/// occupied caller name and refuse rather than select another index entry.
pub fn client_submitted_name_index_input(
  key : ClientSubmittedNameKey,
) -> Result[String, ClientSubmittedNameIssue] {
  try {
    let writer = @encode.writer(8192, 4, 2)
    @encode.begin_array(writer)
    @encode.string_value(writer, key.namespace_id)
    @encode.string_value(writer, key.actor)
    @encode.string_value(writer, key.name)
    @encode.end_array(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
fn submitted_name_authenticator_hex(bytes : Bytes) -> String {
  let output = StringBuilder(size_hint=64)
  let digits : FixedArray[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  for byte in bytes {
    output.write_char(digits[byte.to_int() >> 4])
    output.write_char(digits[byte.to_int() & 15])
  }
  output.to_string()
}

///|
pub fn client_submitted_name_row_body(
  row : ClientSubmittedNameRow,
) -> Result[Bytes, ClientSubmittedNameIssue] {
  if row.authenticator.length() != 32 {
    return Err(CustodyLost)
  }
  let original = match
    client_submitted_name_authentication_input(row.binding, 8192) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  try {
    let writer = @encode.writer(16384, 3, 2)
    @encode.begin_array(writer)
    @encode.string_value(writer, original)
    @encode.string_value(
      writer,
      submitted_name_authenticator_hex(row.authenticator),
    )
    @encode.end_array(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
fn submitted_name_row_cursor(body : Bytes) -> @decode.Cursor? {
  @source.parse_json_bytes_preserving(body, {
    max_input_bytes: 16384,
    max_nodes: 8,
    max_depth: 2,
  })
  .to_option()
  .bind(source => {
    @decode.admit(source, {
      max_nodes: 8,
      max_depth: 2,
      max_string_bytes: 8192,
      max_total_string_bytes: 16384,
    }).to_option()
  })
}

///|
/// Reject noncanonical, malformed and substituted fields before the physical
/// Owner authenticates the original row. No missing record is reconstructed.
pub fn decode_client_submitted_name_row(
  body : Bytes,
) -> Result[ClientSubmittedNameRow, ClientSubmittedNameIssue] {
  guard submitted_name_row_cursor(body) is Some(cursor) &&
    @decode.array_length(cursor) == Some(2) &&
    @decode.element_at(cursor, 0).bind(c => @decode.text(c).to_option())
    is Some(original) &&
    @decode.element_at(cursor, 1).bind(c => @decode.text(c).to_option())
    is Some(tag) &&
    submission_record_hex(tag) is Some(authenticator) &&
    submitted_name_row_cursor(@utf8.encode(original)) is Some(fields) &&
    @decode.array_length(fields) == Some(7) else {
    return Err(CustodyLost)
  }
  let text = index => {
    @decode.element_at(fields, index).bind(c => @decode.text(c).to_option())
  }
  guard text(0) == Some("scoped-submission-name") &&
    text(1) is Some(namespace_id) &&
    text(2) is Some(actor) &&
    text(3) is Some(name) &&
    text(4) is Some(scope) &&
    text(5) is Some(submission_id) &&
    text(6) is Some(intent_cid) else {
    return Err(CustodyLost)
  }
  let key = match
    prepare_client_submitted_name_key(namespace_id, actor, name, scope) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let binding = match
    prepare_client_submitted_name_binding(key, scope, submission_id, intent_cid) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let row = { binding, authenticator, }
  match client_submitted_name_row_body(row) {
    Ok(canonical) if canonical == body => Ok(row)
    _ => Err(CustodyLost)
  }
}
