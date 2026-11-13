///|
pub(all) enum ClientJournalDecodingIssue {
  CustodyLost
} derive(Eq, Debug)

///|
/// Construction geometry, never decoded authority or durable custody. Both
/// observations belong to the same preserving parse and original Read.
pub(all) enum ClientRunJournalConstruction {
  RunJournalParse(Int)
  RunJournalCanonical(Int, Int64, Int, Int)
  // Successful exact-row output handoff, not another construction grant.
  RunJournalRetained(Int, Int64, Int, Int)
}

///|
/// Original physical issuance count syntax and selected finite policy. This
/// does not prove a complete inventory: the journal must scan its same Store
/// transaction and validate every original row and custody relationship.
pub fn client_journal_issuance_count(
  bytes : Bytes,
  max_records : Int,
) -> Result[Int, ClientJournalDecodingIssue] {
  // A nonnegative Int has at most ten decimal digits. Bound parsing before
  // multiply/add; this is representation capacity, not another record policy.
  if max_records < 1 || bytes.length() > 10 {
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
    if count > max_records / 10 ||
      (count == max_records / 10 && digit > max_records % 10) {
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
  before_construction? : ((ClientRunJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ])? = None,
) -> Result[ClientRunJournalEncoding, ClientJournalDecodingIssue] {
  decode_client_run_journal_row_originals(
    body,
    false,
    false,
    before_construction~,
  ).map(value => value.0)
}

///|
/// Additive raw-original projection for the existing acceptance transaction.
/// Nested finite-policy metadata, retained Run binding, current authority and
/// physical custody must still be validated by their existing Owners.
pub fn decode_client_run_journal_row_with_local_policy(
  body : Bytes,
  before_construction? : ((ClientRunJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ])? = None,
) -> Result[(ClientRunJournalEncoding, String?), ClientJournalDecodingIssue] {
  decode_client_run_journal_row_originals(
    body,
    true,
    false,
    before_construction~,
  ).map(value => (value.0, value.1))
}

///|
/// Raw private metadata in the same existing Native row. Authentication,
/// original compiled-evidence validation and current authority remain separate.
pub fn decode_client_run_journal_row_with_observation_originals(
  body : Bytes,
  before_construction? : ((ClientRunJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ])? = None,
) -> Result[
  (ClientRunJournalEncoding, String?, String?),
  ClientJournalDecodingIssue,
] {
  decode_client_run_journal_row_originals(
    body,
    true,
    true,
    before_construction~,
  )
}

///|
/// Decode a changed row using the same already admitted immutable identity
/// when its exact canonical wire matches. Changed or foreign fields take the
/// existing full admission. This is DATA reuse, not a Run or current grant.
pub fn decode_client_run_journal_row_with_retained_identity(
  body : Bytes,
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  before_construction? : ((ClientRunJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ])? = None,
) -> Result[
  (ClientRunJournalEncoding, String?, String?),
  ClientJournalDecodingIssue,
] {
  decode_client_run_journal_row_originals(
    body,
    true,
    true,
    retained_identity=Some((request, definition)),
    before_construction~,
  )
}

///|
fn decode_client_journal_request(
  wire : String,
  original : ClientRequestIdentity?,
) -> Result[(ClientRequestIdentity, String), ClientJournalDecodingIssue] {
  // The nested decoder encodes its input before parsing. Enforce its SAME
  // existing byte limit without allocating that copy on rejected outer rows.
  if @scalar.admit_utf8_length(wire, 4096) is Err(_) {
    return Err(CustodyLost)
  }
  if original is Some(value) &&
    client_request_identity_record_wire(value) is Ok(expected) &&
    expected == wire {
    return Ok((value, expected))
  }
  let value = match admit_client_request_identity_record_wire(wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  // Request field admission checks its identities. Retain the original
  // canonical-wire requirement as well, including nested JSON whitespace.
  match client_request_identity_record_wire(value) {
    Ok(expected) if expected == wire => Ok((value, expected))
    _ => Err(CustodyLost)
  }
}

///|
fn decode_client_journal_definition(
  wire : String,
  original : @publication.PublicationContract?,
) -> Result[
  (@publication.PublicationContract, String),
  ClientJournalDecodingIssue,
] {
  if original is Some(value) &&
    @publication.publication_contract_name(value) == "run_definition" &&
    @publication.publication_contract_check_limits(value, 65536, 4096, 64)
    is Ok(_) &&
    @publication.publication_contract_json(value) == wire {
    return Ok((value, wire))
  }
  let value = match
    @publication.admit_publication_contract(
      "run_definition", wire, 65536, 4096, 64,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  if @publication.publication_contract_json(value) != wire {
    return Err(CustodyLost)
  }
  Ok((value, wire))
}

///|
fn decode_client_run_journal_row_originals(
  body : Bytes,
  allow_local_policy : Bool,
  allow_observation_originals : Bool,
  retained_identity? : (ClientRequestIdentity, @publication.PublicationContract)? = None,
  before_construction? : ((ClientRunJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ])? = None,
) -> Result[
  (ClientRunJournalEncoding, String?, String?),
  ClientJournalDecodingIssue,
] {
  let before_construction = before_construction.map(
    client_run_decode_invocation,
  )
  let keys = [
    "version", "request", "run_definition", "dispatch_reserved", "physical_start_claimed",
    "cancellation_requested", "checkpoint", "publication_binding", "publication_policy_originals",
    "effect_material_originals", "task_materials_cid",
  ]
  if allow_local_policy {
    keys.push("local_run_policy_originals")
  }
  if allow_observation_originals {
    keys.push("run_observation_originals")
  }
  let observed = before_construction is Some(_)
  let row_bytes = if observed { body.length() } else { 131072 }
  if row_bytes <= 0 || row_bytes >= 2147483519 {
    return Err(CustodyLost)
  }
  if before_construction is Some(reserve) {
    match reserve(RunJournalParse(row_bytes)) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  let wire = @utf8.decode(body) catch { _ => return Err(CustodyLost) }
  let parser = match
    @source.start_json_parse(
      wire,
      { max_input_bytes: row_bytes, max_nodes: 32, max_depth: 4, },
      data_keys=true,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let parsed = while true {
    match @source.advance_json_parse(parser, 256) {
      Ok(@source.JsonParseContinue(_)) => continue
      Ok(@source.JsonParseComplete(value, ..)) => break value
      _ => return Err(CustodyLost)
    }
  } nobreak {
    return Err(CustodyLost)
  }
  if before_construction is Some(reserve) {
    match
      reserve(
        RunJournalCanonical(
          row_bytes,
          // The existing raw row plus its decoded immutable text are retained
          // through canonical comparison. UTF16 units cannot exceed input bytes.
          2L * parsed.usage.input_bytes.to_int64(),
          parsed.usage.nodes,
          parsed.usage.depth,
        ),
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  let source = parsed.node
  guard @decode.admit(source, {
      max_nodes: 32,
      max_depth: 4,
      max_string_bytes: row_bytes,
      max_total_string_bytes: row_bytes,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, keys) is Ok(object) else {
    return Err(CustodyLost)
  }
  if observed {
    for key in keys {
      if key != "run_observation_originals" &&
        @decode.lookup(object, key) is Some(value) &&
        @decode.text(value) is Ok(wire) &&
        @scalar.admit_utf8_length(wire, 131072) is Err(_) {
        return Err(CustodyLost)
      }
    }
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
  let (request, request_wire) = match
    decode_client_journal_request(
      request_wire,
      retained_identity.map(value => value.0),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (definition, definition_wire) = match
    decode_client_journal_definition(
      definition_wire,
      retained_identity.map(value => value.1),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
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
  let local_run_policy_originals = match
    @decode.lookup(object, "local_run_policy_originals") {
    None => None
    Some(value) =>
      match @decode.text(value) {
        Ok(wire) if @scalar.admit_utf8_length(wire, 8192) is Ok(_) => Some(wire)
        _ => return Err(CustodyLost)
      }
  }
  let run_observation_originals = match
    @decode.lookup(object, "run_observation_originals") {
    None => None
    Some(value) =>
      match @decode.text(value) {
        Ok(wire) => Some(wire)
        Err(_) => return Err(CustodyLost)
      }
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
    task_materials_cid: match @decode.lookup(object, "task_materials_cid") {
      None => None
      Some(value) =>
        match @decode.text(value) {
          Ok(cid) if valid_client_request_cid(cid) => Some(cid)
          _ => return Err(CustodyLost)
        }
    },
    checkpoint,
  }
  match
    client_run_journal_row_body_from_wires(
      record,
      request_wire,
      definition_wire,
      local_run_policy_originals~,
      run_observation_originals~,
      comparison_bytes=if observed { Some(row_bytes) } else { None },
      // Canonical emission is covered by this same observed decode lifetime;
      // its resource callback has already run before any reconstruction.
      before_construction=if observed {
        Some((_, _, _) => Ok(()))
      } else {
        None
      },
    ) {
    Ok(original) if original == body => {
      if before_construction is Some(handoff) {
        match
          handoff(
            RunJournalRetained(
              row_bytes,
              2L * parsed.usage.input_bytes.to_int64(),
              parsed.usage.nodes,
              parsed.usage.depth,
            ),
          ) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
      }
      Ok((record, local_run_policy_originals, run_observation_originals))
    }
    _ => Err(CustodyLost)
  }
}
