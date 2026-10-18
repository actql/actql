///|
/// Ordered public `databases` DATA, not an installation, complete workspace
/// inventory, publication certificate, key proof or acquisition permission.
/// Every declaration retains its exact original value span, never a re-encode.
pub struct NotionDatabaseReadDeclarations {
  priv original_self : Ref[NotionDatabaseReadDeclarations?]
  priv source_cid : String
  priv aliases : Array[String]
  priv declarations : Array[NotionDatabaseReadDeclaration]
}

///|
fn notion_database_read_declarations_is_original(
  declarations : NotionDatabaseReadDeclarations,
) -> Bool {
  match declarations.original_self.val {
    Some(original) => physical_equal(original, declarations)
    None => false
  }
}

///|
/// Whole-map byte/node/depth bounds apply before member construction. Each
/// whole source byte is charged once before copy/hash. Each resource_alias occurrence
/// costs one plus its UTF-16 length, and every retained value
/// byte is charged before copying/hashing. Contract nodes, text and work share
/// one remaining budget across all members; max_columns stays per declaration.
/// Bounds are structural/work limits, never a Resource reservation or grant.
pub fn read_notion_database_read_declarations(
  bytes : Bytes,
  limits : NotionReadContractLimits,
  max_databases : Int,
) -> Result[NotionDatabaseReadDeclarations, NotionReadContractIssue] {
  if !read_contract_limits_valid(limits) || max_databases < 0 {
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
  let original = match database_cursor(original_bytes, limits.metadata) {
    Ok(value) => value
    Err(issue) => return Err(Metadata(issue))
  }
  guard @decode.open_object(original) is Ok(root) &&
    @decode.object_field_names(original) is Ok(aliases) else {
    return Err(InvalidDeclaration)
  }
  if aliases.length() > max_databases {
    return Err(BudgetExceeded)
  }
  let declarations = []
  for resource_alias in aliases {
    if resource_alias.is_empty() ||
      @admitted.text_value(resource_alias, limits.metadata.max_name_bytes)
      is None {
      return Err(InvalidDeclaration)
    }
    if !read_contract_spend(budget, 1) ||
      !read_contract_spend(budget, resource_alias.length()) {
      return Err(BudgetExceeded)
    }
    let cursor = @decode.lookup(root, resource_alias).unwrap()
    let span = @decode.cursor_span(cursor)
    if span.start_byte < 0 ||
      span.end_byte < span.start_byte ||
      span.end_byte > original_bytes.length() {
      return Err(InvalidDeclaration)
    }
    let length = span.end_byte - span.start_byte
    if !read_contract_spend(budget, length) {
      return Err(BudgetExceeded)
    }
    let value_bytes = Bytes::makei(length, index => {
      original_bytes[span.start_byte + index]
    })
    let declaration = match
      read_notion_database_read_declaration_cursor(
        value_bytes, cursor, limits, budget,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    declarations.push(declaration)
  }
  let declarations : NotionDatabaseReadDeclarations = {
    original_self: Ref(None),
    source_cid: "sha256:" + @sha.hex(original_bytes),
    aliases,
    declarations,
  }
  declarations.original_self.val = Some(declarations)
  Ok(declarations)
}

///|
pub fn notion_database_read_declarations_count(
  declarations : NotionDatabaseReadDeclarations,
) -> Int? {
  if notion_database_read_declarations_is_original(declarations) {
    Some(declarations.declarations.length())
  } else {
    None
  }
}

///|
pub fn notion_database_read_declarations_alias_at(
  declarations : NotionDatabaseReadDeclarations,
  index : Int,
) -> String? {
  if !notion_database_read_declarations_is_original(declarations) ||
    index < 0 ||
    index >= declarations.aliases.length() {
    None
  } else {
    Some(declarations.aliases[index])
  }
}

///|
pub fn notion_database_read_declarations_at(
  declarations : NotionDatabaseReadDeclarations,
  index : Int,
) -> NotionDatabaseReadDeclaration? {
  if !notion_database_read_declarations_is_original(declarations) ||
    index < 0 ||
    index >= declarations.declarations.length() {
    None
  } else {
    Some(declarations.declarations[index])
  }
}

///|
pub fn notion_database_read_declarations_matches(
  declarations : NotionDatabaseReadDeclarations,
  index : Int,
  declaration : NotionDatabaseReadDeclaration,
) -> Bool {
  match notion_database_read_declarations_at(declarations, index) {
    Some(original) => physical_equal(original, declaration)
    None => false
  }
}

///|
/// SOURCE identity of the complete retained input, including whitespace. This
/// identity is DATA, not the authority or identity of any semantic Contract.
pub fn notion_database_read_declarations_source_cid(
  declarations : NotionDatabaseReadDeclarations,
) -> String? {
  if notion_database_read_declarations_is_original(declarations) {
    Some(declarations.source_cid)
  } else {
    None
  }
}
