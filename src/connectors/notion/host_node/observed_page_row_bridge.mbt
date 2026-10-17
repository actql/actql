///|
#export_name("notionStartObservedPageReadRow")
pub fn notion_start_observed_page_read_row(
  binding : @catalog.NotionDataSourceReadContracts,
  page : @catalog.OriginalNotionPage,
  max_properties : Int,
  max_identity_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_text_bytes : Int,
  max_columns : Int,
  max_work : Int,
) -> Result[@catalog.NotionReadRow, @catalog.NotionReadRowIssue] {
  @catalog.start_notion_observed_page_read_row(
    binding,
    page,
    max_properties,
    max_identity_bytes,
    {
      values: { max_nodes, max_depth, max_text_bytes, },
      max_columns,
      max_work,
    },
  )
}

///|
#export_name("notionReadRowMatchesObservedPage")
pub fn notion_read_row_matches_observed_page(
  row : @catalog.NotionReadRow,
  binding : @catalog.NotionDataSourceReadContracts,
  page : @catalog.OriginalNotionPage,
) -> Bool {
  @catalog.notion_read_row_matches_observed_page(row, binding, page)
}

///|
#export_name("notionStartReadRowPropertyRequest")
pub fn notion_start_read_row_property_request(
  row : @catalog.NotionReadRow,
  column : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_data_sources : Int,
  max_properties : Int,
  max_identity_bytes : Int,
  max_name_bytes : Int,
  max_pages : Int,
  max_items : Int,
  max_total_bytes : Int,
  max_total_nodes : Int,
  max_total_text_bytes : Int,
  max_cursor_bytes : Int,
  max_work : Int,
) -> Result[
  @catalog.NotionPropertyItemRequest,
  @catalog.NotionPropertyItemIssue,
] {
  @catalog.start_notion_read_row_property_item_request(row, column, {
    metadata: {
      max_bytes,
      max_nodes,
      max_depth,
      max_data_sources,
      max_properties,
      max_identity_bytes,
      max_name_bytes,
    },
    max_pages,
    max_items,
    max_total_bytes,
    max_total_nodes,
    max_total_text_bytes,
    max_cursor_bytes,
    max_work,
  })
}
