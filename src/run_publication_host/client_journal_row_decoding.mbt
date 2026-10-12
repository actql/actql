///|
pub(all) enum ClientJournalDecodingIssue {
  CustodyLost
} derive(Eq, Debug)

///|
/// Original physical issuance count syntax and finite Native profile. This
/// does not prove a complete inventory: the journal must scan its same Store
/// transaction and validate every original row and custody relationship.
pub fn client_journal_issuance_count(
  bytes : Bytes,
  max_records : Int,
) -> Result[Int, ClientJournalDecodingIssue] {
  if max_records < 1 || max_records > 1024 || bytes.length() > 4 {
    return Err(CustodyLost)
  }
  let text = @utf8.decode(bytes) catch { _ => return Err(CustodyLost) }
  if text.is_empty() {
    return Err(CustodyLost)
  }
  let mut count = 0
  for unit in text {
    let digit = unit.to_int() - 48
    if digit < 0 || digit > 9 {
      return Err(CustodyLost)
    }
    count = count * 10 + digit
  }
  if count > max_records || count.to_string() != text {
    return Err(CustodyLost)
  }
  Ok(count)
}

///|
/// Decode the existing Run row's closed shape and original request/Definition.
/// Returned encoding fields are not a retained Run or committed admission.
/// Policy, Effect and Checkpoint originals still require their existing Owners;
/// count, epoch, current authority and transaction custody are separate facts.
pub fn decode_client_run_journal_row(
  body : Bytes,
) -> Result[ClientRunJournalEncoding, ClientJournalDecodingIssue] {
  let source = @source.parse_json_bytes_preserving(body, {
    max_input_bytes: 131072,
    max_nodes: 32,
    max_depth: 4,
  }).to_option()
  guard source is Some(source) &&
    @decode.admit(source, {
      max_nodes: 32,
      max_depth: 4,
      max_string_bytes: 131072,
      max_total_string_bytes: 131072,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, [
      "version", "request", "run_definition", "dispatch_reserved", "physical_start_claimed",
      "cancellation_requested", "checkpoint", "publication_binding", "publication_policy_originals",
      "effect_material_originals",
    ])
    is Ok(object) else {
    return Err(CustodyLost)
  }
  let text = key => {
    @decode.lookup(object, key).bind(value => @decode.text(value).to_option())
  }
  let flag = key => {
    @decode.lookup(object, key).bind(value => @decode.boolean(value).to_option())
  }
  guard text("version") == Some("actql-native-client-run-row/0.1") &&
    text("request") is Some(request_wire) &&
    text("run_definition") is Some(definition_wire) &&
    flag("dispatch_reserved") is Some(dispatch_reserved) &&
    flag("physical_start_claimed") is Some(physical_start_claimed) &&
    flag("cancellation_requested") is Some(cancellation_requested) else {
    return Err(CustodyLost)
  }
  if physical_start_claimed && !dispatch_reserved {
    return Err(CustodyLost)
  }
  let request = match admit_client_request_identity_record_wire(request_wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let definition = match
    @publication.admit_publication_contract(
      "run_definition", definition_wire, 65536, 4096, 64,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let publication_binding = match
    @decode.lookup(object, "publication_binding") {
    Some(value) if @decode.is_null(value) => None
    Some(value) =>
      match @decode.text(value) {
        Ok(text) if text != "" && text.length() <= 4096 => Some(text)
        _ => return Err(CustodyLost)
      }
    None => return Err(CustodyLost)
  }
  let publication_policy_originals = match
    @decode.lookup(object, "publication_policy_originals") {
    None => None
    Some(value) =>
      match @decode.text(value) {
        Ok(wire) => Some(wire)
        Err(_) => return Err(CustodyLost)
      }
  }
  let effect_material_originals = match
    @decode.lookup(object, "effect_material_originals") {
    None => None
    Some(value) =>
      match @decode.text(value) {
        Ok(wire) => Some(wire)
        Err(_) => return Err(CustodyLost)
      }
  }
  let checkpoint = match @decode.lookup(object, "checkpoint") {
    Some(value) if @decode.is_null(value) => None
    Some(value) =>
      match @decode.text(value) {
        Ok(wire) => Some(wire)
        Err(_) => return Err(CustodyLost)
      }
    None => return Err(CustodyLost)
  }
  let record : ClientRunJournalEncoding = {
    request,
    definition,
    dispatch_reserved,
    physical_start_claimed,
    cancellation_requested,
    publication_binding,
    publication_policy_originals,
    effect_material_originals,
    checkpoint,
  }
  match client_run_journal_row_body(record) {
    Ok(original) if original == body => Ok(record)
    _ => Err(CustodyLost)
  }
}
