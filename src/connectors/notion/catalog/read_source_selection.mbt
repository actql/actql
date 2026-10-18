///|
/// Original DATA occurrence, not installation membership/currentness, a Ref,
/// preparation request, credential grant or permission to observe the schema.
pub struct NotionReadSourceSelection {
  priv original_self : Ref[NotionReadSourceSelection?]
  priv declaration : NotionDatabaseReadDeclaration
  priv database : NotionDatabaseCatalog
  priv index : Int
}

///|
fn notion_read_source_selection_is_original(
  selection : NotionReadSourceSelection,
) -> Bool {
  match selection.original_self.val {
    Some(original) => physical_equal(original, selection)
    None => false
  }
}

///|
/// Exact source bytes, not a new logical Contract/CID domain. Whitespace,
/// CRLF, key order, selectors and Unicode stay bound to this observation.
pub fn notion_database_read_declaration_source_cid(
  declaration : NotionDatabaseReadDeclaration,
) -> String {
  declaration.source_cid
}

///|
pub fn notion_database_read_declaration_source_bytes(
  declaration : NotionDatabaseReadDeclaration,
) -> Int {
  declaration.original_bytes.length()
}

///|
/// Bound all original inventory comparisons before selecting through the same
/// existing Owner. No first/name/compatible-schema fallback is introduced.
pub fn select_notion_read_source(
  declaration : NotionDatabaseReadDeclaration,
  database : NotionDatabaseCatalog,
  max_work : Int,
) -> Result[NotionReadSourceSelection, NotionReadContractIssue] {
  if max_work <= 0 {
    return Err(InvalidLimits)
  }
  let mut remaining = max_work
  for text in [declaration.database_id, database.id] {
    if text.length() > remaining {
      return Err(BudgetExceeded)
    }
    remaining -= text.length()
  }
  for (id, _) in database.sources {
    if remaining == 0 || id.length() > remaining - 1 {
      return Err(BudgetExceeded)
    }
    remaining -= 1 + id.length()
    if declaration.source_id is Some(selected) {
      if selected.length() > remaining {
        return Err(BudgetExceeded)
      }
      remaining -= selected.length()
    }
  }
  let index = match notion_database_read_source_index(declaration, database) {
    Ok(index) => index
    Err(issue) => return Err(issue)
  }
  let selection : NotionReadSourceSelection = {
    original_self: Ref(None),
    declaration,
    database,
    index,
  }
  selection.original_self.val = Some(selection)
  Ok(selection)
}

///|
pub fn notion_read_source_selection_matches(
  selection : NotionReadSourceSelection,
  declaration : NotionDatabaseReadDeclaration,
  database : NotionDatabaseCatalog,
) -> Bool {
  notion_read_source_selection_is_original(selection) &&
  physical_equal(selection.declaration, declaration) &&
  physical_equal(selection.database, database)
}

///|
pub fn notion_read_source_selection_id(
  selection : NotionReadSourceSelection,
) -> String {
  selection.database.sources[selection.index].0
}

///|
pub fn project_notion_selected_read_source(
  selection : NotionReadSourceSelection,
  bytes : Bytes,
  limits : NotionDatabaseLimits,
) -> Result[NotionDataSourceCatalog, NotionReadContractIssue] {
  if !notion_read_source_selection_is_original(selection) {
    return Err(ForeignOriginal)
  }
  match
    project_notion_data_source(
      selection.database,
      selection.index,
      bytes,
      limits,
    ) {
    Ok(source) => Ok(source)
    Err(issue) => Err(Metadata(issue))
  }
}

///|
pub fn bind_notion_selected_read_contracts(
  selection : NotionReadSourceSelection,
  source : NotionDataSourceCatalog,
  limits : NotionReadContractLimits,
) -> Result[NotionDataSourceReadContracts, NotionReadContractIssue] {
  if !notion_read_source_selection_is_original(selection) ||
    !physical_equal(selection.database, source.database) ||
    selection.index != source.source_index {
    return Err(ForeignOriginal)
  }
  bind_notion_data_source_read_contracts(selection.declaration, source, limits)
}
