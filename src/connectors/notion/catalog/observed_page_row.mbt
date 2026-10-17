///|
/// Assemble a full checked property row from an actual exact-page observation
/// and the same original data-source schema. No query response, installation,
/// Reference, target/version guard or write permission is manufactured here.
pub fn start_notion_observed_page_read_row(
  binding : NotionDataSourceReadContracts,
  page : OriginalNotionPage,
  max_properties : Int,
  limits : NotionReadRowLimits,
) -> Result[NotionReadRow, NotionReadRowIssue] {
  if limits.values.max_nodes <= 0 ||
    limits.values.max_depth <= 0 ||
    limits.values.max_text_bytes < 0 ||
    limits.max_columns <= 0 ||
    limits.max_work <= 0 ||
    max_properties < 0 {
    return Err(InvalidLimits)
  }
  if binding.source.properties.length() > max_properties {
    return Err(BudgetExceeded)
  }
  // Charge the original response scan and every schema-name/id/kind lookup
  // before projecting property occurrences. Subtraction avoids overflow; an
  // equal id/body or another observation cannot replenish this row's work.
  let mut work = limits.max_work
  if page.raw.length() > work {
    return Err(BudgetExceeded)
  }
  work -= page.raw.length()
  for property in binding.source.properties {
    for
      units in [
        page.raw.length(),
        property.name.length(),
        property.id.length(),
        property.kind.length(),
      ] {
      if units > work {
        return Err(BudgetExceeded)
      }
      work -= units
    }
  }
  let original = match
    original_query_row(binding.source, page.original, page.raw, max_properties) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  if work <= 0 {
    return Err(BudgetExceeded)
  }
  start_notion_read_row_original(
    binding,
    original,
    page.raw.length(),
    Some(page),
    { ..limits, max_work: work, },
  )
}

///|
/// Read-only nominal correspondence, not currentness, authority or a cleanup
/// acknowledgment. A separately admitted equal body remains another original.
pub fn notion_read_row_matches_observed_page(
  row : NotionReadRow,
  binding : NotionDataSourceReadContracts,
  page : OriginalNotionPage,
) -> Bool {
  read_row_is_original(row) &&
  physical_equal(row.binding, binding) &&
  match row.observed_page {
    Some(original) => physical_equal(original, page)
    None => false
  }
}

///|
/// Select a pending property from this already-issued row, retaining its exact
/// row/property/schema occurrence through the existing pagination algorithm.
/// An arbitrary page id, column tuple or matching wire cannot issue a request.
pub fn start_notion_read_row_property_item_request(
  row : NotionReadRow,
  column : Int,
  limits : NotionPropertyItemLimits,
) -> Result[NotionPropertyItemRequest, NotionPropertyItemIssue] {
  if !read_row_is_original(row) {
    return Err(ForeignOriginal)
  }
  if column < 0 || column >= row.binding.columns.length() {
    return Err(InvalidSelection)
  }
  if row.complete is Some(_) || row.cells[column] is Some(_) {
    return Err(InvalidSelection)
  }
  start_notion_column_property_item_request(
    row.binding,
    row.row,
    column,
    limits,
  )
}
