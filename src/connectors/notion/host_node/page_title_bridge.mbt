///|
#export_name("notionStartPageTitlePropertyRequest")
pub fn notion_start_page_title_property_request(
  page : @catalog.OriginalNotionPage,
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
  @catalog.start_notion_page_title_property_item_request(page, {
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
#export_name("notionPropertyRequestMatchesPageTitle")
pub fn notion_property_request_matches_page_title(
  request : @catalog.NotionPropertyItemRequest,
  page : @catalog.OriginalNotionPage,
) -> Bool {
  @catalog.notion_property_item_request_matches_page_title(request, page)
}

///|
#export_name("notionCompletedPageTitleJson")
pub fn notion_completed_page_title_json(
  original : @catalog.OriginalNotionPage,
  page : @catalog.NotionPropertyItemPage,
  admission_nodes : Int,
  admission_depth : Int,
  admission_text_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.NotionPropertyItemIssue] {
  @catalog.notion_completed_page_title_wire(
    original,
    page,
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
