///|
#export_name("notionProjectPage")
pub fn notion_project_page(
  body : Bytes,
  expected_page_id : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_data_sources : Int,
  max_properties : Int,
  max_identity_bytes : Int,
  max_name_bytes : Int,
  max_text_bytes : Int,
) -> Result[@catalog.OriginalNotionPage, @catalog.NotionPageIssue] {
  @catalog.project_notion_page(body, expected_page_id, {
    metadata: {
      max_bytes,
      max_nodes,
      max_depth,
      max_data_sources,
      max_properties,
      max_identity_bytes,
      max_name_bytes,
    },
    max_text_bytes,
  })
}

///|
#export_name("notionPageMetadataJson")
pub fn notion_page_metadata_json(
  page : @catalog.OriginalNotionPage,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.NotionPageIssue] {
  @catalog.notion_page_metadata_wire(page, max_bytes, max_nodes, max_depth)
}

///|
#export_name("notionPageOriginalJson")
pub fn notion_page_original_json(
  page : @catalog.OriginalNotionPage,
  max_bytes : Int,
) -> Result[String, @catalog.NotionPageIssue] {
  @catalog.notion_page_original_json(page, max_bytes)
}
