///|
/// Private saved metadata, not execution authority, current availability,
/// control revision or a new versioned RunState. Preserve exact original bytes.
struct ClientRunStateOriginal {
  manifest : @publication.PublicationContract
  state_wire : String
  wire : String
}

///|
/// The same validated immutable Manifest DATA retained by this original.
/// It supplies no Store fact, current availability or read authorization.
pub fn ClientRunStateOriginal::original_manifest(
  self : ClientRunStateOriginal,
) -> @publication.PublicationContract {
  self.manifest
}

///|
pub fn ClientRunStateOriginal::state_wire(
  self : ClientRunStateOriginal,
) -> String {
  self.state_wire
}

///|
pub fn ClientRunStateOriginal::wire(self : ClientRunStateOriginal) -> String {
  self.wire
}

///|
/// The existing Core owns both closed Manifest and RunState validation. This
/// serializer cannot issue the Native opaque actual-Store observation.
pub fn prepare_client_run_state_original(
  definition : @publication.PublicationContract,
  manifest : @publication.PublicationContract,
  state_wire : String,
) -> Result[ClientRunStateOriginal, ClientJournalDecodingIssue] {
  match
    @publication.validate_original_succeeded_run_state(
      definition, manifest, state_wire, 65536, 8192, 64,
    ) {
    Ok(_) => ()
    Err(_) => return Err(CustodyLost)
  }
  encode_client_run_state_original(definition, manifest, state_wire)
}

///|
fn encode_client_run_state_original(
  definition : @publication.PublicationContract,
  manifest : @publication.PublicationContract,
  state_wire : String,
) -> Result[ClientRunStateOriginal, ClientJournalDecodingIssue] {
  try {
    let writer = @encode.writer(131072, 8, 1)
    @encode.begin_object(writer)
    @encode.key(writer, "manifest")
    @encode.string_value(
      writer,
      @publication.publication_contract_json(manifest),
    )
    @encode.key(writer, "run_definition_cid")
    let definition_cid = @publication.publication_contract_identity(definition)
    @encode.string_value(writer, definition_cid)
    @encode.key(writer, "state")
    @encode.string_value(writer, state_wire)
    @encode.end_object(writer)
    Ok({ manifest, state_wire, wire: @encode.finish(writer), })
  } catch {
    _ => Err(CustodyLost)
  }
}

///|
/// Read original metadata under the authenticated original Run. No recompile,
/// recapture, availability query, grant or permission is issued on restoration.
pub fn restore_client_run_state_original(
  definition : @publication.PublicationContract,
  wire : String,
) -> Result[ClientRunStateOriginal, ClientJournalDecodingIssue] {
  restore_client_run_state_original_body(definition, wire, false)
}

///|
/// Validate authentic retained metadata without making missing historical
/// observation counters into public state, permission or a restoration repair.
pub fn validate_client_historical_run_state_original(
  definition : @publication.PublicationContract,
  wire : String,
) -> Result[Unit, ClientJournalDecodingIssue] {
  restore_client_run_state_original_body(definition, wire, true).map(_ => ())
}

///|
fn restore_client_run_state_original_body(
  definition : @publication.PublicationContract,
  wire : String,
  historical : Bool,
) -> Result[ClientRunStateOriginal, ClientJournalDecodingIssue] {
  let parsed = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 131072,
      max_nodes: 8,
      max_depth: 1,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  guard @decode.admit(parsed, {
      max_nodes: 8,
      max_depth: 1,
      max_string_bytes: 65536,
      max_total_string_bytes: 131072,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, ["manifest", "run_definition_cid", "state"])
    is Ok(object) else {
    return Err(CustodyLost)
  }
  let text = key => {
    @decode.lookup(object, key).bind(value => @decode.text(value).to_option())
  }
  guard text("manifest") is Some(manifest_wire) &&
    text("state") is Some(state_wire) &&
    text("run_definition_cid") ==
    Some(@publication.publication_contract_identity(definition)) else {
    return Err(CustodyLost)
  }
  let manifest = match
    @publication.admit_publication_contract(
      "result_manifest", manifest_wire, 65536, 8192, 64,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  if historical {
    if @publication.validate_historical_original_succeeded_run_state(
        definition, manifest, state_wire, 65536, 8192, 64,
      )
      is Err(_) {
      return Err(CustodyLost)
    }
    return match
      encode_client_run_state_original(definition, manifest, state_wire) {
      Ok(original) if original.wire == wire => Ok(original)
      _ => Err(CustodyLost)
    }
  }
  match prepare_client_run_state_original(definition, manifest, state_wire) {
    Ok(original) if original.wire == wire => Ok(original)
    _ => Err(CustodyLost)
  }
}
