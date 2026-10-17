///|
#export_name("notionProjectQueryPage")
pub fn notion_project_query_page(
  source : @catalog.NotionDataSourceCatalog,
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_data_sources : Int,
  max_properties : Int,
  max_identity_bytes : Int,
  max_name_bytes : Int,
  max_rows : Int,
  max_cursor_bytes : Int,
) -> Result[@catalog.OriginalNotionQueryPage, @catalog.NotionQueryIssue] {
  @catalog.project_notion_query_page(source, bytes, {
    metadata: {
      max_bytes,
      max_nodes,
      max_depth,
      max_data_sources,
      max_properties,
      max_identity_bytes,
      max_name_bytes,
    },
    max_rows,
    max_cursor_bytes,
  })
}

///|
#export_name("notionQueryPageMatchesSource")
pub fn notion_query_page_matches_source(
  page : @catalog.OriginalNotionQueryPage,
  source : @catalog.NotionDataSourceCatalog,
) -> Bool {
  @catalog.notion_query_page_matches_source(page, source)
}

///|
#export_name("notionQueryPageMetadataJson")
pub fn notion_query_page_metadata_json(
  page : @catalog.OriginalNotionQueryPage,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.NotionQueryIssue] {
  @catalog.notion_query_page_metadata_wire(
    page, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("notionQueryPropertyValueJson")
pub fn notion_query_property_value_json(
  page : @catalog.OriginalNotionQueryPage,
  row : Int,
  property : Int,
  max_bytes : Int,
) -> Result[String, @catalog.NotionQueryIssue] {
  guard @catalog.notion_query_page_row_at(page, row) is Some(row) &&
    @catalog.notion_query_row_property_at(row, property) is Some(value) else {
    return Err(@catalog.InvalidProperty("index"))
  }
  @catalog.notion_query_property_value_json(value, max_bytes)
}

///|
#export_name("notionQueryPageOriginalJson")
pub fn notion_query_page_original_json(
  page : @catalog.OriginalNotionQueryPage,
  max_bytes : Int,
) -> Result[String, @catalog.NotionQueryIssue] {
  @catalog.notion_query_page_original_json(page, max_bytes)
}
