///|
#export_name("notionStartColumnPropertyRequest")
pub fn notion_start_column_property_request(
  binding : @catalog.NotionDataSourceReadContracts,
  page : @catalog.OriginalNotionQueryPage,
  row_index : Int,
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
  guard @catalog.notion_query_page_row_at(page, row_index) is Some(row) else {
    return Err(@catalog.InvalidSelection)
  }
  @catalog.start_notion_column_property_item_request(binding, row, column, {
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

///|
#export_name("notionPropertyRequestMatchesBinding")
pub fn notion_property_request_matches_binding(
  request : @catalog.NotionPropertyItemRequest,
  binding : @catalog.NotionDataSourceReadContracts,
  column : Int,
) -> Bool {
  @catalog.notion_property_item_request_matches_binding(
    request, binding, column,
  )
}

///|
#export_name("notionPropertyRequestJson")
pub fn notion_property_request_json(
  request : @catalog.NotionPropertyItemRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.NotionPropertyItemIssue] {
  @catalog.notion_property_item_request_wire(
    request, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("notionProjectPropertyItemPage")
pub fn notion_project_property_item_page(
  request : @catalog.NotionPropertyItemRequest,
  bytes : Bytes,
) -> Result[@catalog.NotionPropertyItemPage, @catalog.NotionPropertyItemIssue] {
  @catalog.project_notion_property_item_page(request, bytes)
}

///|
#export_name("notionPropertyItemPageComplete")
pub fn notion_property_item_page_complete(
  page : @catalog.NotionPropertyItemPage,
) -> Bool {
  @catalog.notion_property_item_page_complete(page)
}

///|
#export_name("notionNextPropertyRequest")
pub fn notion_next_property_request(
  page : @catalog.NotionPropertyItemPage,
) -> Result[
  @catalog.NotionPropertyItemRequest,
  @catalog.NotionPropertyItemIssue,
] {
  match @catalog.next_notion_property_item_request(page) {
    Some(request) => Ok(request)
    None => Err(@catalog.InvalidSelection)
  }
}

///|
#export_name("notionCompletedPropertyJson")
pub fn notion_completed_property_json(
  binding : @catalog.NotionDataSourceReadContracts,
  page : @catalog.NotionPropertyItemPage,
  column : Int,
  admission_nodes : Int,
  admission_depth : Int,
  admission_text_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.NotionPropertyItemIssue] {
  @catalog.notion_completed_property_wire(
    binding,
    page,
    column,
    {
      max_nodes: admission_nodes,
      max_depth: admission_depth,
      max_text_bytes: admission_text_bytes,
    },
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
#export_name("notionPropertyItemOriginalJson")
pub fn notion_property_item_original_json(
  page : @catalog.NotionPropertyItemPage,
  max_bytes : Int,
) -> Result[String, @catalog.NotionPropertyItemIssue] {
  @catalog.notion_property_item_page_original_wire(page, max_bytes)
}
