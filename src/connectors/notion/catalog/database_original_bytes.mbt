///|
/// Exact retained provider bytes projected as bounded UTF8 text. This is not
/// canonical JSON, authority, a completeness receipt or fresh metadata I/O.
pub fn notion_database_original_json(
  database : NotionDatabaseCatalog,
  max_bytes : Int,
) -> Result[String, NotionDatabaseIssue] {
  if database.raw.length() > max_bytes {
    return Err(BudgetExceeded)
  }
  Ok(@utf8.decode(database.raw[:])) catch {
    _ => Err(InvalidResponse)
  }
}

///|
pub fn notion_data_source_original_json(
  source : NotionDataSourceCatalog,
  max_bytes : Int,
) -> Result[String, NotionDatabaseIssue] {
  if source.raw.length() > max_bytes {
    return Err(BudgetExceeded)
  }
  Ok(@utf8.decode(source.raw[:])) catch {
    _ => Err(InvalidResponse)
  }
}

///|
/// Preserve exact authored declaration bytes, including shorthand, whitespace,
/// Unicode, selector and checked Contract bodies. Re-encoding its Cursor is
/// not a source-identity-preserving replacement.
pub fn notion_database_read_declaration_original_json(
  declaration : NotionDatabaseReadDeclaration,
  max_bytes : Int,
) -> Result[String, NotionReadContractIssue] {
  if declaration.original_bytes.length() > max_bytes {
    return Err(BudgetExceeded)
  }
  Ok(@utf8.decode(declaration.original_bytes[:])) catch {
    _ => Err(Metadata(InvalidResponse))
  }
}
