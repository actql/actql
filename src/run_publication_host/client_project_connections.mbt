///|
/// Original public connection declarations, not installed Sources or grants.
/// Connector-specific readers still validate every selected entry's fields.
struct ClientProjectConnections {
  wire : String
  entries : Array[(String, String, String)]
}

///|
/// Keep exact UTF-8 value spans from the same bounded original parse. No JSON
/// reserialization, canonical identity or secret resolution occurs here.
pub fn admit_client_project_connections(
  wire : String,
) -> Result[ClientProjectConnections, ClientProjectBindingsIssue] {
  let bytes = @utf8.encode(wire)
  let cursor = match project_metadata_cursor(bytes) {
    Ok(value) => value
    Err(_) => return Err(InvalidBindings)
  }
  let object = match @decode.closed_object(cursor, ["version", "connections"]) {
    Ok(value) => value
    Err(_) => return Err(InvalidBindings)
  }
  guard @decode.lookup(object, "version") is Some(version) &&
    @decode.text(version) == Ok("actql-connectors/0.1") &&
    @decode.lookup(object, "connections") is Some(connections) &&
    @decode.object_length(connections) is Some(count) else {
    return Err(InvalidBindings)
  }
  let entries : Array[(String, String, String)] = []
  for index in 0..<count {
    guard @decode.field_at(connections, index) is Some((name, value)) &&
      !name.is_empty() &&
      !name.contains("\u{0000}") &&
      @decode.open_object(value) is Ok(entry) &&
      @decode.lookup(entry, "connector") is Some(connector) &&
      project_configuration_text(connector) is Some(connector) else {
      return Err(InvalidBindings)
    }
    let span = @decode.cursor_span(value)
    if span.start_byte < 0 ||
      span.end_byte < span.start_byte ||
      span.end_byte > bytes.length() {
      return Err(InvalidBindings)
    }
    let original = @utf8.decode(bytes[span.start_byte:span.end_byte]) catch {
      _ => return Err(InvalidBindings)
    }
    entries.push((name, connector, original))
  }
  Ok({ wire, entries, })
}

///|
pub fn ClientProjectConnections::original_wire(self : Self) -> String {
  self.wire
}

///|
pub fn ClientProjectConnections::count(self : Self) -> Int {
  self.entries.length()
}

///|
/// Out-of-range is absence, not selection of another alias or a default.
pub fn ClientProjectConnections::at(
  self : Self,
  index : Int,
) -> (String, String, String)? {
  self.entries.get(index)
}
