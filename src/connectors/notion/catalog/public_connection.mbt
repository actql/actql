///|
/// Original public connection DATA. Credential references do not resolve a
/// secret, admit an installed Site, issue a grant or authorize metadata I/O.
pub struct NotionPublicConnection {
  priv original_self : Ref[NotionPublicConnection?]
  priv original_bytes : Bytes
  priv source_cid : String
  priv databases : NotionDatabaseReadDeclarations?
  priv credential_kind : String
  priv credential_reference : String
}

///|
fn notion_public_connection_is_original(value : NotionPublicConnection) -> Bool {
  match value.original_self.val {
    Some(original) => physical_equal(original, value)
    None => false
  }
}

///|
/// Admit the connection shape documented for the public connectors file.
/// Whole-input bounds apply before member admission. Work charges source bytes,
/// one plus credential-reference UTF-16 length, the exact retained map span,
/// and the existing aggregate declaration work. There is no budget reset per
/// alias, environment lookup, path resolution or new semantic identity domain.
pub fn read_notion_public_connection(
  bytes : Bytes,
  limits : NotionReadContractLimits,
  max_databases : Int,
  max_reference_bytes : Int,
) -> Result[NotionPublicConnection, NotionReadContractIssue] {
  if !read_contract_limits_valid(limits) ||
    max_databases < 0 ||
    max_reference_bytes <= 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.metadata.max_bytes {
    return Err(Metadata(BudgetExceeded))
  }
  let budget : NotionReadContractBudget = {
    work: limits.max_work,
    nodes: limits.contracts.max_nodes,
    text: limits.contracts.max_text_bytes,
  }
  if !read_contract_spend(budget, bytes.length()) {
    return Err(BudgetExceeded)
  }
  let original_bytes = Bytes::makei(bytes.length(), index => bytes[index])
  let cursor = match database_cursor(original_bytes, limits.metadata) {
    Ok(value) => value
    Err(issue) => return Err(Metadata(issue))
  }
  guard @decode.closed_object(cursor, ["connector", "databases", "credentials"])
    is Ok(root) &&
    @decode.lookup(root, "connector") is Some(connector) &&
    @decode.text(connector) == Ok("notion") &&
    @decode.lookup(root, "credentials") is Some(credentials) &&
    @decode.closed_object(credentials, ["integration_token"]) is Ok(secrets) &&
    @decode.lookup(secrets, "integration_token") is Some(token) &&
    @decode.closed_object(token, ["env", "path"]) is Ok(reference) &&
    @decode.object_length(token) == Some(1) else {
    return Err(InvalidDeclaration)
  }
  let (credential_kind, credential_cursor) = match
    @decode.field(reference, "env") {
    Present(value) => ("env", value)
    Missing =>
      match @decode.field(reference, "path") {
        Present(value) => ("path", value)
        _ => return Err(InvalidDeclaration)
      }
    ExplicitNull => return Err(InvalidDeclaration)
  }
  guard @decode.text(credential_cursor) is Ok(credential_reference) &&
    !credential_reference.is_empty() &&
    !credential_reference.contains("\u{0000}") else {
    return Err(InvalidDeclaration)
  }
  if !read_contract_spend(budget, 1) ||
    !read_contract_spend(budget, credential_reference.length()) {
    return Err(BudgetExceeded)
  }
  if @admitted.text_value(credential_reference, max_reference_bytes) is None {
    return Err(InvalidDeclaration)
  }
  let databases = match @decode.field(root, "databases") {
    Missing => None
    ExplicitNull => return Err(InvalidDeclaration)
    Present(map) => {
      let span = @decode.cursor_span(map)
      if span.start_byte < 0 ||
        span.end_byte < span.start_byte ||
        span.end_byte > original_bytes.length() {
        return Err(InvalidDeclaration)
      }
      let length = span.end_byte - span.start_byte
      if !read_contract_spend(budget, length) {
        return Err(BudgetExceeded)
      }
      let identity_bytes = Bytes::makei(length, index => {
        original_bytes[span.start_byte + index]
      })
      match
        read_notion_database_read_declarations_cursor(
          original_bytes, identity_bytes, map, limits, max_databases, budget,
        ) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
    }
  }
  let result : NotionPublicConnection = {
    original_self: Ref(None),
    original_bytes,
    source_cid: "sha256:" + @sha.hex(original_bytes),
    databases,
    credential_kind,
    credential_reference,
  }
  result.original_self.val = Some(result)
  Ok(result)
}

///|
pub fn notion_public_connection_databases(
  value : NotionPublicConnection,
) -> Result[NotionDatabaseReadDeclarations?, NotionReadContractIssue] {
  if notion_public_connection_is_original(value) {
    Ok(value.databases)
  } else {
    Err(ForeignOriginal)
  }
}

///|
pub fn notion_public_connection_credential_kind(
  value : NotionPublicConnection,
) -> Result[String, NotionReadContractIssue] {
  if notion_public_connection_is_original(value) {
    Ok(value.credential_kind)
  } else {
    Err(ForeignOriginal)
  }
}

///|
pub fn notion_public_connection_credential_reference(
  value : NotionPublicConnection,
) -> Result[String, NotionReadContractIssue] {
  if notion_public_connection_is_original(value) {
    Ok(value.credential_reference)
  } else {
    Err(ForeignOriginal)
  }
}

///|
pub fn notion_public_connection_source_cid(
  value : NotionPublicConnection,
) -> Result[String, NotionReadContractIssue] {
  if notion_public_connection_is_original(value) {
    Ok(value.source_cid)
  } else {
    Err(ForeignOriginal)
  }
}

///|
pub fn notion_public_connection_original_json(
  value : NotionPublicConnection,
  max_bytes : Int,
) -> Result[String, NotionReadContractIssue] {
  if !notion_public_connection_is_original(value) {
    return Err(ForeignOriginal)
  }
  if max_bytes < 0 || value.original_bytes.length() > max_bytes {
    return Err(BudgetExceeded)
  }
  Ok(@utf8.decode(value.original_bytes[:])) catch {
    _ => Err(Metadata(InvalidResponse))
  }
}
