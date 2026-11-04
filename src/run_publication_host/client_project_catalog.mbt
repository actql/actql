///|
/// Bounded declaration-file DATA. Entry bodies remain exact original JSON;
/// the selected declaration reader still checks every view and binding.
struct ClientProjectCatalog {
  wire : String
  entries : Array[(String, String)]
}

///|
pub(all) enum ClientProjectCatalogIssue {
  InvalidCatalog
} derive(Eq, Debug)

///|
/// Parse the explicit catalog locator's document without opening a resource,
/// inferring a schema, issuing a Contract or changing connection authority.
pub fn admit_client_project_catalog(
  wire : String,
) -> Result[ClientProjectCatalog, ClientProjectCatalogIssue] {
  let bytes = @utf8.encode(wire)
  let source = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: 65536,
      max_nodes: 4096,
      max_depth: 16,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidCatalog)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 4096,
      max_depth: 16,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidCatalog)
  }
  let object = match @decode.closed_object(cursor, ["connections"]) {
    Ok(value) => value
    Err(_) => return Err(InvalidCatalog)
  }
  guard @decode.lookup(object, "connections") is Some(connections) &&
    @decode.object_length(connections) is Some(count) else {
    return Err(InvalidCatalog)
  }
  let entries : Array[(String, String)] = []
  for index in 0..<count {
    guard @decode.field_at(connections, index) is Some((name, value)) &&
      !name.is_empty() &&
      !name.contains("\u{0000}") &&
      @decode.open_object(value) is Ok(_) else {
      return Err(InvalidCatalog)
    }
    let span = @decode.cursor_span(value)
    if span.start_byte < 0 ||
      span.end_byte < span.start_byte ||
      span.end_byte > bytes.length() {
      return Err(InvalidCatalog)
    }
    let original = @utf8.decode(bytes[span.start_byte:span.end_byte]) catch {
      _ => return Err(InvalidCatalog)
    }
    entries.push((name, original))
  }
  Ok({ wire, entries, })
}

///|
pub fn ClientProjectCatalog::original_wire(self : Self) -> String {
  self.wire
}

///|
pub fn ClientProjectCatalog::count(self : Self) -> Int {
  self.entries.length()
}

///|
/// An absent index never selects another connection or invents a declaration.
pub fn ClientProjectCatalog::at(self : Self, index : Int) -> (String, String)? {
  self.entries.get(index)
}
